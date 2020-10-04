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

# ANCHOR Monitoring

struct ReadAndClearPerf # Request for monitoring info and clearing counters
    requestor::Addr
end

struct PerfRead
    reporter::ActorId
    pings_sent::Int
    pongs_got::Int
    timestamp::Float64
end
PerfRead() = PerfRead(0, 0, 0, Libc.time())

mutable struct Coordinator{TCore} <: AbstractActor{TCore}
    pingers::Vector{PingPonger}
    results::Dict{ActorId, Vector{PerfRead}}
    gotreads::Int
    core::TCore
    Coordinator(pingers, core) = begin
        results = Dict{ActorId, Vector{PerfRead}}(box(a) => [PerfRead()] for a in pingers)
        return new{typeof(core)}(pingers, results, 0, core)
    end
end

CircoCore.onschedule(me::Coordinator, service) = begin
    @info "Monitoring $(length(me.pingers)) pingers."
    sendreqs(me, service)
end

function sendreqs(me::Coordinator, service)
    me.gotreads = 0
    for p in pingers
        send(service, me, addr(p), ReadAndClearPerf(addr(me)))
    end
end

CircoCore.onmessage(me::PingPonger, req::ReadAndClearPerf, service) = begin
    send(service, me, req.requestor, PerfRead(box(me), me.pings_sent, me.pongs_got, Libc.time()))
    me.pings_sent = 0
    me.pongs_got = 0
end

CircoCore.onmessage(me::Coordinator, r::PerfRead, service) = begin
    push!(me.results[r.reporter], r)
    me.gotreads += 1
    if me.gotreads == length(me.pingers)
        printlastresults(me)
        settimeout(service, me, 1.0)
    end
end

CircoCore.onmessage(me::Coordinator, t::Timeout, service) = begin
    sendreqs(me, service)
end

function printlastresults(c::Coordinator)
    println()
    total = 0
    totaltime = 0.0
    for perfs in values(c.results)
        curperf = perfs[end]
        lastperf = perfs[end - 1]
        msgcount = curperf.pings_sent + curperf.pongs_got
        cputime = curperf.timestamp - lastperf.timestamp
        total += msgcount
        totaltime += cputime
        print("$(msgcount / cputime), ")
    end
    println("\nTotal: $(total / totaltime * length(c.pingers))")
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

coordinator = Coordinator(pingers, emptycore(ctx))
spawn(schedulers[1], coordinator)

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
