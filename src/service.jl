# SPDX-License-Identifier: LGPL-3.0-only

struct ActorService{TScheduler}
    scheduler::TScheduler
end

@inline function send(service::ActorService{TScheduler}, sender::AbstractActor, to::Addr, messagebody::TBody) where {TBody, TScheduler}
    message = Msg(address(sender), to, messagebody)
    deliver!(service.scheduler, message)
end

@inline function send(service::ActorService{TScheduler}, sender::AbstractActor, to::Addr, messagebody::TBody) where {TBody<:Request, TScheduler}
    settimeout(service.scheduler.tokenservice, Timeout(sender, token(messagebody)))
    message = Msg(address(sender), to, messagebody)
    deliver!(service.scheduler, message)
end

@inline function spawn(service::ActorService{TScheduler}, actor::AbstractActor)::Addr where {TScheduler}
    schedule!(service.scheduler, actor)
end

@inline function die(service::ActorService{TScheduler}, actor::AbstractActor) where {TScheduler}
    unschedule!(service.scheduler, actor)
end

@inline function migrate(service::ActorService{TScheduler}, actor::AbstractActor, topostcode::PostCode) where {TScheduler}
    migrate!(service.scheduler, actor, topostcode)
end

@inline function registername(service::ActorService{TScheduler}, name::String, handler::AbstractActor) where {TScheduler}
    registername(service.scheduler.registry, name, address(handler))
end

@inline function getname(service::ActorService{TScheduler}, name::String) where {TScheduler}
    return getname(service.scheduler.registry, name)
end
