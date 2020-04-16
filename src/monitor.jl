struct ActorInfo
    core::CoreState
end

struct ActorListRequest
    respondto::Addr
end

struct ActorListResponse
    actors::Array{ActorInfo}
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
end

function onmessage(me::MonitorActor, request::ActorListRequest, service)
    result = [actor.core for actor in me.monitor.scheduler.actorcache.values()]
    send(service, me, request.respondto, ActorListResponse(result))
end