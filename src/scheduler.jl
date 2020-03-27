# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures, Dates

const TIMEOUTCHECK_INTERVAL = Second(1)

mutable struct ActorScheduler <: AbstractActorScheduler
    postoffice::PostOffice
    actorcount::UInt64
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::Queue{AbstractMessage}
    registry::LocalRegistry
    tokenservice::TokenService
    next_timeoutcheck_ts::DateTime
    plugins::Plugins
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::AbstractArray;plugins = default_plugins())
        scheduler = new(PostOffice(), 0, Dict{ActorId,AbstractActor}([]), Queue{AbstractMessage}(),
         LocalRegistry(), TokenService(), Dates.now() + TIMEOUTCHECK_INTERVAL, Plugins(plugins))
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

function default_plugins()
    return [MigrationService()]
end

@inline function deliver!(scheduler::ActorScheduler, message::AbstractMessage)
    if postcode(scheduler) == postcode(target(message))
        deliver_locally!(scheduler, message)
    else
        send(scheduler.postoffice, message)
    end
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::AbstractMessage)
    deliver_nonresponse_locally!(scheduler, message)
    return nothing
end

@inline function deliver_locally!(scheduler::ActorScheduler, message::Message{T}) where T<:Response
    cleartimeout(scheduler.tokenservice, token(message.body), target(message))
    deliver_nonresponse_locally!(scheduler, message)
    return nothing
end

@inline function deliver_nonresponse_locally!(scheduler::ActorScheduler, message::AbstractMessage)
    if box(target(message)) == 0
        handle_special!(scheduler, message)
    else
        enqueue!(scheduler.messagequeue, message)
    end
    return nothing
end

@inline function fill_address!(scheduler::ActorScheduler, actor::AbstractActor)
    actorid = isdefined(actor, :address) ? id(actor) : rand(ActorId)
    actor.address = Address(postcode(scheduler.postoffice), actorid)
    return nothing
end

@inline isscheduled(scheduler::ActorScheduler, actor::AbstractActor) = haskey(scheduler.actorcache, id(actor))

@inline function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Address
    isdefined(actor, :address) && isscheduled(scheduler, actor) && return address(actor)
    fill_address!(scheduler, actor)
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

@inline function step!(scheduler::ActorScheduler)
    message = dequeue!(scheduler.messagequeue)
    targetactor = get(scheduler.actorcache, target(message).box, nothing)
    isnothing(targetactor) ?
        route_locally(scheduler.plugins, scheduler, message) :
        onmessage(targetactor, body(message), scheduler.service)
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
            deliver_locally!(scheduler, Message(
                address(scheduler),
                timeout.watcher,
                timeout
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
        yield() # Allow the postoffice "arrivals" task to run
        incomingmessage = getmessage(scheduler.postoffice)
        hadtimeout = checktimeouts(scheduler)
        if !isnothing(incomingmessage)
            deliver_locally!(scheduler, incomingmessage)
            return nothing
        elseif hadtimeout
            return nothing
        else
            sleep(sleeplength)
            sleeplength = min(sleeplength * 1.002, 0.03)
        end
    end
end

function (scheduler::ActorScheduler)(message::AbstractMessage;process_external=false, exit_when_done=true)
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
    shutdown!(scheduler.postoffice)
    println("Scheduler at $(postcode(scheduler)) exited.")
end
