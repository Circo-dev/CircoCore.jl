# SPDX-License-Identifier: LGPL-3.0-only
using Base.Threads

const MSG_BUFFER_SIZE = 10000

mutable struct HostActor <: AbstractActor
    core::CoreState
    HostActor() = new()
end

mutable struct HostService <: Plugin
    in_msg::Channel{Msg}
    iamzygote
    peers::Dict{PostCode,HostService}
    helper::Addr
    arrivals::Task
    postcode::PostCode
    HostService(;options=NamedTuple()) = new(
        Channel{Msg}(get(options, :buffer_size, MSG_BUFFER_SIZE)),
        get(options, :iamzygote, false),
        Dict()
    )
end

symbol(::HostService) = :host
postcode(hs::HostService) = hs.postcode
is_zygote(hs::HostService) = !isnothing(hs.zygote)

function Plugins.setup!(hs::HostService, scheduler)
    hs.postcode = postcode(scheduler)
    hs.helper = spawn(scheduler.service, HostActor())
end

function schedule_start(hs::HostService, scheduler)
    @debug "Host arrivals scheduled on $(Threads.threadid())"
    hs.arrivals = Task(()->arrivals(hs, scheduler))
    schedule(hs.arrivals)
end

function schedule_stop(hs::HostService, scheduler)
    @info "TODO: stop tasks"
end

function addpeers!(hs::HostService, peers::Array{HostService}, scheduler)
    for peer in peers
        if postcode(peer) != postcode(hs)
            hs.peers[postcode(peer)] = peer
        end
    end
    cluster = get(scheduler.plugins, :cluster, nothing)
    if !isnothing(cluster) && !hs.iamzygote && length(cluster.roots) == 0
        root = peers[1].postcode
        deliver!(scheduler, Msg(cluster.helper, ForceAddRoot(root))) # TODO avoid using the inner API
    end
end

function arrivals(hs::HostService, scheduler)
    while true
        msg = take!(hs.in_msg)
        @debug "arrived at $(hs.postcode): $msg"
        deliver!(scheduler, msg)
        yield()
    end
end

function hostroutes(hostservice::HostService, scheduler::AbstractActorScheduler, msg::AbstractMsg)::Bool
    @debug "hostroutes in host.jl $msg"
    peer = get(hostservice.peers, postcode(target(msg)), nothing)
    if !isnothing(peer)
        @debug "Inter-thread delivery of $(hostservice.postcode): $msg"
        put!(peer.in_msg, msg)
        return true
    end
    return false
end

struct Host
    schedulers::Array{ActorScheduler}
end

function Host(threadcount::Int, pluginsfun; options=NamedTuple())
    schedulers = create_schedulers(threadcount, pluginsfun, options)
    hostservices = [scheduler.plugins[:host] for scheduler in schedulers]
    addpeers(hostservices, schedulers)
    return Host(schedulers)
end

function create_schedulers(threadcount::Number, pluginsfun, options)
    zygote = get(options, :zygote, [])
    schedulers = []
    for i = 1:threadcount
        iamzygote = i == 1
        myzygote = iamzygote ? zygote : nothing
        scheduler = ActorScheduler(myzygote;plugins=[HostService(;options=(iamzygote = iamzygote, options...)), pluginsfun(;options=options)...])
        push!(schedulers, scheduler)
    end
    return schedulers
end

function addpeers(hostservices::Array{HostService}, schedulers)
    for i in 1:length(hostservices)
        addpeers!(hostservices[i], hostservices, schedulers[i])
    end
end

function (ts::Host)(;process_external=true, exit_when_done=false)
    tasks = [(Threads.@spawn scheduler(;process_external=process_external, exit_when_done=exit_when_done)) for scheduler in ts.schedulers]
    for task in tasks
        wait(task)
    end
    return nothing
end

function (host::Host)(message::AbstractMsg;process_external=true, exit_when_done=false)
    deliver!(host.schedulers[1], message)
    host(;process_external=process_external,exit_when_done=exit_when_done)
    return nothing
end

function shutdown!(host::Host)
    for scheduler in host.schedulers
        shutdown!(scheduler)
    end
end