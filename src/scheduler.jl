# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures

const VIEW_SIZE = 1000 # TODO eliminate
const VIEW_HEIGHT = VIEW_SIZE

const TIMEOUTCHECK_INTERVAL = 1.0

function getpos(postcode)
    # return randpos()
    p = port(postcode)
    p == 24721 && return Pos(-1, 0, 0) * VIEW_SIZE
    p == 24722 && return Pos(1, 0, 0) * VIEW_SIZE
    p == 24723 && return Pos(0, -1, 0) * VIEW_SIZE
    p == 24724 && return Pos(0, 1, 0) * VIEW_SIZE
    p == 24725 && return Pos(0, 0, -1) * VIEW_SIZE
    p == 24726 && return Pos(0, 0, 1) * VIEW_SIZE
    return randpos()
end

mutable struct ActorScheduler <: AbstractActorScheduler
    pos::Pos
    postcode::PostCode
    actorcount::UInt64
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::Deque{Msg}# CircularBuffer{Msg}
    tokenservice::TokenService
    next_timeoutcheck_ts::Float64
    shutdown::Bool # shutdown in progress or done
    startup_actor_count::UInt16 # Number of actors created by plugins
    plugins::PluginStack
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::Union{AbstractArray,Nothing} = nothing;plugins = core_plugins(), pos = nothing, msgqueue_capacity = 100_000)
        if isnothing(actors)
            actors = []
        end
        stack = PluginStack(plugins, scheduler_hooks)
        postoffice = get(stack, :postoffice, nothing)
        schedulerpostcode = isnothing(postoffice) ? invalidpostcode : postcode(postoffice)
        if isnothing(pos)# TODO scheduler positioning
            pos = getpos(schedulerpostcode)
        end
        scheduler = new(
            pos,
            schedulerpostcode,
            0,
            Dict{ActorId,AbstractActor}([]),
            Deque{Msg}(),#msgqueue_capacity),
            TokenService(),
            Base.Libc.time() + TIMEOUTCHECK_INTERVAL,
            0,
            false,
            stack)
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        call_lifecycle_hook(scheduler, Plugins.setup!, "setup")
        scheduler.startup_actor_count = scheduler.actorcount
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

pos(scheduler::AbstractActorScheduler) = scheduler.pos
postcode(scheduler::AbstractActorScheduler) = scheduler.postcode

function core_plugins(;options = NamedTuple())
    return [LocalRegistry(), PostOffice(), ActivityService(), Space()]
end

function randpos()
    return Pos(rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_HEIGHT - VIEW_HEIGHT / 2)
end

function call_lifecycle_hook(scheduler, lfhook, hookname)
    res = lfhook(scheduler.plugins, scheduler)
    if !res.allok
        for (i, result) in enumerate(res.results)
            if result isa Tuple && result[1] isa Exception
                @error "Error in calling '$hookname' lifecycle hook of plugin $(typeof(scheduler.plugins[i])):" result
            end
        end
    end
end

@inline function deliver!(scheduler::ActorScheduler, msg::AbstractMsg)
    # Disabled as degrades the ping-pong performance even if debugging is not enabled:
    # @debug "deliver! at $(postcode(scheduler)) $msg"
    target_postcode = postcode(target(msg))
    if postcode(scheduler) === target_postcode
        deliver_locally!(scheduler, msg)
        return nothing
    end
    if !hooks(scheduler).remoteroutes(msg)
        @info "Unhandled remote delivery: $msg"
    end
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::AbstractMsg)
    deliver_locally_kern!(scheduler, message)
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::Msg{<:Response})
    cleartimeout(scheduler.tokenservice, token(message.body), target(message))
    deliver_locally_kern!(scheduler, message)
    return nothing
end

@inline function deliver_locally_kern!(scheduler::ActorScheduler, message::AbstractMsg)
    if box(target(message)) == 0
        handle_special!(scheduler, message)
    else
        push!(scheduler.messagequeue, message)
    end
    return nothing
end

@inline function fill_corestate!(scheduler::ActorScheduler, actor::AbstractActor)
    actorid, actorpos = isdefined(actor, :core) ? (box(actor), pos(actor)) : (rand(ActorId), Pos(rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_HEIGHT - VIEW_HEIGHT / 2))
    actor.core = CoreState(Addr(postcode(scheduler.plugins[:postoffice]), actorid), actorpos)
    return nothing
end

@inline isscheduled(scheduler::ActorScheduler, actor::AbstractActor) = haskey(scheduler.actorcache, box(actor))

# Provide the same API for plugins
spawn(scheduler::ActorScheduler, actor::AbstractActor) = schedule!(scheduler, actor)

@inline function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Addr
    isfirstschedule = !isdefined(actor, :core)
    if !isfirstschedule && isscheduled(scheduler, actor)
        return addr(actor)
    end
    fill_corestate!(scheduler, actor)
    scheduler.actorcache[box(actor)] = actor
    scheduler.actorcount += 1
    isfirstschedule && onschedule(actor, scheduler.service)
    return addr(actor)
end

@inline function unschedule!(scheduler::ActorScheduler, actor::AbstractActor)
    isscheduled(scheduler, actor) || return nothing
    delete!(scheduler.actorcache, box(actor))
    scheduler.actorcount -= 1
    return nothing
end

# Not clear why: without this on 1.4.2 the hook is dynamically dispatched when two arguments are used.
# (With one argument it works correctly, just like in Plugins.jl 06e10515 tests)
call_twoargs(op, msg, targetactor) = op(msg, targetactor)

@inline function handle_message_locally!(targetactor::AbstractActor, message::Msg, scheduler::ActorScheduler)
    onmessage(targetactor, body(message), scheduler.service)
    call_twoargs(hooks(scheduler).localdelivery, message, targetactor)
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
    ts = Base.Libc.time()
    if scheduler.next_timeoutcheck_ts > ts
        return false
    end
    scheduler.next_timeoutcheck_ts = ts + TIMEOUTCHECK_INTERVAL
    firedtimeouts = poptimeouts!(scheduler.tokenservice, ts)
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
        hooks(scheduler).letin_remote()
        hadtimeout = checktimeouts(scheduler)
        if hadtimeout ||
                !isempty(scheduler.messagequeue) ||
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
    try
        @info "Scheduler starting on thread $(Threads.threadid())"
        call_lifecycle_hook(scheduler, schedule_start_hook, "schedule_start")
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
    catch e
        @error "Error while scheduling on thread $(Threads.threadid())" exception = (e, catch_backtrace())
    finally
        call_lifecycle_hook(scheduler, schedule_stop_hook, "schedule_stop")
    end
end

function shutdown!(scheduler::ActorScheduler) # TODO Plugins.shutdown! and CircoCore.shutdown should have different names
    scheduler.shutdown = true
    call_lifecycle_hook(scheduler, Plugins.shutdown!, "shutdown!")
    println("Scheduler at $(postcode(scheduler)) exited.")
end

# Helpers for plugins
getactorbyid(scheduler::AbstractActorScheduler, id::ActorId) = get(scheduler.actorcache, id, nothing)
