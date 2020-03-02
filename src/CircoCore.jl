# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore

using DataStructures

ActorId = UInt64
abstract type AbstractActor end

abstract type AbstractAddress end
postcode(address::AbstractAddress) = address.postcode
box(address::AbstractAddress) = address.box

PostCode = String

struct Address <: AbstractAddress
    postcode::PostCode
    box::ActorId
end
NullAddress = Address("", UInt64(0))
Address() = NullAddress
Address(box::ActorId) = Address("", box)
redirect(address::Address, topostcode::PostCode) = Address(topostcode, box(address)) 

address(a::AbstractActor) = a.address::Address
id(a::AbstractActor) = address(a).box::ActorId

abstract type AbstractMessage end
struct Message{BodyType} <: AbstractMessage
    sender::Address
    target::Address
    body::BodyType
end
Message{T}(sender::AbstractActor, target::Address, body::T) where {T} = Message{T}(Address(sender), target, body)
Message(sender::AbstractActor, target::Address, body::T) where {T} = Message{T}(Address(sender), target, body)
Message{Nothing}(sender, target) = Message{Nothing}(sender, target, nothing)
Message{Nothing}(target) = Message{Nothing}(NullAddress, target)
Message{Nothing}() = Message{Nothing}(NullAddress, NullAddress)

sender(m::AbstractMessage) = m.sender::Address
target(m::AbstractMessage) = m.target::Address
body(m::AbstractMessage) = m.body
redirect(m::AbstractMessage, to::Address) = (typeof(m))(target(m), to, body(m))

# Actor lifecycle callbacks
function onschedule(actor::AbstractActor, service) end
function onmessage(actor::AbstractActor, message, service) end
function onmigrate(actor::AbstractActor, service) end

include("postoffice.jl")
include("scheduler.jl")
include("cluster.jl")

export AbstractActor, ActorId, id, ActorService, ActorScheduler,
    deliver!, schedule!, shutdown!,

    # Messaging
    PostCode, postcode, PostOffice, Address, address, Message, redirect,
    RecipientMoved,

    # Actor API
    send, spawn, die, migrate,

    # Actor lifecycle callbacks
    onschedule, onmessage, onmigrate,

    # User space
    ClusterActor, SchedulerInfo
end
