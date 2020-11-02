# SPDX-License-Identifier: MPL-2.0

abstract type Event end
abstract type OneShotEvent <: Event end
abstract type RecurringEvent <: Event end
const RecurrentEvent = RecurringEvent

struct Subscribe{TEvent <: Event} # TODO: <: Request + handle forwarding
    subscriber::Addr
end

# TODO: Create a Trait for that + auto-creating the dispatcher
function onmessage(me::Actor, message::Subscribe{TEvent}, service) where TEvent <: Event
    send(service, me, me.eventdispatcher, message)
end
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
    push!(me.listeners[TEvent], message.subscriber)
end

function onmessage(me::EventDispatcher, message::TEvent, service) where {TEvent <: Event}
    for listener in get(me.listeners, TEvent, [])
        send(service, me, listener, message)
    end
end
