# SPDX-License-Identifier: MPL-2.0
using Test
using CircoCore
import CircoCore: onmessage, onspawn

const TARGET_COUNT = 13
const EVENT_COUNT = 133
struct Start end

struct NonTopicEvent <: Event
    value::String
end

struct TopicEvent <: Event
    topic::String
    value::String
end

mutable struct TestEventSource{TCore} <: Actor{TCore}
    eventdispatcher::Addr
    core::TCore
end
TestEventSource(core) = TestEventSource(Addr(), core)

CircoCore.traits(::Type{<:TestEventSource}) = (EventSource,)

mutable struct EventTarget{TCore} <: Actor{TCore}
    received_nontopic_count::Int64
    received_topic_count::Int64
    core::TCore
end
EventTarget(core) = EventTarget(0, 0, core)

function onspawn(me::TestEventSource, service)
    me.eventdispatcher = spawn(service, CircoCore.EventDispatcher(emptycore(service)))
    registername(service, "eventsource", me)
end

function onspawn(me::EventTarget, service)
    eventsource = getname(service, "eventsource")
    send(service, me, eventsource, Subscribe(NonTopicEvent, addr(me)))
    send(service, me, eventsource, Subscribe(TopicEvent, addr(me), "topic3"))
    send(service, me, eventsource, Subscribe(TopicEvent, addr(me), "topic4"))
    send(service, me, eventsource, Subscribe(TopicEvent, addr(me), event -> event.topic == "topic5"))
end

function onmessage(me::TestEventSource, message::Start, service)
    for i=1:EVENT_COUNT
        fire(service, me, NonTopicEvent("Test event #$i"))
        fire(service, me, TopicEvent("topic$i", "Topic event #$i"))
    end
end

function onmessage(me::EventTarget, message::NonTopicEvent, service)
    me.received_nontopic_count += 1
end

function onmessage(me::EventTarget, message::TopicEvent, service)
    me.received_topic_count += 1
end

@testset "Event" begin
    ctx = CircoContext(;target_module=@__MODULE__)
    source = TestEventSource(emptycore(ctx))
    targets = [EventTarget(emptycore(ctx)) for i=1:TARGET_COUNT]
    scheduler = Scheduler(ctx, [source; targets])
    scheduler(;remote = false) # to spawn the zygote
    send(scheduler, source, Start())
    scheduler(;remote = false)
    for target in targets
        @test target.received_nontopic_count == EVENT_COUNT
        @test target.received_topic_count == 3
    end

    # unsubscribe and rerun
    send(scheduler, source, UnSubscribe(addr(source), TopicEvent))
    send(scheduler, source, Start())
    scheduler(;remote = false)
    for target in targets
        @test target.received_nontopic_count == 2 * EVENT_COUNT
        @test target.received_topic_count == 3
    end

    shutdown!(scheduler)
end
