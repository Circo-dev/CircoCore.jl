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

mutable struct ActorScheduler <: AbstractActorScheduler
    actors::Array{AbstractActor}
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::Queue{AbstractMessage}
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::AbstractArray)
        scheduler = new(actors, Dict{ActorId,AbstractActor}([]), Queue{AbstractMessage}())
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

function deliver!(scheduler::ActorScheduler, message::AbstractMessage)
    enqueue!(scheduler.messagequeue, message)
end

function fill_address!(actor::AbstractActor)
    actor.address = Address(rand(ActorId))
end

function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Address
    fill_address!(actor)
    scheduler.actorcache[id(actor)] = actor
    push!(scheduler.actors, actor)
    return address(actor)
end

function step!(scheduler::ActorScheduler)
    message = dequeue!(scheduler.messagequeue)
    onmessage(scheduler.actorcache[target(message).box], body(message), scheduler.service)
end

function (scheduler::ActorScheduler)(message::AbstractMessage)
    deliver!(scheduler, message)
    scheduler()
end

function (scheduler::ActorScheduler)()
    while !isempty(scheduler.messagequeue)
        step!(scheduler)
    end
end
