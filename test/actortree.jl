# SPDX-License-Identifier: LGPL-3.0-only
# This test builds a binary tree of TreeActors, growing a new level for every
# Start message received by the TreeCreator.
# The growth of every leaf is reported back by its parent to the
# TreeCreator, which counts the nodes in the tree.

using Test
using CircoCore
import CircoCore.onmessage

Start = Nothing

struct GrowRequest
    creator::Addr
end

struct GrowResponse
    leafsgrown::Vector{Addr}
end

mutable struct TreeActor{TCore} <: AbstractActor{TCore}
    children::Vector{Addr}
    core::TCore
end
TreeActor(core) = TreeActor(Addr[], core)

function onmessage(me::TreeActor, message::GrowRequest, service)
    if length(me.children) == 0
        push!(me.children, spawn(service, TreeActor(emptycore(service))))
        push!(me.children, spawn(service, TreeActor(emptycore(service))))
        send(service, me, message.creator, GrowResponse(me.children))
    else
        for child in me.children
            send(service, me, child, message)
        end
    end
end

mutable struct TreeCreator{TCore} <: AbstractActor{TCore}
    nodecount::Int64
    root::Addr
    core::TCore
end
TreeCreator(core) = TreeCreator(0, Addr(), core)

function onmessage(me::TreeCreator, ::Start, service)
    if CircoCore.isnulladdr(me.root)
        me.root = spawn(service, TreeActor(emptycore(service)))
        me.nodecount = 1
    end
    send(service, me, me.root, GrowRequest(addr(me)))
end

function onmessage(me::TreeCreator, message::GrowResponse, service)
    me.nodecount += length(message.leafsgrown)
end

@testset "Actor" begin
    @testset "Actor-Tree" begin
        ctx = CircoContext()
        creator = TreeCreator(emptycore(ctx))
        scheduler = ActorScheduler(ctx, [creator])#; msgqueue_capacity=2_000_000
        for i in 1:17
            @time scheduler(Msg{Start}(addr(creator)))
            @test creator.nodecount == 2^(i+1)-1
        end
        shutdown!(scheduler)
    end
end
