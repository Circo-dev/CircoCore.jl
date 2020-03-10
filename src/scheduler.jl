# SPDX-License-Identifier: LGPL-3.0-only

abstract type AbstractActorScheduler end

postoffice(scheduler::AbstractActorScheduler) = scheduler.postoffice
address(scheduler::AbstractActorScheduler) = address(postoffice(scheduler))
postcode(scheduler::AbstractActorScheduler) = postcode(postoffice(scheduler))

function handle_special!(scheduler::AbstractActorScheduler, message) end

struct ActorService{TScheduler}
    scheduler::TScheduler
end

include("migration.jl")
include("nameservice.jl")

function send(service::ActorService{TScheduler}, message::AbstractMessage) where {TScheduler}
    deliver!(service.scheduler, message)
end

function send(service::ActorService{TScheduler}, sender::AbstractActor, to::Address, messagebody::TBody) where {TBody, TScheduler}
    message = Message(address(sender), to, messagebody)
    if haskey(service.scheduler.actorcache, box(to))
        deliver!(service.scheduler, message)
        #onmessage(service.scheduler.actorcache[to.box], messagebody, service) # Delivering directly is a bit faster, but stack overflow and reenter prevention is needed which may slow it down too much
    else
        send(service.scheduler.postoffice, message)
    end
end

function spawn(service::ActorService{TScheduler}, actor::AbstractActor)::Address where {TScheduler}
    schedule!(service.scheduler, actor)
end

function die(service::ActorService{TScheduler}, actor::AbstractActor) where {TScheduler}
    unschedule!(service.scheduler, actor)
end

function migrate(service::ActorService, actor::AbstractActor, topostcode::PostCode)
    migrate!(service.scheduler, actor, topostcode)
end

function registername(service::ActorService, name::String, handler::AbstractActor)
    registername(service.scheduler.nameservice, name, address(handler))
end

mutable struct ActorScheduler <: AbstractActorScheduler
    postoffice::PostOffice
    actorcount::UInt64
    actorcache::Dict{ActorId,AbstractActor}
    messagequeue::Queue{AbstractMessage}
    migration::MigrationService
    nameservice::NameService
    service::ActorService{ActorScheduler}
    function ActorScheduler(actors::AbstractArray)
        scheduler = new(PostOffice(), 0, Dict{ActorId,AbstractActor}([]), Queue{AbstractMessage}(), MigrationService(), NameService())
        scheduler.service = ActorService{ActorScheduler}(scheduler)
        for a in actors; schedule!(scheduler, a); end
        return scheduler
    end
end

function deliver!(scheduler::ActorScheduler, message::AbstractMessage)
    enqueue!(scheduler.messagequeue, message)
end

function fill_address!(scheduler::ActorScheduler, actor::AbstractActor)
    actorid = isdefined(actor, :address) ? id(actor) : rand(ActorId)
    actor.address = Address(postcode(scheduler.postoffice), actorid)
end

isscheduled(scheduler::ActorScheduler, actor::AbstractActor) = haskey(scheduler.actorcache, id(actor))

function schedule!(scheduler::ActorScheduler, actor::AbstractActor)::Address
    isdefined(actor, :address) && isscheduled(scheduler, actor) && return address(actor)
    fill_address!(scheduler, actor)
    scheduler.actorcache[id(actor)] = actor
    scheduler.actorcount += 1
    onschedule(actor, scheduler.service)
    return address(actor)
end

function unschedule!(scheduler::ActorScheduler, actor::AbstractActor)
    isscheduled(scheduler, actor) || return nothing
    pop!(scheduler.actorcache, id(actor))
    scheduler.actorcount -= 1
end

function step!(scheduler::ActorScheduler)
    message = dequeue!(scheduler.messagequeue)
    targetactor = get(scheduler.actorcache, target(message).box, nothing)
    isnothing(targetactor) ?
        handle_invalidrecipient!(scheduler, message) :
        onmessage(targetactor, body(message), scheduler.service)
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
        if !process_external || # testing here to avoid blocking at getmessage(). Needs a better approach
            exit_when_done && scheduler.actorcount == 0 
            return
        end
        msg = getmessage(scheduler.postoffice)
        if box(target(msg)) == 0
            handle_special!(scheduler, msg)
        else
            deliver!(scheduler, msg)
        end
    end
end

function shutdown!(scheduler::ActorScheduler)
    shutdown!(scheduler.postoffice)
    println("Scheduler at $(postcode(scheduler)) exited.")
end
