# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore
import Base.show, Base.string

ActorId = UInt64
abstract type AbstractActor end

abstract type AbstractAddr end
postcode(address::AbstractAddr) = address.postcode
postcode(actor::AbstractActor) = postcode(address(actor))
box(address::AbstractAddr) = address.box

PostCode = String

struct Addr <: AbstractAddr
    postcode::PostCode
    box::ActorId
end
NullAddress = Addr("", UInt64(0))
Addr() = NullAddress
Addr(box::ActorId) = Addr("", box)
Addr(readable_address::String) = begin
    parts = split(readable_address, "/") # Handles only dns.or.ip:port[/actorid]
    actorid = length(parts) == 2 ? parse(ActorId, parts[2], base=16) : 0
    return Addr(parts[1], actorid)
end
string(a::Addr) = "$(a.postcode)/$(string(a.box, base=16))"

isbaseaddress(addr::Addr) = box(addr) == 0
function Base.show(io::IO, a::Addr)
    print(io, string(a))
end
redirect(addr::Addr, topostcode::PostCode) = Addr(topostcode, box(addr))

addr(a::AbstractActor) = a.addr::Addr
address(a::AbstractActor) = a.addr::Addr
id(a::AbstractActor) = address(a).box::ActorId

abstract type AbstractMsg end
struct Msg{BodyType} <: AbstractMsg
    sender::Addr
    target::Addr
    body::BodyType
end
Msg{T}(sender::AbstractActor, target::Addr, body::T) where {T} = Msg{T}(Addr(sender), target, body)
Msg(sender::AbstractActor, target::Addr, body::T) where {T} = Msg{T}(Addr(sender), target, body)
Msg{Nothing}(sender, target) = Msg{Nothing}(sender, target, nothing)
Msg{Nothing}(target) = Msg{Nothing}(NullAddress, target)
Msg{Nothing}() = Msg{Nothing}(NullAddress, NullAddress)

sender(m::AbstractMsg) = m.sender::Addr
target(m::AbstractMsg) = m.target::Addr
body(m::AbstractMsg) = m.body
redirect(m::AbstractMsg, to::Addr) = (typeof(m))(target(m), to, body(m))

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

include("postoffice.jl")
include("registry.jl")
include("token.jl")
include("service.jl")
include("plugins.jl")
include("migration.jl")
include("interregion/websocket.jl")
include("scheduler.jl")
include("event.jl")
include("cluster/cluster.jl")
include("cli/circonode.jl")

export AbstractActor, ActorId, id, ActorService, ActorScheduler,
    deliver!, schedule!, shutdown!,

    # Messaging
    PostCode, postcode, PostOffice, Addr, addr, Msg, redirect,
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

