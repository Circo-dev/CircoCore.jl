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

mutable struct TreeActor <: AbstractActor
    children::Vector{Addr}
    core::CoreState
    TreeActor() = new([])
end

function onmessage(me::TreeActor, message::GrowRequest, service)
    if length(me.children) == 0
        push!(me.children, spawn(service, TreeActor()))
        push!(me.children, spawn(service, TreeActor()))
        send(service, me, message.creator, GrowResponse(me.children))
    else
        for child in me.children
            send(service, me, child, message)
        end
    end
end

mutable struct TreeCreator <: AbstractActor
    nodecount::UInt64
    root::Union{Nothing,Addr}
    core::CoreState
    TreeCreator() = new(0, nothing)
end

function onmessage(me::TreeCreator, ::Start, service)
    if isnothing(me.root)
        me.root = spawn(service, TreeActor())
        me.nodecount = 1
    end
    send(service, me, me.root, GrowRequest(addr(me)))
end

function onmessage(me::TreeCreator, message::GrowResponse, service)
    me.nodecount += length(message.leafsgrown)
end

@testset "Actor" begin
    @testset "Actor-Tree" begin
        creator = TreeCreator()
        scheduler = ActorScheduler([creator])
        for i in 1:17
            @time scheduler(Msg{Start}(addr(creator)))
            @test creator.nodecount == 2^(i+1)-1
        end
        shutdown!(scheduler)
    end
end
