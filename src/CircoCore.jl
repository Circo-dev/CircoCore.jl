# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore
import Base.show

ActorId = UInt64
abstract type AbstractActor end

abstract type AbstractAddress end
postcode(address::AbstractAddress) = address.postcode
postcode(actor::AbstractActor) = postcode(address(actor))
box(address::AbstractAddress) = address.box

PostCode = String

struct Address <: AbstractAddress
    postcode::PostCode
    box::ActorId
end
NullAddress = Address("", UInt64(0))
Address() = NullAddress
Address(box::ActorId) = Address("", box)
Address(readable_address::String) = begin
    parts = split(readable_address, "/") # Handles only tcp://dns.or.ip:port[/actorid]
    actorid = length(parts) == 4 ? parse(ActorId, parts[4], base=16) : 0
    return Address(join(parts[1:3], "/"), actorid)
end

isbaseaddress(addr::Address) = box(addr) == 0
function Base.show(io::IO, a::Address)
    print(io, "$(a.postcode)/$(string(a.box, base=16))")
end
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

abstract type Request end
RequestId = UInt64

struct RequestMessage{BodyType} <: AbstractMessage
    sender::Address
    target::Address
    body::BodyType
    id::RequestId
end
RequestMessage{T}(sender::AbstractActor, target::Address, body::T) where {T} = RequestMessage{T}(Address(sender), target, body, rand(RequestId))
RequestMessage(sender::AbstractActor, target::Address, body::T) where {T} = RequestMessage{T}(Address(sender), target, body)
struct ResponseMessage{BodyType} <: AbstractMessage
    sender::Address
    target::Address
    body::BodyType
    requestid::RequestId
end 

sender(m::AbstractMessage) = m.sender::Address
target(m::AbstractMessage) = m.target::Address
body(m::AbstractMessage) = m.body
redirect(m::AbstractMessage, to::Address) = (typeof(m))(target(m), to, body(m))

# Actor lifecycle callbacks
function onschedule(actor::AbstractActor, service) end
function onmessage(actor::AbstractActor, message, service) end
function onmigrate(actor::AbstractActor, service) end

# scheduler
abstract type AbstractActorScheduler end
postoffice(scheduler::AbstractActorScheduler) = scheduler.postoffice
address(scheduler::AbstractActorScheduler) = address(postoffice(scheduler))
postcode(scheduler::AbstractActorScheduler) = postcode(postoffice(scheduler))
function handle_special!(scheduler::AbstractActorScheduler, message) end
struct ActorService{TScheduler}
    scheduler::TScheduler
end

include("postoffice.jl")
include("migration.jl")
include("nameservice.jl")
include("scheduler.jl")
include("cluster/cluster.jl")
include("cli/circonode.jl")

export AbstractActor, ActorId, id, ActorService, ActorScheduler,
    deliver!, schedule!, shutdown!,

    # Messaging
    PostCode, postcode, PostOffice, Address, address, Message, redirect,
    RecipientMoved,
    Request,

    # Actor API
    send, spawn, die, migrate,

    # Actor lifecycle callbacks
    onschedule, onmessage, onmigrate,

    # Cluster management
    ClusterActor, NodeInfo,

    cli
end

