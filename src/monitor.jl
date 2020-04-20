struct ActorInfo
    box::ActorId
    x::Float64
    y::Float64
    z::Float64
end
MsgPack.msgpack_type(::Type{ActorInfo}) = MsgPack.StructType() 

struct ActorListRequest <: Request
    respondto::Addr
    token::Token
end
MsgPack.msgpack_type(::Type{ActorListRequest}) = MsgPack.StructType() 
MsgPack.msgpack_type(::Type{Msg{ActorListRequest}}) = MsgPack.StructType() 

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

function onmessage(me::MonitorActor, request::ActorListRequest, service)
    result = [ActorInfo(box(actor.core.addr), pos(actor).x, pos(actor).y, pos(actor).z) for actor in values(me.monitor.scheduler.actorcache)]
    send(service, me, request.respondto, ActorListResponse(result, request.token))
end