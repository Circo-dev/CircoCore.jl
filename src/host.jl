# SPDX-License-Identifier: LGPL-3.0-only
using Base.Threads

const MSG_BUFFER_SIZE = 10000

mutable struct HostService <: Plugin
    iamzygote
    in_msg::Channel{Msg}
    peers::Dict{PostCode,HostService}
    arrivals::Task
    postcode::PostCode
    HostService(;options=NamedTuple()) = new(
        get(options, :iamzygote, false),
        Channel{Msg}(get(options, :buffer_size, MSG_BUFFER_SIZE)),
        Dict()
    )
end

symbol(::HostService) = :host
postcode(hs::HostService) = hs.postcode
is_zygote(hs::HostService) = !isnothing(hs.zygote)

function Plugins.setup!(hs::HostService, scheduler)
    hs.postcode = postcode(scheduler)
    hs.arrivals = Task(()->arrivals(hs, scheduler))
    schedule(hs.arrivals)
end

function addpeers!(hs::HostService, peers::Array{HostService})
    for peer in peers
        if postcode(peer) != postcode(hs)
            hs.peers[postcode(peer)] = peer
        end
    end
end

function arrivals(hs::HostService, scheduler)
    while true
        msg = take!(hs.in_msg)
        @debug "arrived at $(hs.postcode): $msg"
        deliver!(scheduler, msg)
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
    addpeers(hostservices)
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

function addpeers(hostservices::Array{HostService})
    for hostservice in hostservices
        addpeers!(hostservice, hostservices)
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