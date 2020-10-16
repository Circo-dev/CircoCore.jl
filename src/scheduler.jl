# SPDX-License-Identifier: MPL-2.0
using DataStructures

@enum SchedulerState::Int8 created=0 running=10 paused=20 stopped=30
struct StateChangeError <: Exception
    from::SchedulerState
    to::SchedulerState
end

mutable struct Scheduler{THooks, TMsg, TCoreState} <: AbstractScheduler{TCoreState}
    pos::Pos
    postcode::PostCode
    actorcount::UInt64
    actorcache::Dict{ActorId, Any}
    msgqueue::Deque{Any}# CircularBuffer{Msg}
    tokenservice::TokenService
    state::SchedulerState # shutdown in progress or done
    runopts::NamedTuple
    lock::ReentrantLock
    startcond::Threads.Condition
    pausecond::Threads.Condition
    startup_actor_count::UInt16 # Number of actors created by plugins
    plugins::Plugins.PluginStack
    hooks::THooks
    service::Service{Scheduler{THooks, TMsg, TCoreState}, TMsg, TCoreState}
    function Scheduler(
        ctx::AbstractContext,
        actors::AbstractArray = [];
        pos = nullpos, # TODO: eliminate
        # msgqueue_capacity = 100_000
    )
        plugins = instantiate_plugins(ctx)
        _hooks = hooks(plugins)
        _lock = ReentrantLock()
        scheduler = new{typeof(_hooks), ctx.msg_type, ctx.corestate_type}(
            pos,
            invalidpostcode,
            0,
            Dict([]),
            Deque{Any}(),#msgqueue_capacity),
            TokenService(),
            created,
            NamedTuple(),
            _lock,
            Threads.Condition(_lock),
            Threads.Condition(_lock),
            0,
            plugins,
            _hooks)
        scheduler.service = Service(ctx, scheduler)
        call_lifecycle_hook(scheduler, setup!)
        postoffice = get(plugins, :postoffice, nothing)
        scheduler.postcode = isnothing(postoffice) ? invalidpostcode : postcode(postoffice)
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

Base.show(io::IO, ::Type{<:Scheduler}) = print(io, "Scheduler")
Base.show(io::IO, ::MIME"text/plain", scheduler::Scheduler) = begin
    print(io, "Scheduler at $(postcode(scheduler)) with $(scheduler.actorcount) actors")
end

pos(scheduler::AbstractScheduler) = scheduler.pos
postcode(scheduler::AbstractScheduler) = scheduler.postcode

function setstate!(scheduler::AbstractScheduler, newstate::SchedulerState)
    callcount = 0
    callhook(hook) = begin
        call_lifecycle_hook(scheduler, hook)
        callcount += 1
    end
    curstate = scheduler.state
    curstate == newstate && return newstate

    if newstate == running
        if curstate == created || curstate == stopped
            actorcount = scheduler.actorcount
            callhook(schedule_start_hook)
            callhook(schedule_continue_hook)
            scheduler.startup_actor_count = scheduler.actorcount - actorcount# TODO not just count and not here
        elseif curstate == paused
            callhook(schedule_continue_hook)
        end
    elseif newstate == paused
        if curstate == running
            callhook(schedule_pause_hook)
        end
    elseif newstate == stopped
        if curstate == running
            callhook(schedule_pause_hook)
            callhook(schedule_stop_hook)
        elseif curstate == paused || curstate == created
            callhook(schedule_stop_hook)
        end
    end
    callcount == 0 && throw(StateChangeError(scheduler.state, newstate))
    scheduler.state = newstate
    return newstate
end

function _lockop(op::Function, scheduler, cond_sym::Symbol)
    cond = getfield(scheduler, cond_sym)
    lock(cond)
    try
        op(cond)
    finally
        unlock(cond)
    end
end

function pause!(scheduler)
    setstate!(scheduler, paused)
    _lockop(wait, scheduler, :pausecond)
    return nothing
end

logstart(scheduler::Scheduler) = scheduler.state == created && @info "Scheduler starting on thread $(Threads.threadid())"

function run!(scheduler; nowait = false, kwargs...)
    isrunning(scheduler) && throw(StateChangeError(scheduler.state, running))
    logstart(scheduler)
    task = @async eventloop(scheduler; kwargs...)
    nowait && return task
    _lockop(wait, scheduler, :startcond)
    return task
end

isrunning(scheduler) = scheduler.state == running

# For external calls
function send(scheduler::Scheduler, to::AbstractActor, msgbody; kwargs...)
    send(scheduler, addr(to), msgbody; kwargs...)
end
function send(scheduler::Scheduler{THooks, TMsg, TCoreState}, to::Addr, msgbody; kwargs...) where {THooks, TMsg, TCoreState}
    msg = TMsg(Addr(), to, msgbody, scheduler; kwargs...)
    deliver!(scheduler, msg)
end

@inline function deliver!(scheduler::Scheduler, msg::AbstractMsg)
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

@inline function deliver_locally!(scheduler::Scheduler, msg::AbstractMsg)
    deliver_locally_kern!(scheduler, msg)
    return nothing
end

@inline function deliver_locally!(scheduler::Scheduler, msg::AbstractMsg{<:Response})
    cleartimeout(scheduler.tokenservice, token(msg.body), target(msg))
    deliver_locally_kern!(scheduler, msg)
    return nothing
end

@inline function deliver_locally_kern!(scheduler::Scheduler, msg::AbstractMsg)
    if box(target(msg)) == 0 # TODO always push, check later only if target not found
        if !scheduler.hooks.specialmsg(scheduler, msg)
            @debug("Unhandled special message: $msg")
        end
    else
        push!(scheduler.msgqueue, msg)
    end
    return nothing
end

@inline function fill_corestate!(scheduler::AbstractScheduler{TCoreState}, actor) where TCoreState
    actorid = !isdefined(actor, :core) || box(actor) == 0 ? rand(ActorId) : box(actor)
    actor.core = TCoreState(scheduler, actor, actorid)
    return nothing
end

@inline isscheduled(scheduler::Scheduler, actor::AbstractActor) = haskey(scheduler.actorcache, box(actor))

# Provide the same API for plugins
spawn(scheduler::Scheduler, actor::AbstractActor) = schedule!(scheduler, actor)

@inline function schedule!(scheduler::Scheduler, actor::AbstractActor)::Addr
    isfirstschedule = !isdefined(actor, :core) || box(actor) == 0
    if !isfirstschedule && isscheduled(scheduler, actor)
        return addr(actor)
    end
    fill_corestate!(scheduler, actor)
    scheduler.actorcache[box(actor)] = actor
    scheduler.actorcount += 1
    isfirstschedule && onspawn(actor, scheduler.service)
    return addr(actor)
end

@inline function unschedule!(scheduler::Scheduler, actor::AbstractActor)
    isscheduled(scheduler, actor) || return nothing
    delete!(scheduler.actorcache, box(actor))
    scheduler.actorcount -= 1
    return nothing
end

@inline function step!(scheduler::Scheduler{THooks, TMsg, TCoreState}) where {THooks, TMsg, TCoreState}
    msg = popfirst!(scheduler.msgqueue)
    step_kern1!(msg, scheduler) # This outer kern degrades perf on 1.5, but not on 1.4
    return nothing
end

@inline function step_kern1!(msg, scheduler)
    targetbox = target(msg).box
    targetactor = get(scheduler.actorcache, targetbox, nothing)
    step_kern!(scheduler, msg, targetactor)
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

@inline function checktimeouts(scheduler::Scheduler{THooks, TMsg, TCoreState}) where {THooks, TMsg, TCoreState}
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


@inline function process_post_and_timeout(scheduler::Scheduler)
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
                !isrunning(scheduler)
            return nothing
        else
            if time_ns() - enter_ts > 1_000_000
                try
                    sleep(sleeplength)
                catch e # EOFError happens
                    if e isa InterruptException
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

@inline function nomorework(scheduler::Scheduler, remote::Bool, exit::Bool)
    return isempty(scheduler.msgqueue) &&
        (
            !remote ||
            exit && scheduler.actorcount <= scheduler.startup_actor_count
        )
end

function (scheduler::Scheduler)(msgs;remote = false, exit = true)
    if msgs isa AbstractMsg
        msgs = [msgs]
    end
    for msg in msgs
        deliver!(scheduler, msg)
    end
    scheduler(;remote = remote, exit = exit)
end

function eventloop(scheduler::Scheduler; remote = true, exit = false)
    try
        setstate!(scheduler, running)
        _lockop(notify, scheduler, :startcond)
        while true
            msg_batch::UInt8 = 255
            while msg_batch != 0 && !isempty(scheduler.msgqueue)
                msg_batch -= 1
                step!(scheduler)
            end
            if !isrunning(scheduler) || nomorework(scheduler, remote, exit)
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
        isrunning(scheduler) && setstate!(scheduler, paused)
        _lockop(notify, scheduler, :pausecond)
    end
end

function (scheduler::Scheduler)(;remote = true, exit = false)
    logstart(scheduler)
    eventloop(scheduler; remote = remote, exit = exit)
end

function shutdown!(scheduler::Scheduler)
    setstate!(scheduler, stopped)
    call_lifecycle_hook(scheduler, shutdown!)
    @debug "Scheduler at $(postcode(scheduler)) exited."
end

# Helpers for plugins
getactorbyid(scheduler::AbstractScheduler, id::ActorId) = get(scheduler.actorcache, id, nothing)
