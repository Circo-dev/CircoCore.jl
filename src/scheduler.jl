# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures, Dates

const VIEW_SIZE = 3000 # TODO eliminate
const VIEW_HEIGHT = VIEW_SIZE / 3

const TIMEOUTCHECK_INTERVAL = Second(1)

mutable struct ActorScheduler <: AbstractActorScheduler
    pos::Pos
    postoffice::PostOffice
    actorcount::UInt64
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::Queue{AbstractMsg}
    registry::LocalRegistry
    tokenservice::TokenService
    next_timeoutcheck_ts::DateTime
    plugins::PluginStack
    apply_infoton_hooks::Plugins.HookList # TODO Tried to move this to a type parameter but somehow it slowed the clusterfull test down. Seems that not the hook call is slow but something else. Needs a deeper investigation.
    localroutes_hooks::Plugins.HookList
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::AbstractArray;plugins = default_plugins(),pos=Pos(rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_SIZE - VIEW_SIZE / 2, rand(Float32) * VIEW_HEIGHT - VIEW_HEIGHT / 2))
        scheduler = new(pos, PostOffice(), 0, Dict{ActorId,AbstractActor}([]), Queue{AbstractMsg}(),
         LocalRegistry(), TokenService(), Dates.now() + TIMEOUTCHECK_INTERVAL, PluginStack(plugins))
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        cache_hooks(scheduler)
        setup!(scheduler.plugins, scheduler)
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

function default_plugins()
    return [MigrationService(), WebsocketService(), SpaceService()]
end

function cache_hooks(scheduler::ActorScheduler)
    scheduler.apply_infoton_hooks = hooks(scheduler, apply_infoton)
    scheduler.localroutes_hooks = hooks(scheduler, localroutes)
    #println("Lengths: $(length(scheduler.apply_infoton_hooks)) $(length(scheduler.localroutes_hooks))")
end

@inline function deliver!(scheduler::ActorScheduler, message::AbstractMsg)
    if postcode(scheduler) == postcode(target(message))
        deliver_locally!(scheduler, message)
    else
        send(scheduler.postoffice, message)
    end
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::AbstractMsg)
    deliver_nonresponse_locally!(scheduler, message)
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::Msg{T}) where T<:Response
    cleartimeout(scheduler.tokenservice, token(message.body), target(message))
    deliver_nonresponse_locally!(scheduler, message)
    return nothing
end

@inline function deliver_nonresponse_locally!(scheduler::ActorScheduler, message::AbstractMsg)
    if box(target(message)) == 0
        handle_special!(scheduler, message)
    else
        enqueue!(scheduler.messagequeue, message)
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
    isdefined(actor, :addr) && isscheduled(scheduler, actor) && return address(actor)
    fill_corestate!(scheduler, actor)
    scheduler.actorcache[id(actor)] = actor
    scheduler.actorcount += 1
    onschedule(actor, scheduler.service)
    return address(actor)
end

@inline function unschedule!(scheduler::ActorScheduler, actor::AbstractActor)
    isscheduled(scheduler, actor) || return nothing
    pop!(scheduler.actorcache, id(actor))
    scheduler.actorcount -= 1
    return nothing
end

@inline function scheduler_infoton(scheduler, actor::AbstractActor)
    diff = scheduler.pos - actor.core.pos
    distfromtarget = 2000 - norm(diff) # TODO configuration +easy redefinition from applications (including turning it off completely?)
    energy = sign(distfromtarget) * distfromtarget * distfromtarget * -2e-6
    return Infoton(scheduler.pos, energy)
end

@inline function step!(scheduler::ActorScheduler)
    message = dequeue!(scheduler.messagequeue)
    targetactor = get(scheduler.actorcache, target(message).box, nothing)
    if isnothing(targetactor)
        scheduler.localroutes_hooks(message)
    else
        onmessage(targetactor, body(message), scheduler.service)
        scheduler.apply_infoton_hooks(targetactor, message.infoton)
        if (rand(UInt8) < 30) # TODO: config or remove
            scheduler.apply_infoton_hooks(targetactor, scheduler_infoton(scheduler, targetactor))
        end
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
                address(scheduler),
                timeout.watcher,
                timeout,
                Infoton(nullpos)#TODO scheduler pos
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
    while true
        yield() # Allow the postoffice "arrivals" and plugin tasks to run
        incomingmessage = getmessage(scheduler.postoffice)
        hadtimeout = checktimeouts(scheduler)
        if !isnothing(incomingmessage)
            deliver_locally!(scheduler, incomingmessage)
            return nothing
        elseif hadtimeout || !isempty(scheduler.messagequeue) # Plugins may deliver messages directly
            return nothing
        else
            sleep(sleeplength)
            sleeplength = min(sleeplength * 1.002, 0.03)
        end
    end
end

function (scheduler::ActorScheduler)(message::AbstractMsg;process_external=false, exit_when_done=true)
    deliver!(scheduler, message)
    scheduler(process_external=process_external, exit_when_done=exit_when_done)
end

function (scheduler::ActorScheduler)(;process_external=true, exit_when_done=false)
    while true
        while !isempty(scheduler.messagequeue)
            step!(scheduler)
        end
        if !process_external || 
            exit_when_done && scheduler.actorcount == 0 
            return
        end
        process_post_and_timeout(scheduler)
    end
end

function shutdown!(scheduler::ActorScheduler)
    Plugins.shutdown!(scheduler.plugins, scheduler)
    shutdown!(scheduler.postoffice)
    println("Scheduler at $(postcode(scheduler)) exited.")
end

# Helpers for plugins
getactorbyid(scheduler::AbstractActorScheduler, id::ActorId) = get(scheduler.actorcache, id, nothing)