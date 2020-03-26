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
    parts = split(readable_address, "/") # Handles only dns.or.ip:port[/actorid]
    actorid = length(parts) == 2 ? parse(ActorId, parts[2], base=16) : 0
    return Address(parts[1], actorid)
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

sender(m::AbstractMessage) = m.sender::Address
target(m::AbstractMessage) = m.target::Address
body(m::AbstractMessage) = m.body
redirect(m::AbstractMessage, to::Address) = (typeof(m))(target(m), to, body(m))

# Actor lifecycle callbacks
function onschedule(actor::AbstractActor, service) end
function onmessage(actor::AbstractActor, message, service) end
function onmigrate(actor::AbstractActor, service) end

# scheduler
abstract type SchedulerPlugin end
localroutes(plugin::SchedulerPlugin) = nothing
symbol(plugin::SchedulerPlugin) = :nothing

abstract type AbstractActorScheduler end
postoffice(scheduler::AbstractActorScheduler) = scheduler.postoffice
address(scheduler::AbstractActorScheduler) = address(postoffice(scheduler))
postcode(scheduler::AbstractActorScheduler) = postcode(postoffice(scheduler))
function handle_special!(scheduler::AbstractActorScheduler, message) end

include("postoffice.jl")
include("migration.jl")
include("registry.jl")
include("token.jl")
include("service.jl")
include("plugins.jl")
include("scheduler.jl")
include("event.jl")
include("cluster/cluster.jl")
include("cli/circonode.jl")

export AbstractActor, ActorId, id, ActorService, ActorScheduler,
    deliver!, schedule!, shutdown!,

    # Messaging
    PostCode, postcode, PostOffice, Address, address, Message, redirect,
    RecipientMoved,

    Token, TokenId, Tokenized, token, Request, Response, Timeout,

    # Actor API
    send, spawn, die, migrate, getname, registername,

    # Actor lifecycle callbacks
    onschedule, onmessage, onmigrate,

    # Events
    Event, EventDispatcher, Subscribe,

    # Cluster management
    ClusterActor, NodeInfo, Joined,

    cli
end

