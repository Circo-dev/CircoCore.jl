# SPDX-License-Identifier: LGPL-3.0-only
module ClusterFullTest

using CircoCore
import CircoCore.onmessage
import CircoCore.onschedule

mutable struct Coordinator <: AbstractActor
    list::Address
    address::Address
    Coordinator() = new()
end

mutable struct LinkedList <: AbstractActor
    head::Address()
    length::UInt64
    address::Address
    LinkedList() = new(0)
end

mutable struct ListItem <: AbstractActor
    next::Address()
    data::Address()
    address::Address
    ListItem() = new()
end

mutable struct Data <: AbstractActor
    value
    address::Address
    Data(val) = new(val)
end

struct Append <: Request
    replyto::Address
    item::ListItem
    token::Token
    Append(replyto, item) = new(replyto, item, Token())
end

struct Appended <: Response
    token::Token
end

struct SetCommand{TValue} <: Request
    name::String
    value::TValue
    token::Token
    Append{TValue}(name::String, value::TValue) = new(name, value, Token())
end

struct Setted <: Response
    token::Token
end

function onmessage(me::LinkedList, message::Append, service)
    send(service, me, message.item, SetCommand{Address}("next", me.head))
    send(service, me, message.replyto, Appended(token(message)))
    me.head = message.item
end

function onschedule(me::Coordinator, service)
    cluster = getname(service, "cluster")
    println("Coordinator scheduled on cluster: $cluster")
    list = LinkedList()
    spawn(service, list)
    send(service, me, address(list), Append("This is a message from $(address(me))"))
end

function onmessage(me::SampleActor, message::SampleMessage, service)
    println("Got SampleMessage: '$(message.message)'")
end

end

zygote() = ClusterFullTest.Coordinator()
