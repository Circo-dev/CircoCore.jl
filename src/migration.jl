# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures

struct MigrationRequest
    actor::AbstractActor
end
struct MigrationResponse
    from::Address
    to::Address
    success::Bool
end
struct RecipientMoved{TBody}
    oldaddress::Address
    newaddress::Address
    originalmessage::TBody
end

struct MovingActor
    actor::AbstractActor
    messages::Queue{AbstractMessage}
    MovingActor(actor::AbstractActor) = new(actor, Queue{AbstractMessage}())
end

struct MigrationService <: SchedulerPlugin
    movingactors::Dict{ActorId,MovingActor}
    movedactors::Dict{ActorId,Address}
    MigrationService() = new(Dict([]),Dict([]))
end

localroutes(plugin::MigrationService) = migration_routes!
symbol(plugin::MigrationService) = :migration

function migrate!(scheduler::AbstractActorScheduler, actor::AbstractActor, topostcode::PostCode)
    send(postoffice(scheduler), Message(address(scheduler),
        Address(topostcode, 0),
        MigrationRequest(actor)))
    unschedule!(scheduler, actor)
    scheduler.plugins[:migration].movingactors[id(actor)] = MovingActor(actor)
end

function handle_special!(scheduler::AbstractActorScheduler, message::Message{MigrationRequest})
    actor = body(message).actor
    fromaddress = address(actor)
    schedule!(scheduler, actor)
    onmigrate(actor, scheduler.service)
    send(scheduler.postoffice, Message(address(actor),
        Address(postcode(fromaddress), 0),
        MigrationResponse(fromaddress, address(actor), true)))
end

function handle_special!(scheduler::AbstractActorScheduler, message::Message{MigrationResponse})
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

function migration_routes!(scheduler::AbstractActorScheduler, message::AbstractMessage)::Bool
    if body(message) isa RecipientMoved
        println("Got a RecipientMoved with invalid recipient, dropping.")
        return false
    else
        migration = scheduler.plugins[:migration]
        newaddress = get(migration.movedactors, box(target(message)), nothing)
        if isnothing(newaddress)
            movingactor = get(migration.movingactors, box(target(message)), nothing)
            if isnothing(movingactor)
                println("TODO: handle message sent to invalid address: $message")
                return false
            else
                enqueue!(movingactor.messages, message)
                return true
            end
        else
            send(scheduler.postoffice, Message(
                address(scheduler),
                sender(message),
                RecipientMoved(target(message), newaddress, body(message))
            ))
            return true            
        end
    end
end