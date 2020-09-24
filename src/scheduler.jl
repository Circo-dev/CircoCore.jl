# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures

mutable struct ActorScheduler{THooks, TMsg, TCoreState} <: AbstractActorScheduler{TCoreState}
    pos::Pos
    postcode::PostCode
    actorcount::UInt64
    actorcache::Dict{ActorId, Any}
    msgqueue::Deque{Any}# CircularBuffer{Msg}
    tokenservice::TokenService
    shutdown::Bool # shutdown in progress or done
    startup_actor_count::UInt16 # Number of actors created by plugins
    plugins::Plugins.PluginStack
    hooks::THooks
    service::ActorService{ActorScheduler{THooks, TMsg, TCoreState}, TMsg, TCoreState}
    function ActorScheduler(
        ctx::AbstractContext,
        actors::AbstractArray = [];
        pos = nullpos,
        # msgqueue_capacity = 100_000
    )
        plugins = instantiate_plugins(ctx)
        _hooks = hooks(plugins)
        postoffice = get(plugins, :postoffice, nothing)
        schedulerpostcode = isnothing(postoffice) ? invalidpostcode : postcode(postoffice)
        scheduler = new{typeof(_hooks), ctx.msg_type, ctx.corestate_type}(
            pos,
            schedulerpostcode,
            0,
            Dict([]),
            Deque{Any}(),#msgqueue_capacity),
            TokenService(),
            0,
            false,
            plugins,
            _hooks)
        scheduler.service = ActorService(ctx, scheduler)
        call_lifecycle_hook(scheduler, setup!)
        scheduler.startup_actor_count = scheduler.actorcount
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

Base.show(io::IO, ::Type{<:ActorScheduler}) = print(io, "ActorScheduler")
Base.show(io::IO, ::MIME"text/plain", scheduler::ActorScheduler) = begin
    print(io, "ActorScheduler at $(postcode(scheduler)) with $(scheduler.actorcount) actors")
end

pos(scheduler::AbstractActorScheduler) = scheduler.pos
postcode(scheduler::AbstractActorScheduler) = scheduler.postcode

function call_lifecycle_hook(scheduler, lfhook)
    res = lfhook(scheduler.plugins, scheduler)
    if !res.allok
        for (i, result) in enumerate(res.results)
            if result isa Tuple && result[1] isa Exception
                trimhook(s) = endswith(s, "_hook") ? s[1:end-5] : s
                @error "Error in calling '$(trimhook(string(lfhook)))' lifecycle hook of plugin $(typeof(scheduler.plugins[i])):" result
            end
        end
    end
end

# For external calls
function deliver!(scheduler::ActorScheduler{THooks, TMsg, TCoreState}, to::Addr, msgbody; kwargs...) where {THooks, TMsg, TCoreState}
    msg = TMsg(Addr(), to, msgbody, scheduler; kwargs...)
    deliver!(scheduler, msg)
end

@inline function deliver!(scheduler::ActorScheduler, msg::AbstractMsg)
    # Disabled as degrades the ping-pong performance even if debugging is not enabled:
    # @debug "deliver! at $(postcode(scheduler)) $msg"
    target_postcode = postcode(target(msg))
    if postcode(scheduler) === target_postcode
        deliver_locally!(scheduler, msg)
        return nothing
    end
    if !scheduler.hooks.remoteroutes(scheduler, msg)
        @info "Unhandled remote delivery: $msg"
    end
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, msg::AbstractMsg)
    deliver_locally_kern!(scheduler, msg)
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, msg::AbstractMsg{<:Response})
    cleartimeout(scheduler.tokenservice, token(msg.body), target(msg))
    deliver_locally_kern!(scheduler, msg)
    return nothing
end

@inline function deliver_locally_kern!(scheduler::ActorScheduler, msg::AbstractMsg)
    if box(target(msg)) == 0 # TODO always push, check later only if target not found
        if !scheduler.hooks.specialmsg(scheduler, msg)
            @debug("Unhandled special message: $msg")
        end
    else
        push!(scheduler.msgqueue, msg)
    end
    return nothing
end

@inline function fill_corestate!(scheduler::AbstractActorScheduler{TCoreState}, actor) where TCoreState
    actorid = !isdefined(actor, :core) || box(actor) == 0 ? rand(ActorId) : box(actor)
    actor.core = TCoreState(scheduler, actor, actorid)
    return nothing
end

@inline isscheduled(scheduler::ActorScheduler, actor::AbstractActor) = haskey(scheduler.actorcache, box(actor))

# Provide the same API for plugins
spawn(scheduler::ActorScheduler, actor::AbstractActor) = schedule!(scheduler, actor)

@inline function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Addr
    isfirstschedule = !isdefined(actor, :core) || box(actor) == 0
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

@inline function step!(scheduler::ActorScheduler)
    msg = popfirst!(scheduler.msgqueue)
    # Tried to insert a second kern here, but it degraded perf on 1.5.1
    targetbox = target(msg).box
    targetactor = get(scheduler.actorcache, targetbox, nothing)
    step_kern!(scheduler, msg, targetactor)
    return nothing
end

@inline function step_kern!(scheduler, msg, targetactor)
    if isnothing(targetactor)
        if !scheduler.hooks.localroutes(scheduler, msg)
            @debug "Cannot deliver on host: $msg"
        end
    else
        scheduler.hooks.localdelivery(scheduler, msg, targetactor)
    end
    return nothing
end

@inline function checktimeouts(scheduler::ActorScheduler{THooks, TMsg, TCoreState}) where {THooks, TMsg, TCoreState}
    needchecktimeouts!(scheduler.tokenservice) || return false
    firedtimeouts = poptimeouts!(scheduler.tokenservice)
    if length(firedtimeouts) > 0
        @debug "Fired timeouts: $firedtimeouts"
        for timeout in firedtimeouts
            deliver_locally!(scheduler, TMsg(
                addr(scheduler),
                timeout.watcher,
                timeout,
                scheduler)
            )
        end
        return true
    end
    return false
end


@inline function process_post_and_timeout(scheduler::ActorScheduler)
    incomingmsg = nothing
    hadtimeout = false
    sleeplength = 0.001
    enter_ts = time_ns()
    while true
        yield() # Allow plugin tasks to run
        scheduler.hooks.letin_remote(scheduler)
        hadtimeout = checktimeouts(scheduler)
        if hadtimeout ||
                !isempty(scheduler.msgqueue) ||
                scheduler.shutdown
            return nothing
        else
            if time_ns() - enter_ts > 1_000_000
                try
                    sleep(sleeplength)
                catch e # EOFError happens
                    if e isa InterruptException
                        @info "hjoh"
                        rethrow(e)
                    else
                        @info "Exception while sleeping: $e"
                    end
                end
                sleeplength = min(sleeplength * 1.002, 0.03)
            end
        end
    end
end

@inline function nomorework(scheduler::ActorScheduler, process_external::Bool, exit_when_done::Bool)
    return isempty(scheduler.msgqueue) &&
        (
            !process_external ||
            exit_when_done && scheduler.actorcount <= scheduler.startup_actor_count
        )
end

function (scheduler::ActorScheduler)(msgs;process_external = false, exit_when_done = true)
    if msgs isa AbstractMsg
        msgs = [msgs]
    end
    for msg in msgs
        deliver!(scheduler, msg)
    end
    scheduler(;process_external = process_external, exit_when_done = exit_when_done)
end

function (scheduler::ActorScheduler)(;process_external = true, exit_when_done = false)
    try
        @info "Scheduler starting on thread $(Threads.threadid())"
        call_lifecycle_hook(scheduler, schedule_start_hook)
        while true
            msg_batch::UInt8 = 255
            while msg_batch != 0 && !isempty(scheduler.msgqueue)
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
        if e isa InterruptException
            @info "Interrupt to scheduler on thread $(Threads.threadid())"
        else
            @error "Error while scheduling on thread $(Threads.threadid())" exception = (e, catch_backtrace())
        end
    finally
        call_lifecycle_hook(scheduler, schedule_stop_hook)
    end
end

function shutdown!(scheduler::ActorScheduler)
    scheduler.shutdown = true
    call_lifecycle_hook(scheduler, shutdown!)
    @debug "Scheduler at $(postcode(scheduler)) exited."
end

# Helpers for plugins
getactorbyid(scheduler::AbstractActorScheduler, id::ActorId) = get(scheduler.actorcache, id, nothing)
