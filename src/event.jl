# SPDX-License-Identifier: LGPL-3.0-only

abstract type Event end
abstract type OneShotEvent <: Event end
abstract type RecurringEvent <: Event end
RecurrentEvent = RecurringEvent

struct Subscribe{TEvent <: Event} # TODO: <: Request + handle forwarding
    subscriber::Addr
end

mutable struct EventDispatcher <: AbstractActor
    listeners::Dict{Type{<:Event},Array{Addr}}
    core::CoreState
    EventDispatcher() = new(Dict([]))
end

# TODO: Create a Trait for that + auto-creating the dispatcher
function onmessage(me::AbstractActor, message::Subscribe{TEvent}, service) where TEvent <: Event
    send(service, me, me.eventdispatcher, message)
end
function fire(service, me::AbstractActor, event::TEvent) where TEvent <: Event
    send(service, me, me.eventdispatcher, event)
end


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
