# SPDX-License-Identifier: MPL-2.0

# A Zygote creates a Cell which then repeatedly reincarnates and
# sends back notifications from lifecycle callbacks.
# Both die after DEPTH incarnations.

using Test
using CircoCore
using Plugins

const DEPTH = 10

mutable struct Zygote <: Actor{Any}
    cell_incarnation_count::Int
    cell_spawn_count::Int
    cell_death_count::Int
    core::Any
    Zygote() = new(0, 0, 0)
end

mutable struct Cell{T} <: Actor{Any}
    zygote::Addr
    core::Any
    Cell{T}(zygote) where T = new{T}(zygote)
end

CircoCore.onmessage(me::Zygote, ::OnSpawn, service) = begin
    child = spawn(service, Cell{Val(1)}(addr(me)))
    me.cell_incarnation_count = 1
    send(service, me, child, Reincarnate())
end

struct Reincarnate end

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
    end
end

struct Reincarnated
    addr::Addr
end

CircoCore.onmessage(me::Cell, msg::OnBecome, service) = begin
    @test msg.reincarnation isa Cell
    @test getval(me) + 1 == getval(msg.reincarnation)
    send(service, me, me.zygote, Reincarnated(addr(me)))
end

CircoCore.onmessage(me::Zygote, ::Reincarnated, service) = begin
    me.cell_incarnation_count += 1
end

struct Spawned
    addr::Addr
end

CircoCore.onmessage(me::Cell, ::OnSpawn, service) = begin
    send(service, me, me.zygote, Spawned(me))
end

CircoCore.onmessage(me::Zygote, msg::Spawned, service) = begin
    me.cell_spawn_count += 1
end

struct Died
    addr::Addr
end

CircoCore.onmessage(me::Cell, ::OnDeath, service) = begin
    send(service, me, me.zygote, Died(me))
end

CircoCore.onmessage(me::Zygote, msg::Died, service) = begin
    me.cell_death_count += 1
    die(service, me; exit = true)
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
    ctx = CircoContext(target_module = @__MODULE__; userpluginsfn = (;options...) -> [LifecyclePlugin])
    zygote = Zygote()
    scheduler = Scheduler(ctx, [zygote])
    wait(run!(scheduler; remote = false))
    @test zygote.cell_incarnation_count == DEPTH
    @test zygote.cell_spawn_count == 1
    @test zygote.cell_death_count == 1
    @test scheduler.plugins[:lifecycle].actor_spawning_calls[box(zygote)] == 1
    shutdown!(scheduler)
end
