module SignalTest
using Test
using CircoCore

mutable struct SigTest <: Actor{Any}
    core
end

@testset "SigTerm" begin
    @test Die == CircoCore.SigTerm

    ctx = CircoContext(;target_module=@__MODULE__)
    tester = SigTest(emptycore(ctx))
    scheduler = Scheduler(ctx, [tester])
    scheduler(;remote = false) # to spawn the zygote

    @test CircoCore.is_scheduled(scheduler, tester) == true
    send(scheduler, tester, Die())
    actorcount = scheduler.actorcount
    scheduler(;remote = false) # to spawn the zygote
    @test CircoCore.is_scheduled(scheduler, tester) == false
    @test scheduler.actorcount == actorcount - 1

    shutdown!(scheduler)
end

end
