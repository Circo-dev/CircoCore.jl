# SPDX-License-Identifier: LGPL-3.0-only

module ClusterFullTest

const LIST_LENGTH = 3_000
const MIGRATE_BATCH_SIZE = 0
const BATCHES = 10000000
const RUNS_IN_BACTH = 4

using CircoCore, Dates, Random
import CircoCore.onmessage
import CircoCore.onschedule

mutable struct Coordinator <: AbstractActor
    itemcount::UInt64
    clusternodes::Array{NodeInfo}
    batchidx::UInt
    runidx::UInt
    listitems::Array{Addr} # Local copy for fast migrate commanding
    reducestarted::DateTime
    list::Addr
    core::CoreState
    Coordinator() = new(0, [], 0, 0, [])
end

mutable struct LinkedList <: AbstractActor
    head::Addr
    length::UInt64
    core::CoreState
    LinkedList(head) = new(head)
end

mutable struct ListItem{TData} <: AbstractActor
    data::TData
    prev::Addr
    next::Addr
    core::CoreState
    ListItem(data) = new{typeof(data)}(data)
end

struct Append <: Request
    replyto::Addr
    item::Addr
    token::Token
    Append(replyto, item) = new(replyto, item, Token())
end

struct Appended <: Response
    token::Token
end

struct SetNext #<: Request
    value::Addr
    token::Token
    SetNext(value::Addr) = new(value, Token())
end

struct SetPrev #<: Request
    value::Addr
    token::Token
    SetPrev(value::Addr) = new(value, Token())
end

struct Setted <: Response
    token::Token
end

struct Reduce{TOperation, TResult}
    op::TOperation
    result::TResult
end

struct Ack end

Sum() = Reduce(+, 0)
Mul() = Reduce(*, 1)

struct MigrateCommand
    to::PostCode
end

function onmessage(me::LinkedList, message::Append, service)
    send(service, me, message.item, SetNext(me.head))
    send(service, me, me.head, SetPrev(message.item))
    send(service, me, message.replyto, Appended(token(message)))
    me.head = message.item
    me.length += 1
end

function onschedule(me::Coordinator, service)
    cluster = getname(service, "cluster")
    println("Coordinator scheduled on cluster: $cluster Building list of $LIST_LENGTH actors")
    list = LinkedList(addr(me))
    me.itemcount = 0
    spawn(service, list)
    me.list = addr(list)
    appenditem(me, service)    
end

function appenditem(me::Coordinator, service)
    item = ListItem(1.00001)
    push!(me.listitems, spawn(service, item))
    send(service, me, me.list, Append(addr(me), addr(item)))
end

function onmessage(me::Coordinator, message::Appended, service)
    me.itemcount += 1
    if me.itemcount < LIST_LENGTH
        appenditem(me, service)
    else
        println("List items added. Waiting for cluster join")
        send(service, me, getname(service, "cluster"), Subscribe{PeerListUpdated}(addr(me)))
    end
end

function onmessage(me::Coordinator, message::PeerListUpdated, service)
    me.clusternodes = message.peers
    if length(message.peers) > 1 && me.batchidx == 0
        startbatch(me, service)    
    end
end

onmessage(me::ListItem, message::SetNext, service) = me.next = message.value

onmessage(me::ListItem, message::SetPrev, service) = me.prev = message.value

onmessage(me::LinkedList, message::Reduce, service) = send(service, me, me.head, message)

function onmessage(me::LinkedList, message::RecipientMoved, service) # TODO a default implementation like this
    if me.head == message.oldaddress
        me.head = message.newaddress
        send(service, me, me.head, message.originalmessage)
    else
        error("Unhandled: ", message)
    end
end

function onmessage(me::ListItem, message::Reduce, service)
    newresult = message.op(message.result, me.data)
    send(service, me, me.next, Reduce(message.op, newresult))
    if isdefined(me, :prev)
        #send(service, me, me.prev, Ack())
    end
end    

onmessage(me::ListItem, message::Ack, service) = nothing

function onmessage(me::ListItem, message::RecipientMoved, service)
    if me.next == message.oldaddress
        me.next = message.newaddress
        send(service, me, me.next, message.originalmessage)
    elseif me.prev == message.oldaddress
        me.prev = message.newaddress
        send(service, me, me.prev, message.originalmessage)
    else        
        error("Unhandled: ", message)
    end
end

function batchmigration(me::Coordinator, service)
    if length(me.clusternodes) < 2
        println("Running on a single-node cluster, no migration.")
    end
    batch = randsubseq(me.listitems, MIGRATE_BATCH_SIZE / LIST_LENGTH)
    for actor in batch
        send(service, me, actor, MigrateCommand(postcode(rand(me.clusternodes).addr)))
    end
end

function startbatch(me::Coordinator, service)
    if me.batchidx > BATCHES
        println("Test finished.")
        die(service, me)
        return nothing
    end
    me.batchidx += 1
    batchmigration(me, service)
    me.runidx = 1
    sumlist(me, service)
    return nothing
end

function sumlist(me::Coordinator, service)
    me.reducestarted = now()
    send(service, me, me.list, Sum())
end

function mullist(me::Coordinator, service)
    me.reducestarted = now()
    send(service, me, me.list, Mul())
end

function onmessage(me::Coordinator, message::Reduce, service)
    reducetime = now() - me.reducestarted
    if rand() < 0.01
        print("Run #$(me.runidx): Got reduce result $(message.result) in $reducetime.")
    end
    #sleep(0.001)
    me.runidx += 1
    if me.runidx >= RUNS_IN_BACTH + 1
        #println(" Asking $MIGRATE_BATCH_SIZE actors to migrate.")
        startbatch(me, service)
    else
        #println()
        sumlist(me, service)
    end
end

function onmessage(me::ListItem, message::MigrateCommand, service)
    migrate(service, me, message.to)
end

end
zygote() = ClusterFullTest.Coordinator()
