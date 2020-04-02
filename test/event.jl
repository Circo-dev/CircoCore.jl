# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore.onmessage, CircoCore.onschedule

const TARGET_COUNT = 13
const EVENT_COUNT = 133
Start = Nothing

struct TestEvent <: Event
    value::String
end

mutable struct EventSource <: AbstractActor
    eventdispatcher::Addr
    addr::Addr
    EventSource() = new()
end

mutable struct EventTarget <: AbstractActor
    received_count::UInt64
    addr::Addr
    EventTarget() = new(0)
end

# TODO: Create a Trait for that + handle multiple onschedule
function onmessage(me::EventSource, message::Subscribe{TEvent}, service) where TEvent <: Event
    send(service, me, me.eventdispatcher, message)
end
function fire(service, me::EventSource, event::TEvent) where TEvent <: Event
    send(service, me, me.eventdispatcher, event)
end
function onschedule(me::EventSource, service)
    me.eventdispatcher = spawn(service, EventDispatcher())
    registername(service, "eventsource", me)
end

function onschedule(me::EventTarget, service)
    send(service, me, getname(service, "eventsource"), Subscribe{TestEvent}(addr(me)))
end

function onmessage(me::EventSource, message::Start, service)
    for i=1:EVENT_COUNT
        fire(service, me, TestEvent("Test event #$i"))
    end
end

function onmessage(me::EventTarget, message::TestEvent, service)
    me.received_count += 1
end

@testset "Actor" begin
    @testset "Actor-Tree" begin
        source = EventSource()
        targets = [EventTarget() for i=1:TARGET_COUNT]
        scheduler = ActorScheduler([source; targets])
        @time scheduler(Msg{Start}(addr(source)))
        for target in targets
            @test target.received_count == EVENT_COUNT
        end
        shutdown!(scheduler)
    end
end
