
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
    actors::Array{ActorInfo}
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