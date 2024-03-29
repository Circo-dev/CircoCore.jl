# SPDX-License-Identifier: MPL-2.0

abstract type AbstractService{TScheduler, TMsg, TCore} end

struct Service{TScheduler, TMsg, TCore} <: AbstractService{TScheduler, TMsg, TCore}
    scheduler::TScheduler
    emptycore::TCore
end

Base.show(io::IO, ::Type{<:AbstractService}) = print(io, "Circo Service")

Service(ctx::AbstractContext, scheduler::AbstractScheduler) =
    Service{typeof(scheduler), ctx.msg_type, ctx.corestate_type}(scheduler, emptycore(ctx))

emptycore(s::AbstractService) = s.emptycore
emptycore(sdl::AbstractScheduler) = emptycore(sdl.service)

plugin(service::AbstractService, symbol::Symbol) = plugin(service.scheduler, symbol)
plugin(sdl::AbstractScheduler, symbol::Symbol) = sdl.plugins[symbol]

"""
    send(service, sender::Actor, to::Addr, messagebody::Any; energy::Real = 1, timeout::Real = 2.0)

Send a message from an actor to an another.

Part of the actor API, can be called from a lifecycle callback, providing the `service` you got.

`messagebody` can be of any type, but a current limitation of inter-node communication is
that the serialized form of `messagebody` must fit in an IPv4 UDP packet with ~100 bytes margin.
The exact value depends on the MTU size of the network and changing implementation details, but 1380 bytes
can be considered safe. You may be able to tune your system to get higher values.

If `messagebody` is a `Request`, a timeout will be set for the token of it. The `timeout` keyword argument
can be used to control the deadline (seconds).

`energy` sets the energy and sign of the Infoton attached to the message (if the infoton optimizer is running).

# Examples

```julia
const QUERY = "The Ultimate Question of Life, The Universe, and Everything."

mutable struct MyActor <: Actor{TCoreState}
    searcher::Addr
    core::CoreState
    MyActor() = new()
end

struct Start end

struct Search
    query::String
end

[...] # Spawn the searcher or receive its address


function CircoCore.onmessage(me::MyActor, message::Start, service)
    send(service,
            me,
            me.searcher,
            Search(QUERY, addr(me)))
end
```

# Implementation

Please note that `service` is always the last argument of lifecycle callbacks
like `onmessage`.
It's because `onmessage` is dynamically dispatched, and `service` provides no
information about where to dispatch. (Only one service instance exists
as of `v"0.2.0"`) Listing it at the end improves performance.

On the other hand, actor API endpoints like `send` are always statically dispatched,
thus they can accept the service as their first argument, allowing the user to treat
e.g. "`spawn(service`" as a single unit of thought and not forget to write out the
ballast `service`.

Consistency is just as important as convenience. But performance is king.
"""
@inline function send(service::AbstractService{TScheduler, TMsg}, sender, to::Addr, messagebody; kwargs...) where {TScheduler, TMsg, TCore}
    message = TMsg(sender, to, messagebody, service.scheduler; kwargs...)
    deliver!(service.scheduler, message)
end

@inline function send(service::AbstractService{TScheduler, TMsg}, sender, to::Addr, messagebody::Request; timeout = 2.0, kwargs...) where {TScheduler, TMsg}
    settimeout(service.scheduler.tokenservice, Timeout(sender, token(messagebody), timeout, messagebody))
    message = TMsg(sender, to, messagebody, service.scheduler; kwargs...)
    deliver!(service.scheduler, message)
end

@inline function send(service::AbstractService, sender, to, messagebody; kwargs...)
    send(service, sender, addr(to), messagebody; kwargs...)
end

@inline function send(service::AbstractService, sender, to::Nothing, messagebody; kwargs...)
    @error "Sending message to 'Nothing' is not possible!"
end

@inline function bulksend(service::AbstractService, sender::Actor, targets, messagebody; kwargs...)
    for target in targets
        send(service, sender, target, messagebody; kwargs...)
    end
end

"""
    spawn(service, actor::Actor, [pos::Pos])::Addr

Spawn the given actor on the scheduler represented by `service`, return the address of it.

Part of the actor API, can be called from a lifecycle callback, providing the `service` you got.

The `OnSpawn` message will be delivered to `actor` before this function returns.

# Examples

# TODO: update this sample

```
mutable struct ListItem{TData, TCore} <: Actor{TCore}
    data::TData
    next::Union{Nothing, Addr}
    core::TCore
    ListItem(data, core) = new{typeof(data), typeof(core)}(data, nothing, core)
end

struct Append{TData}
    value::TData
end

function CircoCore.onmessage(me::ListItem, message::Append, service)
    me.next = spawn(service, ListItem(message.value))
end
```
"""
@inline function spawn(service::AbstractService, actor::Actor)::Addr
    return spawn(service.scheduler, actor)
end

"""
    become(service, old::Actor, reincarnated::Actor)

Reincarnates the `old` actor into `new`, meaning that `old` will be unscheduled,
and `reincarnated` will be scheduled reusing the address of `old`.

The `onbecome` lifecycle callback will be called.

Note: As the name suggests, `become` is the Circonian way of behavior change.
"""
function become(service::AbstractService{TScheduler, TMsg}, old::Actor, reincarnated::Actor) where {TScheduler, TMsg}
    scheduler = service.scheduler
    _immediate_delivery(old, scheduler,  TMsg(addr(scheduler), old, OnBecome(reincarnated), scheduler))
    reincarnated.core = old.core
    unschedule!(scheduler, old)
    return spawn(service, reincarnated)
end

"""
    die(service, me::Actor; exit=false)

Permanently unschedule the actor from its current scheduler.

if `exit` is true and this is the last actor on its scheduler,
the scheduler will be terminated.
"""
@inline function die(service::AbstractService, me::Actor; exit = false)
    kill!(service.scheduler, me)
    if exit    
        if service.scheduler.actorcount <= service.scheduler.startup_actor_count
            service.scheduler.exitflag = true
            @debug "Scheduler's exitflag raised"
        end
    end
end

"""
    registername(service, name::String, actor::Union{Addr,Actor})

Register the given actor under the given name in the scheduler-local name registry.

Note that there is no need to unregister the name when migrating or dying

# TODO implement manual and auto-unregistration
"""
@inline function registername(service::AbstractService, name::String, actor::Addr)
    registry = get(service.scheduler.plugins, :registry, nothing)
    isnothing(registry) && throw(NoRegistryException("Cannot register name $name: Registry plugin not found"))
    registername(registry, name, actor)
end
registername(service::AbstractService, name::String, actor::Actor) = registername(service, name, addr(actor))
registername(sdl::AbstractScheduler, name::String, actor_addr) = registername(sdl.service, name, actor_addr)

"""
    function getname(service, name::String)::Union{Addr, Nothing}

Return the registered name from the scheduler-local registry, or nothing.

See also: [`NameQuery`](@ref)
"""
@inline function getname(service, name::String)::Union{Addr, Nothing}
    registry = get(service.scheduler.plugins, :registry, nothing)
    isnothing(registry) && throw(NoRegistryException("Cannot search for name $name: Registry plugin not found"))
    return getname(registry, name)
end

@inline function settimeout(service::AbstractService, actor::Actor, timeout_secs::Real = 0.0)
    return settimeout(service.scheduler.tokenservice, Timeout(actor, Token(), timeout_secs))
end

@inline function cleartimeout(service::AbstractService, token::Token)
    return cleartimeout(service.scheduler.tokenservice, token)
end

@inline pos(service::AbstractService) = pos(service.scheduler) # TODO find its place
