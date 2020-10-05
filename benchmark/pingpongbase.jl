# SPDX-License-Identifier: LGPL-3.0-only
using CircoCore

# ANCHOR Ping-Pong

mutable struct PingPonger{TCore} <: AbstractActor{TCore}
    peer::Union{Addr, Nothing}
    pings_sent::Int64
    pongs_got::Int64
    core::TCore
end
PingPonger(peer, core) = PingPonger(peer, 0, 0, core)

struct Ping end
struct Pong end
struct CreatePeer end

function sendping(service, me::PingPonger)
    send(service, me, me.peer, Ping())
    me.pings_sent += 1
end

function sendpong(service, me::PingPonger)
    send(service, me, me.peer, Pong())
end

function CircoCore.onmessage(me::PingPonger, message::CreatePeer, service)
    peer = PingPonger(addr(me), emptycore(service))
    me.peer =  spawn(service, peer)
    sendping(service, me)
end

function CircoCore.onmessage(me::PingPonger, ::Ping, service)
    sendpong(service, me)
    return nothing
end

function CircoCore.onmessage(me::PingPonger, ::Pong, service)
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

CircoCore.onmessage(me::PingPonger, req::ReadPerf, service) = begin
    send(service, me, req.requestor, PerfReading(box(me), me.pings_sent, me.pongs_got, Libc.time()))
end
