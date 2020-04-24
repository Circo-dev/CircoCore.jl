# SPDX-License-Identifier: LGPL-3.0-only

# Simple search tree for testing cluster functions and for analyzing space optimization strategies

module SearchTreeTest

const ITEM_COUNT = 5000

using CircoCore
import CircoCore.onmessage
import CircoCore.onschedule

mutable struct Coordinator <: AbstractActor
    root::Union{Addr, Nothing}
    core::CoreState
    Coordinator() = new()
end

mutable struct TreeNode{TValue} <: AbstractActor
    value::TValue
    left::Union{Addr, Nothing}
    right::Union{Addr, Nothing}
    core::CoreState
    TreeNode(value) = new{typeof(value)}(value, nothing, nothing)
end

struct Add{TValue}
    value::TValue
end

struct Search{TValue}
    value::TValue
    searcher::Addr
end

struct SearchResult{TValue}
    value::TValue
    found::Bool
end

genvalue() = rand(UInt16)

function onschedule(me::Coordinator, service)
    me.root = createnode(genvalue(), service)
    for i in 1:ITEM_COUNT - 1
        send(service, me, me.root, Add(genvalue()))
    end
    send(service, me, addr(me), SearchResult(0, false))
end

function createnode(nodevalue, service)
    node = TreeNode(nodevalue)
    return spawn(service, node)
end

function onmessage(me::Coordinator, message::SearchResult, service)
    me.core.pos += Pos(0.0, 0.0, 0.95)
    send(service, me, me.root, Search(genvalue(), addr(me)))
    yield()
end

function onmessage(me::TreeNode, message::Add, service)
    if message.value > me.value
        if isnothing(me.right)
            me.right = createnode(message.value, service)
        else
            send(service, me, me.right, message)
        end
    else
        if isnothing(me.left)
            me.left = createnode(message.value, service)
        else
            send(service, me, me.left, message)
        end
    end
end

function onmessage(me::TreeNode{T}, message::Search{T}, service) where T
    if me.value == message.value
        send(service, me, message.searcher, SearchResult(message.value, true))
    else
        child = message.value > me.value ? me.right : me.left
        if isnothing(child)
            send(service, me, message.searcher, SearchResult(message.value, false))
        else
            send(service, me, child, message)
        end
    end
end

end

zygote() = SearchTreeTest.Coordinator()
