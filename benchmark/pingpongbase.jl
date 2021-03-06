# SPDX-License-Identifier: MPL-2.0
using CircoCore

# ANCHOR Ping-Pong

mutable struct Pinger{TCore} <: Actor{TCore}
    peer::Union{Addr, Nothing}
    pings_sent::Int64
    pongs_got::Int64
    core::TCore
    Pinger(peer, core) = new{typeof(core)}(peer, 0, 0, core)
end


mutable struct Ponger{TCore} <: Actor{TCore}
    peer::Addr
    core::TCore
    Ponger(peer, core) = new{typeof(core)}(peer, core)
end

struct Ping end
struct Pong end
struct CreatePeer end

function sendping(service, me::Pinger)
    send(service, me, me.peer, Ping())
    me.pings_sent += 1
end

function sendpong(service, me::Ponger)
    send(service, me, me.peer, Pong())
end

CircoCore.onmessage(me::Pinger, ::CreatePeer, service) = begin
    peer = Ponger(addr(me), emptycore(service))
    me.peer =  spawn(service, peer)
    sendping(service, me)
end

CircoCore.onmessage(me::Ponger, ::Ping, service) = sendpong(service, me)

CircoCore.onmessage(me::Pinger, ::Pong, service) = begin
    me.pongs_got += 1
    sendping(service, me)
    return nothing
end

struct ReadPerf
    requestor::Addr
end

struct PerfReading
    reporter::ActorId
    pings_sent::Int
    pongs_got::Int
    timestamp::Float64
end
PerfReading() = PerfReading(0, 0, 0, Libc.time())

CircoCore.onmessage(me::Pinger, req::ReadPerf, service) = begin
    send(service, me, req.requestor, PerfReading(box(me), me.pings_sent, me.pongs_got, Libc.time()))
end
