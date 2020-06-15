# SPDX-License-Identifier: LGPL-3.0-only

struct ActorInfo{TExtra}
    typename::String
    box::ActorId
    x::Float32
    y::Float32
    z::Float32
    extra::TExtra
    ActorInfo(actor::AbstractActor, extras) = new{typeof(extras)}(string(typeof(actor)), box(actor.core.addr),
     pos(actor).x, pos(actor).y, pos(actor).z, extras)
end

struct NoExtra
    a::Nothing # MsgPack.jl fails for en empty struct (at least when the default is StructType)
    NoExtra() = new(nothing)
end
noextra = NoExtra()

monitorextra(actor::AbstractActor) = noextra

monitorinfo(actor::AbstractActor) = ActorInfo(actor, monitorextra(actor))

struct JS
    src::String
end

monitorprojection(::Type{<: AbstractActor}) = JS("{
    geometry: new THREE.BoxBufferGeometry(20, 20, 20),
    scale: { x: 1, y: 1, z: 1 },
    rotation: { x: 0, y: 0, z: 0 }
}")

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
    box::ActorId
    messagetypes::Vector{String}
    token::Token
end

struct MonitorProjectionRequest <: Request
    respondto::Addr
    typename::String
    token::Token
end

struct MonitorProjectionResponse <: Response
    projection::JS
    token::Token
end

mutable struct MonitorActor{TMonitor} <: AbstractActor
    monitor::TMonitor
    core::CoreState
    MonitorActor(monitor) = new{typeof(monitor)}(monitor)
end

monitorextra(actor::MonitorActor)= (
    actorcount = UInt32(actor.monitor.scheduler.actorcount),
    queuelength = UInt32(length(actor.monitor.scheduler.messagequeue))
    )

monitorprojection(::Type{MonitorActor{TMonitor}}) where TMonitor = JS("
{
    geometry: new THREE.BoxBufferGeometry(5, 5, 5),
    scale: me => {
        const plussize = me.extra.actorcount * 0.00002
        // Works only for origo-centered setups:
        return { x: 1 + plussize * Math.abs(me.y + me.z), y: 1 + plussize * Math.abs(me.x + me.z), z: 1 + plussize * Math.abs(me.x + me.y)}
    },
    color: 0x4063d8
}")

mutable struct MonitorService <: Plugin
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

function onmessage(me::MonitorActor, request::ActorListRequest, service)
    me.core.pos = me.monitor.scheduler.pos
    result = [monitorinfo(actor) for actor in values(me.monitor.scheduler.actorcache)]
    send(service, me, request.respondto, ActorListResponse(result, request.token))
end

function onmessage(me::MonitorActor, request::MonitorProjectionRequest, service)
    projection = monitorprojection(parsetype(request.typename))
    @debug "monitorprojection for $(request.typename): $projection"
    send(service, me, request.respondto, MonitorProjectionResponse(projection, request.token))
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
        if typeof(m.sig) === DataType # TODO handle UnionAll message types
            typename = string(messagetype(m.sig))
            if typename !== "Any"
                push!(result, typename)
            end
        end
    end
    send(service, me, request.respondto, ActorInterfaceResponse(request.box, result, request.token))
end