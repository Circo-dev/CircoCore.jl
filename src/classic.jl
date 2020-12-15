import ActorInterfaces

struct CircoCtx{TActor, TService, TCore}
    actor::TActor
    service::TService
    CircoCtx(actor::Actor{TCore}, service) where TCore = new{typeof(actor), typeof(service), TCore}(actor, service)
end

mutable struct ClassicActor{TState, TCore} <: Actor{TCore}
    state::TState
    core::TCore
end

struct CircoAddr <: ActorInterfaces.Classic.Addr
    addr::Addr
end

import Base.convert
function Base.convert(::Type{Addr}, a::CircoAddr)
    return a.addr
end
function Base.convert(::Type{ActorInterfaces.Classic.Addr}, a::Addr)
    return CircoAddr(a)
end

struct CircoMessage
    addr::Addr
end

function onmessage(me::ClassicActor, msg, service)
    ActorInterfaces.Classic.onmessage(me.state, msg, CircoCtx(me, service))
end

function ActorInterfaces.Classic.self(ctx::CircoCtx)::CircoAddr
    return CircoAddr(addr(ctx.actor))
end

function ActorInterfaces.Classic.send(recipient::CircoAddr, msg, ctx::CircoCtx)
    send(ctx.service, ctx.actor, recipient.addr, msg)
end

function ActorInterfaces.Classic.spawn(behavior, ctx::CircoCtx)::CircoAddr
    spawned = spawn(ctx.service, ClassicActor(behavior, emptycore(ctx.service)))
    return CircoAddr(spawned)
end

function ActorInterfaces.Classic.become(behavior, ctx::CircoCtx)
    become(ctx.service, ctx.actor, ClassicActor(behavior, ctx.actor.core))
    return nothing
end


spawn(scheduler::AbstractScheduler, actor) = spawn(scheduler, ClassicActor(actor, emptycore(scheduler.service)))

function send(scheduler::AbstractScheduler, to::CircoAddr, msgbody; kwargs...)
    send(scheduler, to.addr, msgbody; kwargs...)
end

