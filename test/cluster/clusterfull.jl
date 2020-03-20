# SPDX-License-Identifier: LGPL-3.0-only
module ClusterFullTest

const LIST_LENGTH = 4000000

using CircoCore, Dates
import CircoCore.onmessage
import CircoCore.onschedule

mutable struct Coordinator <: AbstractActor
    itemcount::UInt64
    reducestarted::DateTime
    list::Address
    address::Address
    Coordinator() = new(0)
end

mutable struct LinkedList <: AbstractActor
    head::Address
    length::UInt64
    address::Address
    LinkedList(head) = new(head)
end

mutable struct ListItem{TData} <: AbstractActor
    data::TData
    next::Address
    address::Address
    ListItem(data) = new{typeof(data)}(data)
end

struct Append <: Request
    replyto::Address
    item::Address
    token::Token
    Append(replyto, item) = new(replyto, item, Token())
end

struct Appended <: Response
    token::Token
end

struct SetNext #<: Request
    value::Address
    token::Token
    SetNext(value::Address) = new(value, Token())
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

function onmessage(me::LinkedList, message::Append, service)
    send(service, me, message.item, SetNext(me.head))
    send(service, me, message.replyto, Appended(token(message)))
    me.head = message.item
    me.length += 1
end

function onschedule(me::Coordinator, service)
    cluster = getname(service, "cluster")
    println("Coordinator scheduled on cluster: $cluster Building list of $LIST_LENGTH actors")
    list = LinkedList(address(me))
    me.itemcount = 0
    spawn(service, list)
    me.list = address(list)
    appenditem(me, service)
end

function appenditem(me::Coordinator, service)
    item = ListItem(1.00001)
    spawn(service, item)
    send(service, me, me.list, Append(address(me), address(item)))
end

function onmessage(me::Coordinator, message::Appended, service)
    me.itemcount += 1
    if me.itemcount < LIST_LENGTH
        appenditem(me, service)
    else
        println("List items added. Summing")
        sumlist(me, service)
    end
end

function onmessage(me::ListItem, message::SetNext, service)
    me.next = message.value
end

function onmessage(me::LinkedList, message::Reduce, service)
    send(service, me, me.head, message)
end

function onmessage(me::ListItem, message::Reduce, service)
    newresult = message.op(message.result, me.data)
    send(service, me, me.next, Reduce(message.op, newresult))
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
    println("Got reduce result $(message.result) in $reducetime")
    rand() < 0.5 ? mullist(me, service) : sumlist(me, service)
end

end
zygote() = ClusterFullTest.Coordinator()
