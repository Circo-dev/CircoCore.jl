# SPDX-License-Identifier: MPL-2.0
using Test
using CircoCore
using Plugins

struct SchedulerMock
    hooks
    SchedulerMock() = new((
        actor_activity_sparse16 = (scheduler, actor) -> actor.count16 += 1,
        actor_activity_sparse256 = (scheduler, actor) -> actor.count256 += 1
    ))
end

struct HooksMock
    actor_activity_sparse16
    actor_activity_sparse256
end

mutable struct ActorMock
    count16::Int
    count256::Int
end

const NUM_SAMPLES = 20000
@testset "SparseActivity" begin
    scheduler = SchedulerMock()
    as = CircoCore.Activity.SparseActivityImpl()
    actor = ActorMock(0, 0)
    for i = 1:NUM_SAMPLES
        CircoCore.localdelivery(as, scheduler, nothing, actor)
    end
    println("sparse16: $(actor.count16 / NUM_SAMPLES) vs $(1 / 16)")
    println("sparse256: $(actor.count256 / NUM_SAMPLES)  vs $(1 / 256)")
    @test isapprox(actor.count16 / NUM_SAMPLES,  1 / 16; atol = 0.06)
    @test isapprox(actor.count256 / NUM_SAMPLES, 1 / 256; atol = 0.03)
end
