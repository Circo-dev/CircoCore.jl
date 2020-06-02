# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore
using Vec, Plugins

import Base.show, Base.string
import Plugins.setup!, Plugins.shutdown!, Plugins.symbol

"""
    ActorId

A cluster-unique id that is randomly generated when the actor is spawned (first scheduled).

`ActorId` is an alias to `UInt64` at the time, so it may pop up in error messags as such.
"""
ActorId = UInt64

"""
    abstract type AbstractActor    

Supertype of all actors.

Subtypes must be mutable and must provide a field `core::CoreState`
that can remain undefined after creation.

# Examples

```julia
mutable struct DataHolder{TValue} <: AbstractActor
    value::TValue
    core::CoreState
    DataHolder(value) = new{typeof(value)}(value)
end
```
"""
abstract type AbstractActor end

abstract type AbstractAddr end
postcode(address::AbstractAddr) = address.postcode
postcode(actor::AbstractActor) = postcode(addr(actor))
box(address::AbstractAddr) = address.box

"""
    PostCode

A string that identifies a scheduler.

# Examples

"192.168.1.11:24721"

"""
PostCode = String
port(postcode::PostCode) = parse(UInt32, split(postcode, ":")[end])

"""
    Addr(postcode::PostCode, box::ActorId)
    Addr(readable_address::String)

The full address of an actor.

If the referenced actor migrates to a different scheduler, messages sent to the
old address will bounce back as [`RecipientMoved`](@ref) and the Addr
must be updated manually.

# Examples

Addr("192.168.1.11:24721", 0xbc6ac81fc7e4ea2)

Addr("192.168.1.11:24721/bc6ac81fc7e4ea2")

"""
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

"""
    box(a::Addr)::ActorId

Return the box of the address, that is the id of the actor.

When the actor migrates, its box remains the same, only the PostCode of the address changes.
"""
box(a::Addr) = a.box

"""
    isbaseaddress(addr::Addr)::Bool

Return true if `addr` is a base address, meaning it references a scheduler directly.
"""
isbaseaddress(addr::Addr) = box(addr) == 0
function Base.show(io::IO, a::Addr)
    print(io, string(a))
end

"""
    redirect(addr::Addr, topostcode::PostCode):Addr

Create a new Addr by replacing the postcode of the given one.
"""
redirect(addr::Addr, topostcode::PostCode) = Addr(topostcode, box(addr))

"""
    addr(a::AbstractActor)

Return the address of the actor.

Call this on a spawned actor to get its address. Throws `UndefRefError` if the actor is not spawned.
"""
addr(a::AbstractActor) = a.core.addr::Addr

"""
    id(a::AbstractActor)

Return the id of the actor.

Call this on a spawned actor to get its id (aka box). Throws `UndefRefError` if the actor is not spawned.
"""
id(a::AbstractActor) = addr(a).box::ActorId

"""
    pos(a::AbstractActor)::Pos

return the current position of the actor.

Call this on a spawned actor to get its position. Throws `UndefRefError` if the actor is not spawned.
"""
pos(a::AbstractActor) = a.core.pos

"""
    Pos

A point in the 3D "actor space".

Pos is currently a VecE3{Float32}. See [Vec.jl](https://github.com/sisl/Vec.jl)
"""
Pos=VecE3{Float32}
mutable struct CoreState
    addr::Addr
    pos::Pos
end
nullpos = Pos(0, 0, 0)

"""
    Infoton(sourcepos::Pos, energy::Number)

Create an Infoton that carries `abs(energy)` amount of energy and either 
"""
struct Infoton
    sourcepos::Pos
    energy::Float32
    Infoton(sourcepos::Pos, energy::Number) = new(sourcepos, Float64(energy))
    Infoton(sourcepos::Pos) = new(sourcepos, 1)
end

abstract type AbstractMsg end
struct Msg{BodyType} <: AbstractMsg
    sender::Addr
    target::Addr
    body::BodyType
    infoton::Infoton
end
Msg{T}(sender::AbstractActor, target::Addr, body::T) where {T} = Msg{T}(addr(sender), target, body, Infoton(sender.core.pos))
Msg(sender::AbstractActor, target::Addr, body::T, energy) where {T} = Msg{T}(addr(sender), target, body, Infoton(sender.core.pos, energy))
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
addr(scheduler::AbstractActorScheduler) = addr(postoffice(scheduler))
postcode(scheduler::AbstractActorScheduler) = postcode(postoffice(scheduler))
function handle_special!(scheduler::AbstractActorScheduler, message) end

include("postoffice.jl")
include("token.jl")
include("registry.jl")
include("service.jl")
#include("plugins.jl")
include("space.jl")
include("interregion/websocket.jl")
include("monitor.jl")
include("scheduler.jl")
include("event.jl")
include("cluster/cluster.jl")
include("migration.jl")
include("cli/circonode.jl")

export AbstractActor, CoreState, ActorId, id, Pos, pos, ActorService,
    ActorScheduler, deliver!, schedule!, shutdown!,

    #Plugins
    default_plugins,
    MonitorService, monitorextra,

    # Messaging
    PostCode, postcode, PostOffice, Addr, addr, box, Msg, redirect,
    RecipientMoved,

    Token, TokenId, Tokenized, token, Request, Response, Timeout,

    # Actor API
    send, spawn, die, migrate, getname, registername,

    # Actor lifecycle callbacks
    onschedule, onmessage, onmigrate,

    # Events
    Event, EventDispatcher, Subscribe, fire,

    # Space
    Infoton,

    # Cluster management
    ClusterActor, NodeInfo, Joined, PeerListUpdated,
    migrate_to_nearest, MigrationAlternatives,

    cli
end

