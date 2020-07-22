# SPDX-License-Identifier: LGPL-3.0-only

struct ActorService{TScheduler}
    scheduler::TScheduler
end

function plugin(service::ActorService, symbol::Symbol)
    return service.scheduler.plugins[symbol]
end

"""
    send(service, sender::AbstractActor, to::Addr, messagebody::Any, energy::Real = 1; timeout::Second = Second(2))

Send a message from an actor to an another.

Part of the actor API, can be called from a lifecycle callback, providing the `service` you got.

`messagebody` can be of any type, but a current limitation of inter-node communication is
that the serialized form of `messagebody` must fit in an IPv4 UDP packet with ~100 bytes margin.
The exact value depends on the MTU size of the network and changing implementation details, but 1380 bytes
can be considered safe. You may be able to tune your system to get higher values.

If `messagebody` is a `Request`, a timeout will be set for the token of it. The `timeout` keyword argument
can be used to control the deadline.

`energy` sets the energy and sign of the Infoton attached to the message.

# Examples

```julia
const QUERY = "The Ultimate Question of Life, The Universe, and Everything."

mutable struct MyActor <: AbstractActor
    searcher::Addr
    core:: CoreState
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
as of `v"0.2.0"`)

On the other hand, actor API endpoints like `send` are always statically dispatched,
thus they can accept the service as their first argument, allowing the user to treat
e.g. "`spawn(service`" as a single unit of thought and not forget to write out the meaningless `service`.

Consistency is just as important as convenience. But performance is king. 
"""
@inline function send(service::ActorService, sender::AbstractActor, to::Addr, messagebody, energy::Real = 1)
    message = Msg(sender, to, messagebody, energy)
    deliver!(service.scheduler, message)
end

@inline function send(service::ActorService, sender::AbstractActor, to::Addr, messagebody::TBody, energy::Real = 1;timeout::Second = Second(2)) where {TBody<:Request}
    settimeout(service.scheduler.tokenservice, Timeout(sender, token(messagebody), timeout))
    message = Msg(sender, to, messagebody, energy)
    deliver!(service.scheduler, message)
end

"""
    spawn(service, actor::AbstractActor, [pos::Pos])::Addr

Spawn the given actor on the scheduler represented by `service`, return the address of it.

Part of the actor API, can be called from a lifecycle callback, providing the `service` you got.

The `onschedule` callback of `actor` will run before this function returns.

# Examples

```
mutable struct ListItem{TData} <: AbstractActor
    data::TData
    next::Addr
    core::CoreState
    ListItem(data) = new{typeof(data)}(data)
end

struct Append{TData}
    value::TData
end

function CircoCore.onmessage(me::ListItem, message::Append, service)
    me.next = spawn(service, ListItem(message.value))
end
```
"""
@inline function spawn(service::ActorService, actor::AbstractActor)::Addr
    return schedule!(service.scheduler, actor)
end

@inline function spawn(service::ActorService, actor::AbstractActor, pos::Pos)::Addr
    addr = schedule!(service.scheduler, actor)
    actor.core.pos = pos
    return addr
end

"""
    die(service, me::AbstractActor)

Unschedule the actor from its current scheduler.
"""
@inline function die(service::ActorService, me::AbstractActor)
    unschedule!(service.scheduler, me)
end

"""
    registername(service, name::String, actor::AbstractActor)

Register the given actor under the given name in the scheduler-local name registry.

Note that there is no need to unregister the name when migrating or dying

# TODO implement manual and auto-unregistration
"""
@inline function registername(service, name::String, actor::AbstractActor)
    registername(service.scheduler.registry, name, addr(actor))
end

"""
    function getname(service, name::String)::Union{Addr, Nothing}

Return the registered name from the scheduler-local registry, or nothing.

See also: [`NameQuery`](@ref)
"""
@inline function getname(service, name::String)::Union{Addr, Nothing}
    return getname(service.scheduler.registry, name)
end

@inline pos(service::ActorService) = pos(service.scheduler)
