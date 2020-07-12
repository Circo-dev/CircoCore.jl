# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures, Dates

const VIEW_SIZE = 1000 # TODO eliminate
const VIEW_HEIGHT = VIEW_SIZE

const TIMEOUTCHECK_INTERVAL = Second(1)

# Lifecycle hooks
schedule_start(::Plugin, ::Any) = false
schedule_stop(::Plugin, ::Any) = false

schedule_stop_hook = Plugins.create_lifecyclehook(schedule_stop)
schedule_start_hook = Plugins.create_lifecyclehook(schedule_start)

# Event hooks
hostroutes(::Plugin, ::Any, ::Any) = false
localroutes(::Plugin, ::Any, ::Any) = false
actor_activity_sparse(::Plugin, ::Any, ::Any) = false

scheduler_hooks = [hostroutes, localroutes, actor_activity_sparse]

function getpos(port) 
    # return randpos()
    port == 24721 && return Pos(-1, 0, 0) * VIEW_SIZE
    port == 24722 && return Pos(1, 0, 0) * VIEW_SIZE
    port == 24723 && return Pos(0, -1, 0) * VIEW_SIZE
    port == 24724 && return Pos(0, 1, 0) * VIEW_SIZE
    port == 24725 && return Pos(0, 0, -1) * VIEW_SIZE
    port == 24726 && return Pos(0, 0, 1) * VIEW_SIZE
    return randpos()
end

mutable struct ActorScheduler <: AbstractActorScheduler
    pos::Pos
    postoffice::PostOffice
    actorcount::UInt64
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::CircularBuffer{Msg}
    registry::LocalRegistry
    tokenservice::TokenService
    next_timeoutcheck_ts::DateTime
    shutdown::Bool # shutdown in progress or done
    startup_actor_count::UInt16 # Number of actors created by plugins
    plugins::PluginStack
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::Union{AbstractArray,Nothing} = nothing;plugins = default_plugins(), pos = nothing, msgqueue_capacity = 100_000)
        if isnothing(actors) 
            actors = []
        end
        postoffice = PostOffice()
        if isnothing(pos)# TODO scheduler positioning
            pos = getpos(port(postoffice.postcode))
        end
        scheduler = new(pos, postoffice, 0, Dict{ActorId,AbstractActor}([]), CircularBuffer{Msg}(msgqueue_capacity),
         LocalRegistry(), TokenService(), Dates.now() + TIMEOUTCHECK_INTERVAL, 0, false, PluginStack(plugins, scheduler_hooks))
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        setup!(scheduler.plugins, scheduler)
        scheduler.startup_actor_count = scheduler.actorcount
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

pos(scheduler::AbstractActorScheduler) = scheduler.pos

function default_plugins(;options = NamedTuple())
    return [ClusterService(;options = options), MigrationService(;options = options), WebsocketService(;options = options)]
end

function randpos()
    return Pos(rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_HEIGHT - VIEW_HEIGHT / 2)
end

@inline function deliver!(scheduler::ActorScheduler, message::AbstractMsg)
    # Disabled as degrades the ping-pong performance even if debugging is not enabled:
    # @debug "deliver! at $(postcode(scheduler)) $message"
    target_postcode = postcode(target(message))
    if postcode(scheduler) === target_postcode
        deliver_locally!(scheduler, message)
        return nothing
    end
    if network_host(postcode(scheduler)) == network_host(target_postcode)
        if deliver_onhost!(scheduler, message)
            return nothing
        end
    end
    send(scheduler.postoffice, message)
    return nothing
end

@inline function deliver_onhost!(scheduler::ActorScheduler, msg::AbstractMsg)
    if !hooks(scheduler).hostroutes(msg)
        @debug "Unhandled host delivery: $msg"
        return false
    end
    return true
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::AbstractMsg)
    deliver_nonresponse_locally!(scheduler, message)
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::Msg{<:Response})
    cleartimeout(scheduler.tokenservice, token(message.body), target(message))
    deliver_nonresponse_locally!(scheduler, message)
    return nothing
end

@inline function deliver_nonresponse_locally!(scheduler::ActorScheduler, message::AbstractMsg)
    if box(target(message)) == 0
        handle_special!(scheduler, message)
    else
        push!(scheduler.messagequeue, message)
    end
    return nothing
end

@inline function fill_corestate!(scheduler::ActorScheduler, actor::AbstractActor)
    actorid, actorpos = isdefined(actor, :core) ? (id(actor), pos(actor)) : (rand(ActorId), Pos(rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_HEIGHT - VIEW_HEIGHT / 2))
    actor.core = CoreState(Addr(postcode(scheduler.postoffice), actorid), actorpos)
    return nothing
end

@inline isscheduled(scheduler::ActorScheduler, actor::AbstractActor) = haskey(scheduler.actorcache, id(actor))

@inline function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Addr
    isfirstschedule = !isdefined(actor, :core)
    if !isfirstschedule && isscheduled(scheduler, actor) 
        return addr(actor)
    end
    fill_corestate!(scheduler, actor)
    scheduler.actorcache[id(actor)] = actor
    scheduler.actorcount += 1
    isfirstschedule && onschedule(actor, scheduler.service)
    return addr(actor)
end

@inline function unschedule!(scheduler::ActorScheduler, actor::AbstractActor)
    isscheduled(scheduler, actor) || return nothing
    delete!(scheduler.actorcache, id(actor))
    scheduler.actorcount -= 1
    return nothing
end

@inline function scheduler_infoton(scheduler, actor::AbstractActor)
    diff = scheduler.pos - actor.core.pos
    distfromtarget = 2000 - norm(diff) # TODO configuration +easy redefinition from applications (including turning it off completely?)
    energy = sign(distfromtarget) * distfromtarget * distfromtarget * -2e-6
    return Infoton(scheduler.pos, energy)
end

@inline function handle_message_locally!(targetactor::AbstractActor, message::Msg, scheduler::ActorScheduler)
    onmessage(targetactor, body(message), scheduler.service)
    apply_infoton(targetactor, message.infoton)
    if rand(UInt8) < 30 # TODO: config and move to a hook
        apply_infoton(targetactor, scheduler_infoton(scheduler, targetactor))
        if rand(UInt8) < 15
            hooks(scheduler).actor_activity_sparse(targetactor)
        end
    end
    return nothing
end

@inline function step!(scheduler::ActorScheduler)
    message = popfirst!(scheduler.messagequeue)
    targetactor = get(scheduler.actorcache, target(message).box, nothing)
    if isnothing(targetactor)
        if !hooks(scheduler).localroutes(message)
            @debug "Cannot deliver on host: $message"
        end
    else
        handle_message_locally!(targetactor, message, scheduler)
    end
    return nothing
end

@inline function checktimeouts(scheduler::ActorScheduler)
    if scheduler.next_timeoutcheck_ts > Dates.now()
        return false
    end
    scheduler.next_timeoutcheck_ts = Dates.now() + TIMEOUTCHECK_INTERVAL
    firedtimeouts = poptimeouts!(scheduler.tokenservice)
    if length(firedtimeouts) > 0
        println("Fired timeouts: $firedtimeouts")
        for timeout in firedtimeouts
            deliver_locally!(scheduler, Msg(
                addr(scheduler),
                timeout.watcher,
                timeout,
                Infoton(nullpos)# TODO scheduler pos
            ))
        end
        return true
    end
    return false
end

@inline function process_post_and_timeout(scheduler::ActorScheduler)
    incomingmessage = nothing
    hadtimeout = false
    sleeplength = 0.001
    enter_ts = time_ns()
    while true
        yield() # Allow the postoffice "arrivals" and plugin tasks to run
        incomingmessage = getmessage(scheduler.postoffice)
        hadtimeout = checktimeouts(scheduler)
        if !isnothing(incomingmessage)
            deliver_locally!(scheduler, incomingmessage)
            return nothing
        elseif hadtimeout ||
                !isempty(scheduler.messagequeue) ||# Plugins may deliver messages directly
                scheduler.shutdown
            return nothing
        else
            if time_ns() - enter_ts > 1_000_000
                sleep(sleeplength)
                sleeplength = min(sleeplength * 1.002, 0.03)
            end
        end
    end
end

function (scheduler::ActorScheduler)(message::AbstractMsg;process_external = false, exit_when_done = true)
    deliver!(scheduler, message)
    scheduler(process_external = process_external, exit_when_done = exit_when_done)
end

@inline function nomorework(scheduler::ActorScheduler, process_external::Bool, exit_when_done::Bool)
    return isempty(scheduler.messagequeue) &&
        (
            !process_external ||
            exit_when_done && scheduler.actorcount == scheduler.startup_actor_count
        )
end

function (scheduler::ActorScheduler)(;process_external = true, exit_when_done = false)
    schedule_start_hook(scheduler.plugins, scheduler)
    while true
        msg_batch::UInt8 = 255
        while msg_batch != 0 && !isempty(scheduler.messagequeue)
            msg_batch -= 1
            step!(scheduler)
        end
        if scheduler.shutdown || nomorework(scheduler, process_external, exit_when_done)
            @debug "Scheduler loop $(postcode(scheduler)) exiting."
            return
        end
        process_post_and_timeout(scheduler)
    end
    schedule_stop_hook(scheduler.plugins, scheduler)
end

function shutdown!(scheduler::ActorScheduler)
    scheduler.shutdown = true
    Plugins.shutdown!(scheduler.plugins, scheduler)
    shutdown!(scheduler.postoffice)
    println("Scheduler at $(postcode(scheduler)) exited.")
end

# Helpers for plugins
getactorbyid(scheduler::AbstractActorScheduler, id::ActorId) = get(scheduler.actorcache, id, nothing)