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

mutable struct MigrationAlternatives
    peers::Array{NodeInfo}
end

mutable struct MigrationService <: Plugin
    movingactors::Dict{ActorId,MovingActor}
    movedactors::Dict{ActorId,Addr}
    alternatives::MigrationAlternatives
    helperactor::Addr
    MigrationService() = new(Dict([]),Dict([]), MigrationAlternatives([]))
end

mutable struct MigrationHelper <: AbstractActor
    service::MigrationService
    core::CoreState
    MigrationHelper(migration) = new(migration)
end

symbol(plugin::MigrationService) = :migration

function setup!(migration::MigrationService, scheduler)
    helper = MigrationHelper(migration)
    migration.helperactor = spawn(scheduler.service, helper)
end

function onschedule(me::MigrationHelper, service)
    println("cluster: $(getname(service, "cluster"))")
    registername(service, "migration", me)
    send(service, me, getname(service, "cluster"), Subscribe{PeerListUpdated}(addr(me)))
end

function onmessage(me::MigrationHelper, message::PeerListUpdated, service)
    println("PeerListUpdated received: $message")
    me.service.alternatives = MigrationAlternatives(message.peers) # TODO filter if lengthy
end

"""
  migrate

  sdfs sdf
"""
@inline function migrate(service::ActorService{TScheduler}, actor::AbstractActor, topostcode::PostCode) where {TScheduler}
    migrate!(service.scheduler, actor, topostcode)
end

function migrate!(scheduler::AbstractActorScheduler, actor::AbstractActor, topostcode::PostCode)
    send(postoffice(scheduler), Msg(addr(scheduler),
        Addr(topostcode, 0),
        MigrationRequest(actor),
        Infoton(nullpos)))
    unschedule!(scheduler, actor)
    scheduler.plugins[:migration].movingactors[id(actor)] = MovingActor(actor)
end

function handle_special!(scheduler::AbstractActorScheduler, message::Msg{MigrationRequest})
    #println("Migration request: $(message)")
    actor = body(message).actor
    fromaddress = addr(actor)
    migration = scheduler.plugins[:migration] # TODO also handle fast back-and forth moving when the request comes earlier than the previous response
    delete!(migration.movedactors, box(addr(body(message).actor)))
    schedule!(scheduler, actor)
    onmigrate(actor, scheduler.service)
    send(scheduler.postoffice, Msg(actor,
        Addr(postcode(fromaddress), 0),
        MigrationResponse(fromaddress, addr(actor), true)))
end

function handle_special!(scheduler::AbstractActorScheduler, message::Msg{MigrationResponse})
    #println("Migration response: $(message)")
    migration = scheduler.plugins[:migration]
    response = body(message)
    movingactor = pop!(migration.movingactors, box(response.to))
    if response.success
        migration.movedactors[box(response.from)] = response.to
        #println("Messages waiting: $(movingactor.messages)")
        for message in movingactor.messages
            deliver!(scheduler, message)
        end
    else
        schedule!(scheduler, movingactor.actor) # TODO callback + tests
    end
end

function localroutes(migration::MigrationService, scheduler::AbstractActorScheduler, message::AbstractMsg)::Bool
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
        if body(message) isa RecipientMoved # Got a RecipientMoved, but the original sender also moved. Forward the RecipientMoved
            msg = Msg(
                addr(scheduler),
                newaddress,
                body(message),
                Infoton(nullpos)
            )
            #println("Forwarding message $message")
            #println(":::$msg")
            send(scheduler.postoffice, msg)
        else # Do not forward normal messages but send back a RecipientMoved
            send(scheduler.postoffice, Msg(
                addr(scheduler),
                sender(message),
                RecipientMoved(target(message), newaddress, body(message)),
                Infoton(nullpos)
            ))
        end    
        return false       
    end
end

@inline check_migration(me::AbstractActor, alternatives::MigrationAlternatives, service) = nothing

@inline function actor_activity_sparse(migration::MigrationService, scheduler, actor::AbstractActor)
    check_migration(actor, migration.alternatives, scheduler.service)
end

@inline function find_nearest(sourcepos::Pos, alternatives::MigrationAlternatives)::Union{NodeInfo, Nothing}
    peers = alternatives.peers
    if length(peers) < 2
        return nothing
    end
    found = peers[1]
    mindist = norm(pos(found) - sourcepos)
    for peer in peers[2:end]
        dist = norm(pos(peer) - sourcepos)
        if dist < mindist
            mindist = dist
            found = peer
        end
    end
    return found
end

@inline function migrate_to_nearest(me::AbstractActor, alternatives::MigrationAlternatives, service)
    nearest = find_nearest(pos(me), alternatives)
    #println("Nearest: $nearest")
    if isnothing(nearest) return nothing end
    if box(nearest.addr) === box(addr(me)) return nothing end
    if norm(pos(me) - pos(nearest)) < 0.99 * norm(pos(me) - pos(service))
        #println("$(box(addr(me))): Migrating to $(postcode(nearest))")
        migrate(service, me, postcode(nearest))
    end
    return nothing
end