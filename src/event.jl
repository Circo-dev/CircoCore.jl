# SPDX-License-Identifier: MPL-2.0

abstract type Event end
abstract type OneShotEvent <: Event end
abstract type RecurringEvent <: Event end
const RecurrentEvent = RecurringEvent

"""
    Subscribe{TEvent <: Event}(subscriber::Addr)

    Message type for subscribing to the event of type TEvent.
"""
struct Subscribe{TEvent <: Event} # TODO: <: Request + handle forwarding
    subscriber::Addr
end

# TODO: Create a Trait for that + auto-creating the dispatcher
function onmessage(me::Actor, message::Subscribe{TEvent}, service) where TEvent <: Event
    @assert isdefined(me, :eventdispatcher) "Missing or undefined field 'eventdispatcher' from $(typeof(me))"
    send(service, me, me.eventdispatcher, message)
end

"""
    fire(service, me::Actor, event::Event)

    Fire an event on the actor to be delivered by the actor's eventdispatcher.

    To fire an event, the actor must have a field `eventdispatcher::Addr`.
"""
function fire(service, me::Actor, event::TEvent) where TEvent <: Event
    send(service, me, me.eventdispatcher, event)
end

mutable struct EventDispatcher{TCore} <: Actor{TCore}
    listeners::IdDict #{Type{<:Event},Array{Addr}}
    core::TCore
end
EventDispatcher(core) = EventDispatcher(IdDict(), core)

function onmessage(me::EventDispatcher, message::Subscribe{TEvent}, service) where {TEvent<:Event}
    if !haskey(me.listeners, TEvent)
        me.listeners[TEvent] = Array{Addr}(undef, 0)
    end
    push!(me.listeners[TEvent], message.subscriber) # TODO ack
end

function onmessage(me::EventDispatcher, message::TEvent, service) where {TEvent <: Event}
    for listener in get(me.listeners, TEvent, [])
        send(service, me, listener, message)
    end
end
