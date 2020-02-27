# SPDX-License-Identifier: LGPL-3.0-only

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
end

struct MigrationService
    movingactors::Dict{ActorId,AbstractActor}
    movedactors::Dict{ActorId,Address}
    MigrationService() = new(Dict{ActorId,AbstractActor}([]),Dict{ActorId,Address}([]))
end

function migrate!(scheduler::AbstractActorScheduler, actor::AbstractActor, topostcode::PostCode)
    send(postoffice(scheduler), Message(address(scheduler),
        Address(topostcode, 0),
        MigrationRequest(actor)))
    unschedule!(scheduler, actor)
    scheduler.migration.movingactors[id(actor)] = actor
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
    println("Migration response: $(body(message))")
    response = body(message)
    actor = pop!(scheduler.migration.movingactors, box(response.to))
    if response.success
        scheduler.migration.movedactors[box(response.from)] = response.to
    else
        schedule!(scheduler, actor)
    end
end

function handle_invalidrecipient!(scheduler::AbstractActorScheduler, message::AbstractMessage)
    println("Invalid target: $message")
    if body(message) isa RecipientMoved
        println("Got a RecipientMoved with invalid recipient, dropping.")
        return
    end
    newaddress = get(scheduler.migration.movedactors, box(target(message)), nothing)
    if isnothing(newaddress)
        println("TODO handle unknown address")
        return
    else
        send(scheduler.postoffice, Message(
            address(scheduler),
            sender(message),
            RecipientMoved(target(message), newaddress)
        ))
    end
end