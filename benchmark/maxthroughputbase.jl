include("pingpongbase.jl")

mutable struct Coordinator{TCore} <: AbstractActor{TCore}
    pingeraddrs::Vector{Addr}
    results::Dict{ActorId, Vector{PerfReading}}
    gotreads::Int
    core::TCore
    Coordinator(pingeraddrs, core) = begin
        results = Dict{ActorId, Vector{PerfReading}}(box(a) => PerfReading[] for a in pingeraddrs)
        return new{typeof(core)}(pingeraddrs, results, 0, core)
    end
end

CircoCore.onschedule(me::Coordinator, service) = begin
    @info "Monitoring $(length(me.pingeraddrs)) pingers."
    sendreqs(me, service)
end

function sendreqs(me::Coordinator, service)
    me.gotreads = 0
    for p in me.pingeraddrs
        send(service, me, p, ReadPerf(addr(me)))
    end
end

CircoCore.onmessage(me::Coordinator, r::PerfReading, service) = begin
    push!(me.results[r.reporter], r)
    me.gotreads += 1
    if me.gotreads == length(me.pingeraddrs)
        printlastresults(me)
        settimeout(service, me, 1.0)
    end
end

CircoCore.onmessage(me::Coordinator, ::Timeout, service) = begin
    sendreqs(me, service)
end

function printlastresults(c::Coordinator)
    println()
    total = 0
    totaltime = 0.0
    for perfs in values(c.results)
        length(perfs) <= 1 && continue
        curperf = perfs[end]
        lastperf = perfs[end - 1]
        msgcount = curperf.pings_sent + curperf.pongs_got - lastperf.pings_sent - lastperf.pongs_got
        cputime = curperf.timestamp - lastperf.timestamp
        total += msgcount
        totaltime += cputime
        print("$(msgcount / cputime), ")
    end
    if totaltime > 0
        println("\nTotal: $(total / totaltime * length(c.pingeraddrs))")
    end
end

schedulers = []
pingers = []
ctx = CircoContext(;
    profile=CircoCore.Profiles.MinimalProfile(),
    userpluginsfn=() -> [CircoCore.PostOffice()]
)
