# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore

export AbstractActor, CoreState, ActorId, ActorService,
    AbstractActorScheduler, ActorScheduler, deliver!, schedule!, shutdown!,

    #Plugins
    getactorbyid, unschedule!,

    # Messaging
    PostCode, postcode, PostOffice, postoffice, Addr, addr, box, port, AbstractMsg, Msg,
    redirect, body, target, sender,

    Token, TokenId, Tokenized, token, Request, Response, Timeout,

    # Actor API
    send, spawn, die, migrate, getname, registername, NameQuery, NameResponse,

    # Actor lifecycle callbacks
    onschedule, onmessage, onmigrate,

    # Events
    Event, EventDispatcher, Subscribe, fire,

    # Space
    Pos, pos, nullpos, Infoton,

    # Multithreading

    # Monitoring
    JS, registermsg

using Plugins, StaticArrays

import Base: show, string
import Plugins: setup!, shutdown!, symbol

"""
    ActorId

A cluster-unique id that is randomly generated when the actor is spawned (first scheduled).

`ActorId` is an alias to `UInt64` at the time, so it may pop up in error messages as such.
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
PostCode = String # TODO (perf): destructured storage
port(postcode::PostCode) = parse(UInt32, split(postcode, ":")[end])
network_host(postcode::PostCode) = SubString(postcode, 1, findfirst(":", postcode)[1])

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
    box(a::AbstractActor)

Return the 'P.O. box' of the spawned actor.

Call this on a spawned actor to get its id (aka box). Throws `UndefRefError` if the actor is not spawned.
"""
box(a::AbstractActor) = box(addr(a))::ActorId

"""
    pos(a::AbstractActor)::Pos

return the current position of the actor.

Call this on a spawned actor to get its position. Throws `UndefRefError` if the actor is not spawned.
"""
pos(a::AbstractActor) = a.core.pos

"""
    Pos(x::Real, y::Real, z::Real)
    Pos(coords)

A point in the 3D "actor space".

You can access the coords by pos.x, pos.y, pos.z.

Pos is implemented using an SVector{3, Float32}.
"""
struct Pos <: AbstractVector{Float32}
    coords::SVector{3, Float32}
    Pos(x, y, z) = new(SVector{3, Float32}(x, y, z))
    Pos(coords) = new(coords)
end

dist(a::Pos, b::Pos) = sqrt((a.coords[1]-b.coords[1])^2 + (a.coords[2]-b.coords[2])^2 + (a.coords[3]-b.coords[3])^2)
Base.:*(a::Pos, x::Real) = Pos(a.coords * x)
Base.:/(a::Pos, x::Real) = Pos(a.coords / x)
Base.:+(a::Pos, b::Pos) = Pos(a.coords + b.coords)
Base.:-(a::Pos, b::Pos) = Pos(a.coords - b.coords)
Base.getindex(pos::Pos, i::Int) = getindex(pos.coords, i)
Base.getproperty(pos::Pos, symbol::Symbol) = (symbol == :x) ? getfield(pos, :coords)[1] :
                                        (symbol == :y) ? getfield(pos, :coords)[2] :
                                        (symbol == :z) ? getfield(pos, :coords)[3] :
                                        getfield(pos, symbol)
Base.iterate(pos::Pos) = iterate(pos.coords)
Base.iterate(pos::Pos, state) = iterate(pos.coords, state)
Base.length(pos::Pos) = length(pos.coords)
Base.size(pos::Pos) = size(pos.coords)

Base.show(io::IO, ::MIME"text/plain", pos::Pos) = begin
    print(io, "Pos($(pos[1]), $(pos[2]), $(pos[3]))")
end


mutable struct CoreState
    addr::Addr
    pos::Pos
end
nullpos = Pos(0, 0, 0)



"""
    Infoton(sourcepos::Pos, energy::Real = 1)

Create an Infoton that carries `abs(energy)` amount of energy and has the sign `sign(energy)`.

The infoton mediates the force that awakens between communicating actors. When arriving at its
target actor, the infoton pulls/pushes the actor toward/away from its source, depending on its
sign (positive pulls).

The exact details of how the Infoton should act at its target is actively researched.
Please check or overload [`apply_infoton`](@ref).
"""
struct Infoton
    sourcepos::Pos
    energy::Float32
    Infoton(sourcepos::Pos, energy::Real = 1) = new(sourcepos, Float32(energy))
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

"""
    CircoCore.onschedule(me::AbstractActor, service)

Lifecycle callback that marks the first scheduling of the actor, called during spawning, before any `onmessage`.

Note: Do not forget to import it or use its qualified name to allow overloading!

# Examples

```julia
import CircoCore.onschedule

funtion onschedule(me::MyActor, service)
    registername(service, "MyActor", me) # Register this actor in the local name service
end
```
"""
function onschedule(me::AbstractActor, service) end

"""
    onmessage(me::AbstractActor, message, service)

Handle a message arriving at an actor.

Only the payload of the message is delivered, there is currently no way to access the infoton or the sender address.
If you need a reply, include the sender address in the request.

Note: Do not forget to import it or use its qualified name to allow overloading!

# Examples

```julia
import CircoCore.onmessage

struct TestRequest
    replyto::Addr
end

struct TestResponse end

function onmessage(me::MyActor, message::TestRequest, service)
    send(service, me, message.replyto, TestResponse())
end
```
"""
function onmessage(me::AbstractActor, message, service) end

"""
    onmigrate(me::AbstractActor, service)

Lifecycle callback that marks a successful migration.

It is called on the target scheduler, before any messages will be delivered.

Note: Do not forget to import it or use its qualified name to allow overloading!

# Examples
```julia
import CircoCore.onmigrate

function onmigrate(me::MyActor, service)
    println("Successfully migrated, registering a name on the new scheduler")
    registername(service, "MyActor", me)
end
```
"""
function onmigrate(me::AbstractActor, service) end

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
include("space.jl")
include("scheduler.jl")
include("event.jl")

end
