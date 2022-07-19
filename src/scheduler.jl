# SPDX-License-Identifier: MPL-2.0
using DataStructures

@enum SchedulerState::Int8 created=0 running=10 paused=20 stopped=30
struct StateChangeError <: Exception
    from::SchedulerState
    to::SchedulerState
end

mutable struct Scheduler{THooks, TMsg, TCoreState} <: AbstractScheduler{TMsg, TCoreState} # TODO THooks -> TSchedulerState
    pos::Pos # TODO -> state
    postcode::PostCode # TODO -> state
    actorcount::UInt64
    actorcache::ActorStore{Any}
    msgqueue::Deque{Any}# CircularBuffer{Msg}
    tokenservice::TokenService
    state::SchedulerState # TODO state::TSchedulerState , plugin-assembled
    maintask::Union{Task, Nothing} # The task that runs the event loop
    lock::ReentrantLock # TODO -> state (?)
    startcond::Threads.Condition # TODO -> state
    pausecond::Threads.Condition # TODO -> state
    startup_actor_count::UInt16 # Number of actors created by plugins TODO eliminate
    plugins::Plugins.PluginStack
    hooks::THooks # TODO -> state
    zygote::AbstractArray  
    exitflag::Bool  
    service::Service{Scheduler{THooks, TMsg, TCoreState}, TMsg, TCoreState}

    function Scheduler(
        ctx::AbstractContext,
        zygote::AbstractArray = [];
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
            ActorStore(),
            Deque{Any}(),#msgqueue_capacity),
            TokenService(),
            created,
            nothing,
            _lock,
            Threads.Condition(_lock),
            Threads.Condition(_lock),
            0,
            plugins,
            _hooks,
            zygote,
            false)
        scheduler.service = Service(ctx, scheduler)
        call_lifecycle_hook(scheduler, setup!)
        postoffice = get(plugins, :postoffice, nothing)  # TODO eliminate
        scheduler.postcode = isnothing(postoffice) ? invalidpostcode : postcode(postoffice) # TODO eliminate

        return scheduler
    end
end

Base.show(io::IO, ::Type{<:Scheduler}) = print(io, "Scheduler")
Base.show(io::IO, ::MIME"text/plain", scheduler::AbstractScheduler) = begin
    print(io, "Scheduler at $(postcode(scheduler)) with $(scheduler.actorcount) actors")
end

pos(scheduler::AbstractScheduler) = scheduler.pos # TODO find a better location
postcode(scheduler::AbstractScheduler) = scheduler.postcode # TODO find a better location

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
            scheduler.startup_actor_count = scheduler.actorcount - actorcount # TODO not just count and not here
            for a in scheduler.zygote; spawn(scheduler, a); end
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

function lockop(op::Function, cond)
    lock(cond)
    try
        op(cond)
    finally
        unlock(cond)
    end
end

function lockop(op::Function, obj, cond_sym::Symbol)
    lockop(op, getfield(obj, cond_sym))
end

function pause!(scheduler)
    setstate!(scheduler, paused)
    lockop(wait, scheduler, :pausecond)
    return nothing
end

# TODO collect startup info from a hook
logstart(scheduler::AbstractScheduler) = scheduler.state == created && @info "Circo scheduler starting on thread $(Threads.threadid())"

function run!(scheduler; nowait = false, kwargs...)
    isrunning(scheduler) && throw(StateChangeError(scheduler.state, running))
    logstart(scheduler)
    task = @async eventloop(scheduler; kwargs...)
    nowait && return task
    lockop(wait, scheduler, :startcond)
    return task
end

isrunning(scheduler) = scheduler.state == running

# For external calls # TODO find a better place
function send(scheduler::AbstractScheduler{TMsg, TCoreState}, from::Addr, to::Addr, msgbody; kwargs...) where {TMsg, TCoreState}
    msg = TMsg(from, to, msgbody, scheduler; kwargs...)
    deliver!(scheduler, msg)
end
function send(scheduler::AbstractScheduler, to::Addr, msgbody; kwargs...)
    send(scheduler, Addr(), to, msgbody; kwargs...)
end
function send(scheduler::AbstractScheduler, to::Actor, msgbody; kwargs...)
    send(scheduler, addr(to), msgbody; kwargs...)
end

@inline function deliver!(scheduler::AbstractScheduler, msg::AbstractMsg)
    # @debug "deliver! at $(postcode(scheduler)) $msg" # degrades ping-pong perf even if debugging is not enabled
    target_postcode = postcode(target(msg)) # TODO eliminate
    if postcode(scheduler) === target_postcode
        deliver_locally!(scheduler, msg)
        return nothing
    end
    if !scheduler.hooks.remoteroutes(scheduler, msg)
        @info "Unhandled remote delivery: $msg"
    end
    return nothing
end

@inline function deliver_locally!(scheduler::AbstractScheduler, msg::AbstractMsg)
    deliver_locally_kern!(scheduler, msg)
    return nothing
end

@inline function deliver_locally!(scheduler::AbstractScheduler, msg::AbstractMsg{<:Response})
    cleartimeout(scheduler.tokenservice, token(msg.body), target(msg))
    deliver_locally_kern!(scheduler, msg)
    return nothing
end

@inline function deliver_locally_kern!(scheduler::AbstractScheduler, msg::AbstractMsg)
    if box(target(msg)) == 0 # TODO (?) always push, check later only if target not found
        if !scheduler.hooks.specialmsg(scheduler, msg)
            @debug("Unhandled special message: $msg")
        end
    else
        push!(scheduler.msgqueue, msg)
    end
    return true
end

@inline function fill_corestate!(scheduler::AbstractScheduler{TMsg, TCoreState}, actor) where {TMsg, TCoreState}
    actorid = !isdefined(actor, :core) || box(actor) == 0 ? rand(ActorId) : box(actor)
    actor.core = TCoreState(scheduler, actor, actorid)
    return nothing
end

@inline is_scheduled(scheduler::AbstractScheduler, actor::Actor) = haskey(scheduler.actorcache, box(actor))

function spawn(scheduler::AbstractScheduler, actor::Actor)
    isfirstschedule = !isdefined(actor, :core) || box(actor) == 0
    if !isfirstschedule && is_scheduled(scheduler, actor)
        error("Actor already spawned")
    end

    fill_corestate!(scheduler, actor)
    schedule!(scheduler, actor)
    scheduler.actorcount += 1

    if isfirstschedule
        scheduler.hooks.actor_spawning(scheduler, actor)
        onspawn(actor, scheduler.service)
    end
    return addr(actor)
end

@inline function schedule!(scheduler::AbstractScheduler, actor::Actor)::Addr
    scheduler.actorcache[box(actor)] = actor
    return addr(actor)
end

function kill!(scheduler::AbstractScheduler, actor::Actor)
    scheduler.hooks.actor_dying(scheduler, actor)
    try
        ondeath(actor, scheduler.service)
    catch e
        @warn "Exception in ondeath of actor $(addr(actor)). Unscheduling anyway." exception = (e, catch_backtrace())
    end

    if is_scheduled(scheduler, actor)
        unschedule!(scheduler, actor)
        scheduler.actorcount -= 1
    else 
        error("Actor wasn't scheduled!")
    end
end

@inline function unschedule!(scheduler::AbstractScheduler, actor::Actor)
    if is_scheduled(scheduler, actor) 
    delete!(scheduler.actorcache, box(actor))
    end
    return nothing
end

@inline function step!(scheduler::AbstractScheduler)
    msg = popfirst!(scheduler.msgqueue)
    step_kern1!(msg, scheduler) # This outer kern degrades perf on 1.5, but not on 1.4
    return nothing
end

@inline function step_kern1!(msg, scheduler)
    targetbox = target(msg).box::ActorId
    targetactor = get(scheduler.actorcache, targetbox, nothing)
    step_kern!(targetactor, scheduler, msg)
end

@inline function step_kern!(targetactor, scheduler, msg)
    if isnothing(targetactor)
        if !scheduler.hooks.localroutes(scheduler, msg)
            @debug "Cannot deliver on host: $msg"
        end
    else
        scheduler.hooks.localdelivery(scheduler, msg, targetactor)
    end
    return nothing
end

@inline function checktimeouts(scheduler::AbstractScheduler{TMsg, TCoreState}) where {TMsg, TCoreState}
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

@inline function safe_sleep(sleeplength)
    try
        sleep(sleeplength)
    catch e # EOFError happens
        if e isa InterruptException
            rethrow(e)
        else
            @info "Exception while sleeping: $e"
        end
    end
end

@inline function process_remote_and_timeout(scheduler::AbstractScheduler)
    incomingmsg = nothing
    hadtimeout = false
    sleeplength = 0.001
    enter_ts = time_ns()
    while true
        yield() # Allow plugin tasks to run
        scheduler.hooks.letin_remote(scheduler)
        hadtimeout = checktimeouts(scheduler)
        if haswork(scheduler) || !isrunning(scheduler)
            return nothing
        else
            scheduler.hooks.idle(scheduler)
            safe_sleep(sleeplength)
            if time_ns() - enter_ts > 1_000_000
                sleeplength = min(sleeplength * 1.002, 0.03)
            end
        end
    end
end

@inline function haswork(scheduler::AbstractScheduler)
    return !isempty(scheduler.msgqueue)
end

@inline function nomorework(scheduler::AbstractScheduler, remote::Bool)
    return !haswork(scheduler) && !remote
end

function eventloop(scheduler::AbstractScheduler; remote = true)
    try
        if isnothing(scheduler.maintask)
            scheduler.maintask = current_task()
        end
        setstate!(scheduler, running)
        scheduler.exitflag = false
        lockop(notify, scheduler, :startcond)
        while true
            msg_batch = UInt8(255)
            while msg_batch != 0 && haswork(scheduler) && !scheduler.exitflag
                msg_batch -= UInt8(1)
                step!(scheduler)
            end
            if !isrunning(scheduler) || nomorework(scheduler, remote) || scheduler.exitflag
                @debug "Scheduler loop $(postcode(scheduler)) exiting."
                return
            end
            process_remote_and_timeout(scheduler)
        end
    catch e
        if e isa InterruptException
            @info "Interrupt to scheduler on thread $(Threads.threadid())"
        else
            @error "Error while scheduling on thread $(Threads.threadid())" exception = (e, catch_backtrace())
        end
    finally
        isrunning(scheduler) && setstate!(scheduler, paused)
        scheduler.exitflag = false
        lockop(notify, scheduler, :pausecond)
        if scheduler.maintask != current_task()
            yieldto(scheduler.maintask)
        else
            scheduler.maintask = nothing
        end
    end
end

function (scheduler::AbstractScheduler)(;remote = true)
    logstart(scheduler)
    eventloop(scheduler; remote = remote)
end

# NOTE remote keyword signals that there may be remote connection to actors and shouldn't stop automatically. In this case ( remot = true) scheduling stop when the last actor die() function called with "exit = true" keyword
function (scheduler::AbstractScheduler)(msgs; remote = false)
    if msgs isa AbstractMsg
        msgs = [msgs]
    end
    for msg in msgs
        deliver!(scheduler, msg)
    end
    scheduler(;remote = remote)
end

function shutdown!(scheduler::AbstractScheduler)
    setstate!(scheduler, stopped)
    call_lifecycle_hook(scheduler, shutdown!)
    @debug "Scheduler at $(postcode(scheduler)) exited."
end

# Helpers for plugins
getactorbyid(scheduler::AbstractScheduler, id::ActorId) = get(scheduler.actorcache, id, nothing)
