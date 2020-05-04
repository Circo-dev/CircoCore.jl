# SPDX-License-Identifier: LGPL-3.0-only

# Simple search tree for testing cluster functions and for analyzing space optimization strategies

module SearchTreeTest

const ITEM_COUNT = 40_000_000
const ITEMS_PER_LEAF = 4000

using CircoCore
import CircoCore.onmessage
import CircoCore.onschedule
import CircoCore.monitorextra

using DataStructures

mutable struct Coordinator <: AbstractActor
    size::Int64
    root::Union{Addr, Nothing}
    core::CoreState
    Coordinator() = new(0)
end
monitorextra(me::Coordinator)  = (size = me.size, root = !isnothing(me.root) ? me.root.box : nothing)

mutable struct TreeNode{TValue} <: AbstractActor
    values::SortedSet{TValue}
    size::Int64
    left::Union{Addr, Nothing}
    right::Union{Addr, Nothing}
    sibling::Union{Addr, Nothing}
    splitvalue::Union{TValue, Nothing}
    core::CoreState
    TreeNode(values) = new{eltype(values)}(SortedSet(values), length(values), nothing, nothing, nothing, nothing)
end
monitorextra(me::TreeNode{TValue}) where TValue = 
(left = isnothing(me.left) ? nothing : me.left.box,
 right = isnothing(me.right) ? nothing : me.right.box,
 sibling = isnothing(me.sibling) ? nothing : me.sibling.box,
 splitval = isnothing(me.splitvalue) ? nothing : me.splitvalue,
 localsize = length(me.values),
 size = me.size)

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

struct SetSibling # TODO UnionAll Addr, default Setter and Getter, no more boilerplate like this. See #14
    value::Addr
end

struct SiblingInfo
    size::UInt64
end

genvalue() = rand(UInt32)

function onschedule(me::Coordinator, service)
    me.root = createnode(Array{UInt32}(undef, 0), service)
    send(service, me, addr(me), SearchResult(0, false))
end

function createnode(nodevalues, service)
    node = TreeNode(nodevalues)
    return spawn(service, node)
end

function onmessage(me::Coordinator, message::SearchResult, service)
    me.core.pos = Pos(0.0, 0.0, -5000.0)
    if me.size < ITEM_COUNT && rand() < 0.06 + me.size / ITEM_COUNT * 0.1
        send(service, me, me.root, Add(genvalue()))
        me.size += 1
    end
    send(service, me, me.root, Search(genvalue(), addr(me)))
    if (me.size > 1000000 && rand() < 0.1) 
        sleep(0.001)
    end
    yield()
end

function split(me::TreeNode, service)
    leftvalues = typeof(me.values)()
    rightvalues = typeof(me.values)()
    idx = 1
    splitat = length(me.values) / 2
    split = false
    for value in me.values
        if split
            push!(rightvalues, value)
        else
            push!(leftvalues, value)
            if idx >= splitat
                me.splitvalue = value
                split = true
            end
        end
        idx += 1
    end
    left = TreeNode(leftvalues)
    right = TreeNode(rightvalues)
    me.left = spawn(service, left)
    me.right = spawn(service, right)
    send(service, me, me.left, SetSibling(me.right))
    send(service, me, me.right, SetSibling(me.left))
    empty!(me.values)
end

function onmessage(me::TreeNode, message::Add, service)
    me.size += 1
    if isnothing(me.splitvalue)
        push!(me.values, message.value)
        if length(me.values) > ITEMS_PER_LEAF
            split(me, service)
        end
    else
        if message.value > me.splitvalue
            send(service, me, me.right, message)
        else
            send(service, me, me.left, message)
        end
    end
end

function onmessage(me::TreeNode{T}, message::Search{T}, service) where T
    if isnothing(me.splitvalue)
        if message.value in me.values
            send(service, me, message.searcher, SearchResult(message.value, true))
        else
            send(service, me, message.searcher, SearchResult(message.value, false))
        end
    else
        child = message.value > me.splitvalue ? me.right : me.left
        send(service, me, child, message)
    end
    if !isnothing(me.sibling) && rand() < 0.05
        send(service, me, me.sibling, SiblingInfo(me.size), -1)
    end
end

function onmessage(me::TreeNode, message::SetSibling, service)
    me.sibling = message.value
end

function onmessage(me::TreeNode, message::SiblingInfo, service)
#    println(message)
end

end

zygote() = SearchTreeTest.Coordinator()
