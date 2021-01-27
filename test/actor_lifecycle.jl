# SPDX-License-Identifier: MPL-2.0

# A Zygote creates a Cell which then repeatedly reincarnates. Both die after DEPTH incarnations

using Test
using CircoCore
using Plugins

const DEPTH = 10

mutable struct Zygote <: Actor{Any}
    incarnation_count::Int
    core::Any
    Zygote() = new(0)
end

mutable struct Cell{T} <: Actor{Any}
    zygote::Addr
    core::Any
    Cell{T}(zygote) where T = new{T}(zygote)
end

struct Reincarnate end
struct Reincarnated
    addr::Addr
end

CircoCore.onspawn(me::Zygote, service) = begin
    child = spawn(service, Cell{Val(1)}(addr(me)))
    me.incarnation_count = 1
    send(service, me, child, Reincarnate())
end

getval(v::Val{V}) where V = V
getval(c::Cell{T}) where T = getval(T)

CircoCore.onmessage(me::Cell, ::Reincarnate, service) = begin
    depth = getval(me)
    if depth >= DEPTH
        die(service, me)
    else
        reincarnated = Cell{Val(depth + 1)}(me.zygote)
        @test become(service, me, reincarnated) == addr(me)
        send(service, reincarnated, addr(me), Reincarnate())
        send(service, reincarnated, reincarnated.zygote, Reincarnated(addr(reincarnated)))
    end
end

CircoCore.onmessage(me::Zygote, msg::Reincarnated, service) = begin
    me.incarnation_count += 1
    if me.incarnation_count == DEPTH
        die(service, me)
    end
end

struct LifecyclePlugin <: Plugin
    actor_spawning_calls::Dict{ActorId, Int}
    LifecyclePlugin(;options...) = new(Dict())
end

Plugins.symbol(::LifecyclePlugin) = :lifecycle
Plugins.register(LifecyclePlugin)

function CircoCore.actor_spawning(p::LifecyclePlugin, scheduler, actor)
    count = get(p.actor_spawning_calls, box(actor), 0)
    p.actor_spawning_calls[box(actor)] = count + 1
end

@testset "Actor Lifecycle" begin
    ctx = CircoContext(;userpluginsfn = (;options...) -> [LifecyclePlugin])
    zygote = Zygote()
    scheduler = Scheduler(ctx, [zygote])
    wait(run!(scheduler; remote = false, exit = true))
    @test zygote.incarnation_count == DEPTH
    @test scheduler.plugins[:lifecycle].actor_spawning_calls[box(zygote)] == 1
    shutdown!(scheduler)
end