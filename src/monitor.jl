struct ActorInfo
    core::CoreState
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

function onmessage(me::MonitorActor, request::ActorListRequest, service)
    result = [ActorInfo(actor.core) for actor in values(me.monitor.scheduler.actorcache)]
    send(service, me, request.respondto, ActorListResponse(result, request.token))
end