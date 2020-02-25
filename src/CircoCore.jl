# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore

using DataStructures

ActorId = UInt64
abstract type AbstractActor end

abstract type AbstractAddress end

PostCode = String

struct Address <: AbstractAddress
    postcode::PostCode
    box::ActorId
end

Address(box::ActorId) = Address("", box)
NullAddress = Address("", UInt64(0))

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

function onmessage(component, message, service) end

include("scheduler.jl")

export ActorId, id,
    AbstractActor,
    PostCode,
    Address,
    address,
    Message,
    onmessage,
    ActorService,
    ActorScheduler,
    deliver!,
    schedule!,
    send,
    spawn

end # module
