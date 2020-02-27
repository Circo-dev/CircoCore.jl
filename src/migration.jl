# SPDX-License-Identifier: LGPL-3.0-only

struct MigrationRequest
    actor::AbstractActor
end
struct MigrationResponse
    from::Address
    to::Address
    success::Bool
end

function migrate(service::ActorService, actor::AbstractActor, topostcode::PostCode)
    migrate!(service.scheduler, actor, topostcode)
end

function migrated(actor::AbstractActor, service) end

function migrate!(scheduler::ActorScheduler, actor::AbstractActor, topostcode::PostCode)
    send(scheduler.postoffice, Message{MigrationRequest}(
        Address(postcode(scheduler.postoffice), 0),
        Address(topostcode, 0),
        MigrationRequest(actor)
    ))
    unschedule!(scheduler, actor)
end

function handle_special!(scheduler::ActorScheduler, message) end
function handle_special!(scheduler::ActorScheduler, message::Message{MigrationRequest})
    actor = body(message).actor
    fromaddress = address(actor)
    schedule!(scheduler, actor)
    migrated(actor, scheduler.service)
    send(scheduler.postoffice, Message{MigrationResponse}(
        address(actor),
        Address(postcode(fromaddress), 0),
        MigrationResponse(fromaddress, address(actor), true)
    ))
end

function handle_special!(scheduler::ActorScheduler, message::Message{MigrationResponse})
    println("Migration response: $(body(message))")
end
