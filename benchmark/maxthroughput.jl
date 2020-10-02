# SPDX-License-Identifier: LGPL-3.0-only
using CircoCore

const MSG_COUNT = 50_000_000

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
    if me.pings_sent == MSG_COUNT
        die(service, me)
    end
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
    if me.pongs_got == MSG_COUNT
        die(service, me)
    else
        sendping(service, me)
    end
    return nothing
end

const ctx = CircoContext(;
    profile=CircoCore.Profiles.MinimalProfile(),
    userpluginsfn=() -> [CircoCore.PostOffice()]
)

schedulers = ActorScheduler[]
pingers = PingPonger[]
for i = 1:Threads.nthreads()
    ps = [PingPonger(nothing, emptycore(ctx)) for i=1:1]
    scheduler = ActorScheduler(ctx, ps)
    push!(schedulers, scheduler)
    for pinger in ps
        deliver!(scheduler, addr(pinger), CreatePeer())
    end
    push!(pingers, ps...)
end

startts = time_ns()
Threads.@threads for i = 1:length(schedulers)
    schedulers[i](; remote = false, exit = true)
end
endts = time_ns()
timediff = (endts - startts) / 1e9

total = sum(pinger.pings_sent + pinger.pongs_got for pinger in pingers)

println("Total messages sent: $total")
println("Time: $(timediff) secs")
println("$(total / timediff) msg/sec")
