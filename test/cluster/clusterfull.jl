# SPDX-License-Identifier: LGPL-3.0-only
module ClusterFullTest

const LIST_LENGTH = 4_000_000
const MIGRATE_BATCH_SIZE = 10
const BATCHES = 100
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
    addr::Addr
    Coordinator() = new(0, [], 0, 0, [])
end

mutable struct LinkedList <: AbstractActor
    head::Addr
    length::UInt64
    addr::Addr
    LinkedList(head) = new(head)
end

mutable struct ListItem{TData} <: AbstractActor
    data::TData
    next::Addr
    addr::Addr
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

struct Setted <: Response
    token::Token
end

struct Reduce{TOperation, TResult}
    op::TOperation
    result::TResult
end

Sum() = Reduce(+, 0)
Mul() = Reduce(*, 1)

struct MigrateCommand
    to::PostCode
end

function onmessage(me::LinkedList, message::Append, service)
    send(service, me, message.item, SetNext(me.head))
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
        send(service, me, getname(service, "cluster"), Subscribe{Joined}(addr(me)))
    end
end

function onmessage(me::Coordinator, message::Joined, service)
    me.clusternodes = message.peers
    startbatch(me, service)    
end

function onmessage(me::ListItem, message::SetNext, service)
    me.next = message.value
end

function onmessage(me::LinkedList, message::Reduce, service)
    send(service, me, me.head, message)
end

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
end    

function onmessage(me::ListItem, message::RecipientMoved, service)
    if me.next == message.oldaddress
        me.next = message.newaddress
        send(service, me, me.next, message.originalmessage)
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
        die()
        return nothing
    end
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
    print("Run #$(me.runidx): Got reduce result $(message.result) in $reducetime.")
    me.runidx += 1
    if me.runidx >= RUNS_IN_BACTH + 1
        println(" Asking $MIGRATE_BATCH_SIZE actors to migrate.")
        startbatch(me, service)
    else
        println()
        sumlist(me, service)
    end
end

function onmessage(me::ListItem, message::MigrateCommand, service)
    migrate(service, me, message.to)
end

end
zygote() = ClusterFullTest.Coordinator()
