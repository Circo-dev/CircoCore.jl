using ActorInterfaces.Classic

struct Pop
    customer::Addr
end

struct Push
    content
end

struct StackNode
    content
    link::Union{Addr, Nothing}
end

struct Forwarder
    target::Addr
end

@ctx function Classic.onmessage(me::Forwarder, msg)
    send(me.target, msg)
end

@ctx function Classic.onmessage(me::StackNode, msg::Push)
    p = spawn(StackNode(me.content, me.link))
    become(StackNode(msg.content, p))
end

@ctx function Classic.onmessage(me::StackNode, msg::Pop)
    if !isnothing(me.link)
        become(Forwarder(me.link))
    end
    send(msg.customer, me.content)
end

import CircoCore
using Test

struct TestCoordinator
    received::Vector{Any}
end

@ctx function Classic.onmessage(me::TestCoordinator, msg)
    push!(me.received, msg)
end

@testset "Stack" begin
    ctx = CircoCore.CircoContext()
    s = CircoCore.Scheduler(ctx)
    CircoCore.run!(s)

    stack = StackNode(nothing, nothing)
    stackaddr = CircoCore.spawn(s, stack)
    coordinator = TestCoordinator([])
    coordaddr = CircoCore.spawn(s, coordinator)
    CircoCore.send(s, stackaddr, Push(42))
    CircoCore.send(s, stackaddr, Push(43))
    @test length(coordinator.received) == 0
    CircoCore.send(s, stackaddr, Pop(coordaddr))
    sleep(0.01)
    @test coordinator.received == Any[43]
    CircoCore.send(s, stackaddr, Pop(coordaddr))
    sleep(0.01)
    @test coordinator.received == Any[43, 42]
    CircoCore.send(s, stackaddr, Pop(coordaddr))
    sleep(0.01)
    @test coordinator.received == Any[43, 42, nothing]
    CircoCore.send(s, stackaddr, Pop(coordaddr))
    sleep(0.01)
    @test coordinator.received == Any[43, 42, nothing, nothing]
end