using Distributed
@everywhere using Pkg
@everywhere Pkg.activate(".")
@everywhere using CircoCore
@everywhere include("benchmark/pingpongbase.jl")
@everywhere include("benchmark/maxthroughputbase.jl")

@everywhere ctx = CircoContext(;
    profile=CircoCore.Profiles.MinimalProfile(),
    userpluginsfn=() -> [CircoCore.PostOffice()]
)

@everywhere schedulers = []
@everywhere pingers = []

@sync @distributed for i = 1:nworkers()
    global schedulers
    global pingers
    ps = [PingPonger(nothing, emptycore(ctx)) for i=1:1]
    scheduler = ActorScheduler(ctx, ps)
    for pinger in ps
        deliver!(scheduler, addr(pinger), CreatePeer())
        push!(pingers, addr(pinger))
    end
    push!(schedulers, scheduler)
end

all_pingers = []
for i = 2:nworkers() + 1
    global all_pingers
    push!(all_pingers, fetch(@spawnat i pingers)...)
end

@show all_pingers

@distributed for i = 1:nworkers()
    for scheduler in schedulers
        scheduler(; remote = true, exit = true)
    end
end

sleep(8)
coordinator = Coordinator(all_pingers, emptycore(ctx))
scheduler = ActorScheduler(ctx, [coordinator])
spawn(scheduler, coordinator)
scheduler(; remote = true, exit = true)
