# You need to add the Distributed package as a dependency in order for this to run
@everywhere using Pkg
@everywhere Pkg.activate(".")
@everywhere include("benchmark/maxthroughputbase.jl")

# Create schedulers and pingers on worker processes
@sync @distributed for i = 1:nworkers()
    global schedulers
    global pingers
    ps = [Pinger(nothing, emptycore(ctx)) for i=1:1]
    scheduler = Scheduler(ctx, ps) # A single scheduler per process
    for pinger in ps
        send(scheduler, addr(pinger), CreatePeer())
        push!(pingers, addr(pinger))
    end
    push!(schedulers, scheduler)
end

# Collect pingers from worker processes
all_pingers = []
for i = 2:nworkers() + 1
    global all_pingers
    push!(all_pingers, fetch(@spawnat i pingers)...)
end

# Run remote schedulers
@distributed for i = 1:nworkers()
    for scheduler in schedulers
        scheduler(; remote = true)
    end
end

# Wait Rudimentarily for them to start
sleep(8)

# Create and run the coordinator on the master process
coordinator = Coordinator(all_pingers)
scheduler = Scheduler(ctx, [coordinator])
spawn(scheduler, coordinator)
# TODO Check this if it's run correctly
scheduler(; remote = true)

# Stop remote schedulers
@distributed for i = 1:nworkers()
    for scheduler in schedulers
        shutdown!(scheduler)
    end
end
;
