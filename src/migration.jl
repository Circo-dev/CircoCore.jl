# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures

struct MigrationRequest
    actor::AbstractActor
end
struct MigrationResponse
    from::Addr
    to::Addr
    success::Bool
end
struct RecipientMoved{TBody}
    oldaddress::Addr
    newaddress::Addr
    originalmessage::TBody
end

struct MovingActor
    actor::AbstractActor
    messages::Queue{AbstractMsg}
    MovingActor(actor::AbstractActor) = new(actor, Queue{AbstractMsg}())
end

struct MigrationService <: Plugin
    movingactors::Dict{ActorId,MovingActor}
    movedactors::Dict{ActorId,Addr}
    MigrationService() = new(Dict([]),Dict([]))
end

symbol(plugin::MigrationService) = :migration

@inline function migrate(service::ActorService{TScheduler}, actor::AbstractActor, topostcode::PostCode) where {TScheduler}
    migrate!(service.scheduler, actor, topostcode)
end

function migrate!(scheduler::AbstractActorScheduler, actor::AbstractActor, topostcode::PostCode)
    send(postoffice(scheduler), Msg(address(scheduler),
        Addr(topostcode, 0),
        MigrationRequest(actor),
        Infoton(nullpos)))
    unschedule!(scheduler, actor)
    scheduler.plugins[:migration].movingactors[id(actor)] = MovingActor(actor)
end

function handle_special!(scheduler::AbstractActorScheduler, message::Msg{MigrationRequest})
    actor = body(message).actor
    fromaddress = address(actor)
    schedule!(scheduler, actor)
    onmigrate(actor, scheduler.service)
    send(scheduler.postoffice, Msg(actor,
        Addr(postcode(fromaddress), 0),
        MigrationResponse(fromaddress, address(actor), true)))
end

function handle_special!(scheduler::AbstractActorScheduler, message::Msg{MigrationResponse})
    migration = scheduler.plugins[:migration]
    response = body(message)
    movingactor = pop!(migration.movingactors, box(response.to))
    if response.success
        migration.movedactors[box(response.from)] = response.to
        for message in movingactor.messages
            deliver!(scheduler, message)
        end
    else
        schedule!(scheduler, movingactor.actor) # TODO callback + tests
    end
end

function localroutes(migration::MigrationService, scheduler::AbstractActorScheduler, message::AbstractMsg)::Bool
    if body(message) isa RecipientMoved
        println("Got a RecipientMoved with invalid recipient, dropping.")
        return true
    else
        newaddress = get(migration.movedactors, box(target(message)), nothing)
        if isnothing(newaddress)
            movingactor = get(migration.movingactors, box(target(message)), nothing)
            if isnothing(movingactor)
                return true
            else
                enqueue!(movingactor.messages, message)
                return false
            end
        else
            send(scheduler.postoffice, Msg(
                address(scheduler),
                sender(message),
                RecipientMoved(target(message), newaddress, body(message)),
                Infoton(nullpos)
            ))
            return false       
        end
    end
end