# SPDX-License-Identifier: LGPL-3.0-only

# Simple search tree for testing cluster functions and for analyzing space optimization strategies

module SearchTreeTest

const ITEM_COUNT = 1_000_000
const ITEMS_PER_LEAF = 1000
const SIBLINGINFO_FREQ = 0 #0..255

using CircoCore, DataStructures, LinearAlgebra
import CircoCore.onmessage
import CircoCore.onschedule
import CircoCore.monitorextra
import CircoCore.check_migration

const STOP = 0
const STEP = 1
const SLOW = 20
const FAST = 98
const FULLSPEED = 100

mutable struct Coordinator <: AbstractActor
    runmode::UInt8
    size::Int64
    resultcount::UInt64
    lastreportts::UInt64
    root::Union{Addr, Nothing}
    core::CoreState
    Coordinator() = new(STOP, 0, 0, 0)
end
monitorextra(me::Coordinator)  = (
    runmode=me.runmode,    
    size = me.size,
    root =!isnothing(me.root) ? me.root.box : nothing
)

struct RunFull
    a::UInt8 # TODO fix MsgPack to allow empty structs
end

struct Step # TODO Create UI to allow parametrized messages
    a::UInt8
end

struct RunSlow
    a::UInt8
end

struct RunFast
    a::UInt8
end

struct Stop
    a::UInt8
end

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
monitorextra(me::TreeNode) = 
(left = isnothing(me.left) ? nothing : me.left.box,
 right = isnothing(me.right) ? nothing : me.right.box,
 sibling = isnothing(me.sibling) ? nothing : me.sibling.box,
 splitval = me.splitvalue,
 size = me.size)

 @inline function actorcount_scheduler_infoton(scheduler, actor::AbstractActor)
    dist = norm(scheduler.pos - actor.core.pos)
    dist === 0.0 && return Infoton(scheduler.pos, 0.0)
    energy = (600.0 - scheduler.actorcount) * 3e-1 / dist
    return Infoton(scheduler.pos, energy)
end

CircoCore.scheduler_infoton(scheduler, actor::AbstractActor) = actorcount_scheduler_infoton(scheduler, actor)

@inline CircoCore.check_migration(me::Union{TreeNode, Coordinator}, alternatives::MigrationAlternatives, service) = begin
    if norm(pos(service) - pos(me)) > 1100 # Do not check for alternatives if too close to the current scheduler
        #println("check $alternatives")
        migrate_to_nearest(me, alternatives, service)
    end
end

const TARGET_DISTANCE = 200
const I = 1.0

@inline CircoCore.apply_infoton(targetactor::AbstractActor, infoton::Infoton) = begin
    diff = infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    energy = infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE #|| energy < 0 && difflen > TARGET_DISTANCE / 2
        return nothing
    end
    targetactor.core.pos += diff / difflen * energy * I
    return nothing
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

struct SetSibling # TODO UnionAll Addr, default Setter and Getter, no more boilerplate like this. See #14
    value::Addr
end

struct SiblingInfo
    size::UInt64
end

genvalue() = rand(UInt32)
nearpos(pos::Pos, maxdistance=10.0) = pos + Pos(rand() * maxdistance, rand() * maxdistance, rand() * maxdistance)

function onschedule(me::Coordinator, service)
    me.core.pos = Pos(0, 0, 0)
    me.root = createnode(Array{UInt32}(undef, 0), service, nearpos(me.core.pos))
    if me.runmode !== STOP
        startround(me, service)
    end
end

function createnode(nodevalues, service, pos=nothing)
    node = TreeNode(nodevalues)
    retval = spawn(service, node)
    if !isnothing(pos)
        node.core.pos = pos
    end
    return retval
end

function startround(me::Coordinator, service, parallel = 1)
    if me.size < ITEM_COUNT && rand() < 0.06 + me.size / ITEM_COUNT * 0.1
        send(service, me, me.root, Add(genvalue()))
        me.size += 1
    end
    me.runmode == STOP && return nothing
    if me.runmode == STEP
        me.runmode = STOP
        return nothing
    end
    if (me.runmode != FULLSPEED && rand() > 0.01 * me.runmode) 
        sleep(0.001)
    end
    for i in 1:parallel
        send(service, me, me.root, Search(genvalue(), addr(me)))
    end
end

function onmessage(me::Coordinator, message::SearchResult, service)
    #me.core.pos = Pos(0, 0, 0)
    me.resultcount += 1
    if time_ns() > me.lastreportts + 1_000_000_000
        println("#of searches since last report: $(me.resultcount)")
        me.resultcount = 0
        me.lastreportts = time_ns()
    end
    startround(me, service)
    yield()
end

function onmessage(me::Coordinator, message::RecipientMoved, service) # TODO a default implementation like this
    if !isnothing(me.root) && box(me.root) === box(message.oldaddress)
        me.root = message.newaddress
    else
        @info "unhandled, forwarding: $message" 
    end
    send(service, me, me.root, message.originalmessage)
end

function onmessage(me::Coordinator, message::Stop, service)
    me.runmode = STOP
end

function onmessage(me::Coordinator, message::RunFast, service)
    oldmode = me.runmode
    me.runmode = FAST
    oldmode == STOP && startround(me, service, 80)
end

function onmessage(me::Coordinator, message::RunSlow, service)
    oldmode = me.runmode
    me.runmode = SLOW
    oldmode == STOP && startround(me, service)
end

function onmessage(me::Coordinator, message::RunFull, service)
    oldmode = me.runmode
    me.runmode = FULLSPEED
    oldmode == STOP && startround(me, service, 1000)
end

function onmessage(me::Coordinator, message::Step, service)
    oldmode = me.runmode
    me.runmode = STEP
    oldmode == STOP && startround(me, service)
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
    left.core.pos = nearpos(me.core.pos)
    right.core.pos = nearpos(me.core.pos)
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

function onmessage(me::TreeNode, message::RecipientMoved, service) # TODO a default implementation like this
    oldbox = box(message.oldaddress)
    if !isnothing(me.left) && box(me.left) === oldbox
        me.left = message.newaddress
    elseif !isnothing(me.right) && box(me.right) === oldbox
        me.right = message.newaddress
    elseif !isnothing(me.sibling) && box(me.sibling) == oldbox
        me.sibling = message.newaddress
    end
    send(service, me, message.newaddress, message.originalmessage)
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
    if SIBLINGINFO_FREQ > 0 && !isnothing(me.sibling) && rand(UInt8) < SIBLINGINFO_FREQ
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
