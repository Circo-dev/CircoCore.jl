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
struct RecipientMoved
    oldaddress::Address
    newaddress::Address
    originalmessage::AbstractMessage
end

struct MovingActor
    actor::AbstractActor
    messages::Queue{AbstractMessage}
    MovingActor(actor::AbstractActor) = new(actor, Queue{AbstractMessage}())
end

struct MigrationService
    movingactors::Dict{ActorId,MovingActor}
    movedactors::Dict{ActorId,Address}
    MigrationService() = new(Dict([]),Dict([]))
end

function migrate!(scheduler::AbstractActorScheduler, actor::AbstractActor, topostcode::PostCode)
    send(postoffice(scheduler), Message(address(scheduler),
        Address(topostcode, 0),
        MigrationRequest(actor)))
    unschedule!(scheduler, actor)
    scheduler.migration.movingactors[id(actor)] = MovingActor(actor)
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
    response = body(message)
    movingactor = pop!(scheduler.migration.movingactors, box(response.to))
    if response.success
        scheduler.migration.movedactors[box(response.from)] = response.to
        for message in movingactor.messages
            println("Delivering to migrant: $message")
            deliver!(scheduler, message)
        end
    else
        schedule!(scheduler, movingactor.actor) # TODO callback + tests
    end
end

function handle_invalidrecipient!(scheduler::AbstractActorScheduler, message::AbstractMessage)
    if body(message) isa RecipientMoved
        println("Got a RecipientMoved with invalid recipient, dropping.")
        return
    end
    newaddress = get(scheduler.migration.movedactors, box(target(message)), nothing)
    if isnothing(newaddress)
        movingactor = get(scheduler.migration.movingactors, box(target(message)), nothing)
        if isnothing(movingactor)
            println("TODO: handle message sent to invalid address: $message")
        else
            enqueue!(movingactor.messages, message)
        end
    else
        send(scheduler.postoffice, Message(
            address(scheduler),
            sender(message),
            RecipientMoved(target(message), newaddress, message)
        ))
    end
end