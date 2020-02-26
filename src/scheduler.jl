# SPDX-License-Identifier: LGPL-3.0-only
abstract type AbstractActorScheduler end

struct ActorService{TScheduler}
    scheduler::TScheduler
end

function send(service::ActorService{TScheduler}, message::AbstractMessage) where {TScheduler}
    deliver!(service.scheduler, message)
end

function send(service::ActorService{TScheduler}, sender::AbstractActor, to::Address, messagebody::TBody) where {TBody, TScheduler}
    #onmessage(service.scheduler.actorcache[to.box], messagebody, service) # Delivering directly is a bit faster, but stack overflow prevention is needed
    deliver!(service.scheduler, Message{TBody}(address(sender), to, messagebody))
end

function spawn(service::ActorService{TScheduler}, actor::AbstractActor)::Address where {TScheduler}
    schedule!(service.scheduler, actor)
end

function die(service::ActorService{TScheduler}, actor::AbstractActor) where {TScheduler}
    unschedule!(service.scheduler, actor)
end

mutable struct ActorScheduler <: AbstractActorScheduler
    postoffice::PostOffice
    actorcount::UInt64
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::Queue{AbstractMessage}
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::AbstractArray)
        scheduler = new(PostOffice(), 0, Dict{ActorId,AbstractActor}([]), Queue{AbstractMessage}())
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

function deliver!(scheduler::ActorScheduler, message::AbstractMessage)
    enqueue!(scheduler.messagequeue, message)
end

function fill_address!(scheduler::ActorScheduler, actor::AbstractActor)
    actor.address = Address(postcode(scheduler.postoffice), rand(ActorId))
end

isscheduled(scheduler::ActorScheduler, actor::AbstractActor) = haskey(scheduler.actorcache, id(actor))

function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Address
    isdefined(actor, :address) && isscheduled(scheduler, actor) && return address(actor)
    fill_address!(scheduler, actor)
    scheduler.actorcache[id(actor)] = actor
    scheduler.actorcount += 1
    return address(actor)
end

function unschedule!(scheduler::ActorScheduler, actor::AbstractActor)
    isscheduled(scheduler, actor) || return nothing
    pop!(scheduler.actorcache, id(actor))
    scheduler.actorcount -= 1
end

function step!(scheduler::ActorScheduler)
    message = dequeue!(scheduler.messagequeue)
    onmessage(scheduler.actorcache[target(message).box], body(message), scheduler.service)
end

function (scheduler::ActorScheduler)(message::AbstractMessage;process_external=false)
    deliver!(scheduler, message)
    scheduler(process_external=process_external)
end

function (scheduler::ActorScheduler)(;process_external=true)
    while true
        while !isempty(scheduler.messagequeue)
            step!(scheduler)
        end
        if !process_external || #testing here to avoid blocking at getmessage()
            scheduler.actorcount == 0 
            return
        end
        msg = getmessage(scheduler.postoffice)
        deliver!(scheduler, msg)
    end
end

function shutdown!(scheduler::ActorScheduler)
    shutdown!(scheduler.postoffice)
end
