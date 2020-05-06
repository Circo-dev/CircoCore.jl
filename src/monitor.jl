# SPDX-License-Identifier: LGPL-3.0-only

struct ActorInfo
    typename::String
    box::ActorId
    x::Float32
    y::Float32
    z::Float32
    extra::Any
    ActorInfo(actor::AbstractActor, extras) = new(string(typeof(actor)), box(actor.core.addr),
     pos(actor).x, pos(actor).y, pos(actor).z, extras)
end

struct ActorListRequest <: Request
    respondto::Addr
    token::Token
end

struct ActorListResponse <: Response
    actors::Vector{ActorInfo}
    token::Token
end

struct ActorInterfaceRequest <: Request
    respondto::Addr
    box::ActorId
    token::Token
end

struct ActorInterfaceResponse <: Response
    messagetypes::Vector{String}
    token::Token
end

mutable struct MonitorActor{TMonitor} <: AbstractActor
    monitor::TMonitor
    core::CoreState
    MonitorActor(monitor) = new{typeof(monitor)}(monitor)
end

mutable struct MonitorService <: SchedulerPlugin
    actor::MonitorActor
    scheduler::AbstractActorScheduler
    MonitorService() = new()
end

function setup!(monitor::MonitorService, scheduler)
    monitor.actor = MonitorActor(monitor)
    monitor.scheduler = scheduler
    schedule!(scheduler, monitor.actor)
    registername(scheduler.service, "monitor", monitor.actor)
end

struct NoExtra
    a::Nothing # MsgPack.jl fails for en empty struct (at least when the default is StructType)
    NoExtra() = new(nothing)
end
noextra = NoExtra()

monitorextra(actor::AbstractActor) = noextra

monitorinfo(actor::AbstractActor) = ActorInfo(actor, monitorextra(actor))

function onmessage(me::MonitorActor, request::ActorListRequest, service)
    result = [monitorinfo(actor) for actor in values(me.monitor.scheduler.actorcache)]
    send(service, me, request.respondto, ActorListResponse(result, request.token))
end

# Retrieves the message type from an onmessage method signature
messagetype(::Type{Tuple{A,B,C,D}}) where {D, C, B, A} = C

function onmessage(me::MonitorActor, request::ActorInterfaceRequest, service)
    actor = getactorbyid(me.monitor.scheduler, request.box)
    if isnothing(actor)
        return nothing # TODO a general notfound response
    end
    result = Vector{String}()
    for m in methods(onmessage, [typeof(actor), Any, Any])
        if m.sig !== Any &&
            typeof(m.sig) === DataType # TODO handle UnionAll message types
            push!(result, string(messagetype(m.sig)))
        end
    end
    send(service, me, request.respondto, ActorInterfaceResponse(result, request.token))
end