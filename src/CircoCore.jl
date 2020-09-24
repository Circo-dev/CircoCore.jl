# SPDX-License-Identifier: LGPL-3.0-only
module CircoCore

export CircoContext, ActorScheduler,

    AbstractActor, CoreState, ActorId, ActorService, deliver!, schedule!,
    emptycore,

    #Plugins reexport
    Plugin, setup!, shutdown!, symbol,

    #Plugins
    plugin, getactorbyid, unschedule!,

    ActivityService,

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

    # Monitoring
    JS, registermsg

using  StaticArrays
import Base: show, string
import Plugins

const Plugin = Plugins.Plugin
const shutdown! = Plugins.shutdown!
const setup! = Plugins.setup!
const symbol = Plugins.symbol
const hooks = Plugins.hooks

include("hooks.jl")

abstract type AbstractContext end

"""
    ActorId

A cluster-unique id that is randomly generated when the actor is spawned (first scheduled).

`ActorId` is an alias to `UInt64` at the time, so it may pop up in error messages as such.
"""
ActorId = UInt64

"""
    abstract type AbstractActor{TCoreState}

Supertype of all actors.

Subtypes must be mutable and must provide a field `core::TCoreState`
that can remain undefined after creation.

# Examples

```julia
mutable struct DataHolder{TValue, TCore} <: AbstractActor{TCore}
    value::TValue
    core::TCore
end
```
"""
abstract type AbstractActor{TCoreState} end

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
invalidpostcode = "0.0.0.0:0"
postcode(::Any) = invalidpostcode

"""
    Addr(postcode::PostCode, box::ActorId)
    Addr(readable_address::String)
    Addr()

The full address of an actor.

When created without arguments, it will be the null address. See [`isnulladdr()`](@ref)

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
nulladdr = Addr("", UInt64(0))
Addr() = nulladdr
Addr(box::ActorId) = Addr("", box)
Addr(readable_address::String) = begin
    parts = split(readable_address, "/") # Handles only dns.or.ip:port[/actorid]
    actorid = length(parts) == 2 ? parse(ActorId, parts[2], base=16) : 0
    return Addr(parts[1], actorid)
end
string(a::Addr) = "$(a.postcode)/$(string(a.box, base=16))"

"""
    isnulladdr(a::Addr)

Check if the given address is a null address, meaning that it points to "nowhere", messages
sent to it will be dropped.
"""
isnulladdr(a::Addr) = a == nulladdr

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
    @info "Successfully migrated, registering a name on the new scheduler"
    registername(service, "MyActor", me)
end
```
"""
function onmigrate(me::AbstractActor, service) end

# scheduler
abstract type AbstractActorScheduler{TCoreState} end
addr(scheduler::AbstractActorScheduler) = Addr(postcode(scheduler), 0)
function handle_special!(scheduler::AbstractActorScheduler, message) end

include("msg.js")
include("onmessage.jl")
include("postoffice.jl")
include("token.jl")
include("registry.jl")
include("service.jl")
include("sparse_activity.jl")
include("space.jl")
include("positioning.jl")
include("profiles.jl")
include("context.jl")
include("scheduler.jl")
include("event.jl")

end
