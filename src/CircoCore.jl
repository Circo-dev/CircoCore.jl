# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore
using Vec

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

addr(a::AbstractActor) = a.core.addr::Addr
address(a::AbstractActor) = a.core.addr::Addr
id(a::AbstractActor) = address(a).box::ActorId
pos(a::AbstractActor) = a.core.pos

Pos=VecE3
mutable struct CoreState
    addr::Addr
    pos::Pos
end
nullpos = Pos(0, 0, 0)

struct Infoton
    sourcepos::Pos
    #energy::Float16
end

abstract type AbstractMsg end
struct Msg{BodyType} <: AbstractMsg
    sender::Addr
    target::Addr
    body::BodyType
    infoton::Infoton
end
Msg{T}(sender::AbstractActor, target::Addr, body::T) where {T} = Msg{T}(addr(sender), target, body, Infoton(sender.core.pos))
Msg(sender::AbstractActor, target::Addr, body::T) where {T} = Msg{T}(addr(sender), target, body, Infoton(sender.core.pos))
Msg(target::Addr, body::T) where {T} = Msg{T}(Addr(), target, body, Infoton(nullpos))
Msg{Nothing}(sender, target) = Msg{Nothing}(sender, target, nothing)
Msg{Nothing}(target) = Msg{Nothing}(NullAddress, target, nothing, Infoton(nullpos))
Msg{Nothing}() = Msg{Nothing}(NullAddress, NullAddress, nothing, Infoton(nullpos))

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
include("token.jl")
include("registry.jl")
include("service.jl")
include("plugins.jl")
include("migration.jl")
include("space.jl")
include("interregion/websocket.jl")
include("monitor.jl")
include("scheduler.jl")
include("event.jl")
include("cluster/cluster.jl")
include("cli/circonode.jl")

export AbstractActor, CoreState, ActorId, id, Pos, pos, ActorService,
    ActorScheduler, deliver!, schedule!, shutdown!,

    #Plugins
    default_plugins,
    MonitorService,

    # Messaging
    PostCode, postcode, PostOffice, Addr, addr, Msg, redirect,
    RecipientMoved,

    Token, TokenId, Tokenized, token, Request, Response, Timeout,

    # Actor API
    send, spawn, die, migrate, getname, registername,

    # Actor lifecycle callbacks
    onschedule, onmessage, onmigrate,

    # Events
    Event, EventDispatcher, Subscribe, fire,

    # Cluster management
    ClusterActor, NodeInfo, Joined, PeerListUpdated,

    cli
end

