# SPDX-License-Identifier: MPL-2.0
using Test
using CircoCore
import CircoCore: onmessage, onspawn

const TARGET_COUNT = 13
const EVENT_COUNT = 133
struct Start end

struct TestEvent <: Event
    value::String
end

mutable struct EventSource{TCore} <: Actor{TCore}
    eventdispatcher::Addr
    core::TCore
end
EventSource(core) = EventSource(Addr(), core)

mutable struct EventTarget{TCore} <: Actor{TCore}
    received_count::Int64
    core::TCore
end
EventTarget(core) = EventTarget(0, core)

function onspawn(me::EventSource, service)
    me.eventdispatcher = spawn(service, EventDispatcher(emptycore(service)))
    registername(service, "eventsource", me)
end

function onspawn(me::EventTarget, service)
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
        ctx = CircoContext(;target_module=@__MODULE__)
        source = EventSource(emptycore(ctx))
        targets = [EventTarget(emptycore(ctx)) for i=1:TARGET_COUNT]
        scheduler = Scheduler(ctx, [source; targets])
        scheduler(;remote = false, exit = true) # to spawn the zygote
        send(scheduler, source, Start())
        @time scheduler(;remote = false, exit = true)
        for target in targets
            @test target.received_count == EVENT_COUNT
        end
        shutdown!(scheduler)
    end
end
