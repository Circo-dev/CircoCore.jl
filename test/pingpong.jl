# SPDX-License-Identifier: MPL-2.0
using Test, Printf
using CircoCore

mutable struct PingPonger{TCore} <: Actor{TCore}
    peer::Union{Addr, Nothing}
    pings_sent::Int64
    pongs_got::Int64
    core::TCore
end
PingPonger(peer, core) = PingPonger(peer, 0, 0, core)

struct Ping end
struct Pong end
struct CreatePeer end

@inline function sendping(service, me::PingPonger)
    send(service, me, me.peer, Ping())
    me.pings_sent += 1
end

@inline function sendpong(service, me::PingPonger)
    send(service, me, me.peer, Pong())
end

function CircoCore.onmessage(me::PingPonger, message::CreatePeer, service)
    peer = PingPonger(addr(me), emptycore(service))
    me.peer =  spawn(service, peer)
    sendping(service, me)
end

@inline function CircoCore.onmessage(me::PingPonger, ::Ping, service)
    sendpong(service, me)
end

@inline function CircoCore.onmessage(me::PingPonger, ::Pong, service)
    me.pongs_got += 1
    sendping(service, me)
end

const PINGER_PARALLELISM = 1

@testset "PingPong" begin
    ctx = CircoContext(;target_module=@__MODULE__, profile=CircoCore.Profiles.MinimalProfile(),
     userpluginsfn=()->[CircoCore.PostOffice])
    pingers = [PingPonger(nothing, emptycore(ctx)) for i=1:PINGER_PARALLELISM]
    scheduler = Scheduler(ctx, pingers)
    scheduler(;remote = false) # to spawn the zygote
    for pinger in pingers
        send(scheduler, pinger, CreatePeer())
    end
    schedulertask = @async scheduler(; remote = false)

    @info "Sleeping to allow ping-pong to start."
    sleep(3.0)
    for pinger in pingers
        @test pinger.pings_sent > 1e3
        @test pinger.pongs_got > 1e3
    end

    @info "Measuring ping-pong performance (10 secs)"
    startpingcounts = [pinger.pings_sent for pinger in pingers]
    startts = Base.time_ns()
    sleep(4.0)
    rounds_made = sum([pingers[i].pings_sent - startpingcounts[i] for i=1:length(pingers)])
    wall_time_used = Base.time_ns() - startts
    for pinger in pingers
        @test pinger.pings_sent > 1e3
        @test pinger.pongs_got > 1e3
    end
    shutdown!(scheduler)
    sleep(0.001)
    endpingcounts = [pinger.pings_sent for pinger in pingers]
    sleep(0.1)
    for i = 1:length(pingers)
        @test pingers[i].pongs_got in [pingers[i].pings_sent, pingers[i].pings_sent - 1]
        @test endpingcounts[i] === pingers[i].pings_sent
    end
    @printf "In-thread ping-pong performance: %f rounds/sec\n" (rounds_made / wall_time_used * 1e9)
end
