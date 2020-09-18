# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore: onmessage, onschedule

const TARGET_COUNT = 13
const EVENT_COUNT = 133
Start = Nothing

struct TestEvent <: Event
    value::String
end

mutable struct EventSource{TCore} <: AbstractActor{TCore}
    eventdispatcher::Addr
    core::Core
end
EventSource(core) = new(nulladdr, core)

mutable struct EventTarget <: AbstractActor{TCoreState}
    received_count::UInt64
    core::CoreState
    EventTarget() = new(0)
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
        ctx = CircoContext()
        source = EventSource()
        targets = [EventTarget() for i=1:TARGET_COUNT]
        scheduler = ActorScheduler(ctx, [source; targets])
        @time scheduler(Msg{Start}(addr(source)))
        for target in targets
            @test target.received_count == EVENT_COUNT
        end
        shutdown!(scheduler)
    end
end
