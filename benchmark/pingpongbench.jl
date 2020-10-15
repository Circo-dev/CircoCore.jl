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

for i=1:1000
    typename = Symbol("XX$i")
    eval(quote
        struct $typename end
        CircoCore.onmessage(me::PingPonger, message::$typename, service::Service) = $i
    end)
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

function createbench(ctx)
    pingers = [PingPonger(nothing, emptycore(ctx)) for i=1:1]
    scheduler = Scheduler(ctx, pingers)
    for pinger in pingers
        deliver!(scheduler, addr(pinger), CreatePeer())
    end
    return (run! = () -> scheduler(; remote = false, exit = true),
        teardown! = () -> shutdown!(scheduler),
        scheduler = scheduler)
end

function pingpongbench()
    bench = createbench(ctx)
    @time bench.run!()
    bench.teardown!()
end

const ctx = CircoContext(;profile=CircoCore.Profiles.DefaultProfile())

using Main.Atom.Profiler
using Profile
using Main.Atom.Profiler.FlameGraphs
using AbstractTrees
AbstractTrees.children(d::Dict{Symbol,Any}) = d[:children] # To make the json dict iterable

pingers = [PingPonger(nothing, emptycore(ctx)) for i=1:1]
scheduler = Scheduler(ctx, pingers)
for pinger in pingers
    deliver!(scheduler, addr(pinger), CreatePeer())
end

#run profiler here.........
@profiler scheduler(; remote = false, exit = true)

data = Profile.fetch()
@info "Analyzing"
graph = FlameGraphs.flamegraph(data)
#Main.Atom.Profiler.pruneinternal!(graph)
#Main.Atom.Profiler.prunetask!(graph)
js = Main.Atom.Profiler.tojson(graph)

dynamic_dispatches = count(PostOrderDFS(js)) do l
    d = "dynamic-dispatch" ∈ l[:classes]
end

@show dynamic_dispatches

for l in PostOrderDFS(js)
    if "dynamic-dispatch" ∈ l[:classes]
        println("$(l[:count]) - $(l[:location]):$(l[:line])")
    end
end
