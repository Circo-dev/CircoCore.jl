# SPDX-License-Identifier: MPL-2.0
module CircoCore

export CircoContext, Scheduler, AbstractScheduler, run!, pause!,

    Actor, ActorId, schedule!,

    emptycore,

    # Lifecycle
    OnSpawn, OnDeath, OnBecome,

    #Plugins reexport
    Plugin, setup!, shutdown!, symbol,

    #Plugins
    plugin, getactorbyid, unschedule!,

    ActivityService,

    # Messaging
    PostCode, postcode, PostOffice, PostException, postoffice, Addr, addr, box, port, AbstractMsg, Msg,
    redirect, body, target, sender, nulladdr,

    Token, TokenId, Tokenized, token, Request, Response, Timeout, settimeout,

    # Actor API
    send, bulksend,
    spawn, become, die,
    migrate,
    getname, registername, NameQuery, NameResponse,

    # Events
    EventSource, Event, Subscribe, UnSubscribe, fire,

    # Signals
    SigTerm,

    # Space
    Pos, pos, nullpos, Infoton, Space
    
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
    abstract type Actor{TCoreState}

Supertype of all actors.

Subtypes must be mutable and must provide a field `core::TCoreState`
that can remain undefined after creation.

# Examples

```julia
mutable struct DataHolder{TValue, TCore} <: Actor{TCore}
    value::TValue
    core::TCore
end
```
"""
abstract type Actor{TCoreState} end
coretype(::Actor{TCore}) where TCore = TCore

abstract type AbstractAddr end
postcode(address::AbstractAddr) = address.postcode
postcode(actor::Actor) = postcode(addr(actor))
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

Base.convert(::Type{Addr}, x::Actor) = addr(x)

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
box(a)::ActorId = a.box

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
    addr(a::Actor)

Return the address of the actor.

Call this on a spawned actor to get its address. Throws `UndefRefError` if the actor is not spawned.
"""
addr(a::Actor) = a.core.addr::Addr

"""
    addr(entity)

Return the address of entity.

The default implementation returns the `addr` field, allowing you to use your own structs
with such fields as message targets.
"""
addr(a) = a.addr

"""
    box(a::Actor)

Return the 'P.O. box' of the spawned actor.

Call this on a spawned actor to get its id (aka box). Throws `UndefRefError` if the actor is not spawned.
"""
box(a::Actor) = box(addr(a))::ActorId

# Actor lifecycle messages

"""
    OnSpawn

Actor lifecycle message that marks the first scheduling of the actor,
sent during spawning, before any other message.

# Examples

```julia
CircoCore.onmessage(me::MyActor, ::OnSpawn, service) = begin
    registername(service, "MyActor", me) # Register this actor in the local name service
end
```
"""
struct OnSpawn end

"""
    onmessage(me::Actor, message, service)

Actor callback to handle a message arriving at an actor.

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
function onmessage(me::Actor, message, service) end

"""
    OnDeath

Actor lifecycle message to release resources when the actor dies (meaning unscheduled "permanently").

The actor is still scheduled when this message is delivered,
but no more messages will be delivered after this.
"""
struct OnDeath end

"""
    OnBecome(reincarnation::Actor)

Actor lifecycle message marking the `become()` action.

`reincarnation` points to the new incarnation of the actor.
`me` is scheduled at the delivery time of this message, `reincarnation` is not.

Exceptions thrown while handling `OnBecome`` will propagate to the initiating `become` call.
"""
struct OnBecome
    reincarnation::Actor
end

# scheduler
abstract type AbstractScheduler{TMsg, TCoreState} end
addr(scheduler::AbstractScheduler) = Addr(postcode(scheduler), 0)

abstract type Delivery <: Plugin end
Plugins.symbol(::Delivery) = :delivery

const PORT_RANGE = 24721:24999
abstract type PostOffice <: Plugin end
Plugins.symbol(::PostOffice) = :postoffice
postcode(post::PostOffice) = post.postcode
addr(post::PostOffice) = Addr(postcode(post), 0)

struct PostException
    message::String
end

abstract type LocalRegistry <: Plugin end
Plugins.symbol(::LocalRegistry) = :registry

abstract type SparseActivity <: Plugin end
Plugins.symbol(::SparseActivity) = :sparseactivity

abstract type Space <: Plugin end
abstract type EuclideanSpace <: Space end
Plugins.symbol(::Space) = :space

abstract type Positioner <: Plugin end
Plugins.symbol(::Positioner) = :positioner

# naming
function registername end
function getname end


include("actorstore.jl")
include("msg.jl")
include("onmessage.jl")
include("signal.jl")
include("zmq_postoffice.jl")
#include("udp_postoffice.jl")
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
include("classic.jl")

function __init__()
    Plugins.register(EuclideanSpaceImpl)
    Plugins.register(OnMessageImpl)
end

end # module
