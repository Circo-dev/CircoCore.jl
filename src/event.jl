# SPDX-License-Identifier: MPL-2.0

abstract type Event end
abstract type OneShotEvent <: Event end
abstract type RecurringEvent <: Event end
const RecurrentEvent = RecurringEvent

"""
    Subscribe(eventtype::Type, subscriber::Union{Actor, Addr}, filter::Union{Nothing, String, Function} = nothing)

Message for subscribing to events of the given `eventtype`.

The subscription can be optionally filtered by a topic string or a predicate function.
Filtering and subscription management will be done by the event dispatcher, which is a separate actor.

`eventtype` must be concrete.

# Examples

```julia
    fs = getname(service, "fs")
    send(service, me, fs, Subscribe(FSEvent, me, "MODIFY"))
    send(service, me, fs, Subscribe(FSEvent, me, event -> event.path == "test.txt"))
```

"""
struct Subscribe # TODO: <: Request + handle forwarding
    subscriber::Addr
    filter::Union{Nothing, String, Function}
    eventtype::Type
    Subscribe(eventtype:: Type, subscriber::Actor, filter=nothing) = new(addr(subscriber), filter, eventtype)
    Subscribe(eventtype:: Type, subscriber::Addr, filter=nothing) = new(subscriber, filter, eventtype)
end

"""
    Unsubscribe(subscriber::Addr, eventtype::Type)

Message for unsubscribing from events of the given `eventtype`.

Cancels all subscriptions of the given `subscriber` for the given `eventtype`.
"""
struct UnSubscribe
    subscriber::Addr
    eventtype::Type
end


"""
    EventSource

Trait for actors that can publish events.

Manages subscriptions and dispatches events.
You need to add a field `eventdispatcher::Addr` to your actor to use this trait.
"""
struct EventSource end

function initdispatcher(me::Actor, service)
    @assert hasfield(typeof(me), :eventdispatcher) "Missing field 'eventdispatcher::Addr' in $(typeof(me))"
    @assert !isdefined(me, :eventdispatcher) || me.eventdispatcher == Addr()
    me.eventdispatcher = spawn(service, EventDispatcher(emptycore(service)))
end

ontraitmessage(::EventSource, me::Actor, msg::Union{Subscribe, UnSubscribe}, service) = begin
    send(service, me, me.eventdispatcher, msg)
end

ontraitmessage(::EventSource, me::Actor, msg::OnSpawn, service) = begin
    initdispatcher(me, service)
end

"""
    EventSourceDied

SigTerm cause for terminating event dispatchers.
"""
struct EventSourceDied end

ontraitmessage(::EventSource, me::Actor, msg::OnDeath, service) = begin
    send(service, me, me.eventdispatcher, SigTerm(EventSourceDied()))
end

"""
    fire(service, me::Actor, event::Event)

Fire an event on the actor to be delivered by the actor's eventdispatcher.

To fire an event, the actor must have a field `eventdispatcher::Addr`,
which will be filled automatically.
"""
function fire(service, me::Actor, event::TEvent) where TEvent <: Event
    send(service, me, me.eventdispatcher, event)
end

mutable struct EventDispatcher{TCore} <: Actor{TCore}
    listeners::IdDict{Type{<:Event}, Vector{Subscribe}}
    core::TCore
end
EventDispatcher(core) = EventDispatcher(IdDict{Type{<:Event}, Vector{Subscribe}}(), core)

function onmessage(me::EventDispatcher, msg::Subscribe, service)
    if !haskey(me.listeners, msg.eventtype)
        me.listeners[msg.eventtype] = Subscribe[]
    end
    push!(me.listeners[msg.eventtype], msg) # TODO ack
end

function onmessage(me::EventDispatcher, msg::UnSubscribe, service)
    if !haskey(me.listeners, msg.eventtype)
        return
    end
    filter!(me.listeners[msg.eventtype]) do sub
        return sub.eventtype == msg.eventtype && sub.subscriber == msg.subscriber
    end
    # TODO ack
end

function onmessage(me::EventDispatcher, msg::Event, service)
    listeners = get!(me.listeners, typeof(msg)) do
        return Subscribe[]
    end
    for subscription in listeners
        if subscription.filter isa Nothing ||
            (hasfield(typeof(msg), :topic) && subscription.filter isa String && msg.topic == subscription.filter) ||
            (subscription.filter isa Function && subscription.filter(msg) == true)
            send(service, me, subscription.subscriber, msg)
        end
    end
end

