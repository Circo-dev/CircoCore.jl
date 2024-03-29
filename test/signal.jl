module SignalTest
using Test
using CircoCore

mutable struct SigTest <: Actor{Any}
    core
end

@testset "SigTerm" begin
    ctx = CircoContext(;target_module=@__MODULE__)
    tester = SigTest(emptycore(ctx))
    scheduler = Scheduler(ctx, [tester])
    scheduler(;remote = false)

    @test CircoCore.is_scheduled(scheduler, tester) == true
    send(scheduler, tester, SigTerm())
    actorcount = scheduler.actorcount
    scheduler(;remote = false)
    @test CircoCore.is_scheduled(scheduler, tester) == false
    @test scheduler.actorcount == actorcount - 1

    shutdown!(scheduler)
end

end
