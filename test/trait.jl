module TraitTest
using CircoCore
using Test

abstract type MyMsg end

struct NonTraitedMsg <: MyMsg
    a
end

struct AllTraitMsg <: MyMsg
    a
end

struct SecondTraitMsg <: MyMsg
    a
end

struct Trait1 end
struct Trait2
    config::Int
end
struct Trait3 end

mutable struct TraitTester <: Actor{Any}
    gotmessages
    core
    TraitTester() = new([])
end

CircoCore.traits(::Type{TraitTester}) = (Trait1, Trait2(42), Trait3)

CircoCore.onmessage(t::Union{Trait1, Trait2, Trait3}, me, msg::AllTraitMsg, service) = begin
    push!(me.gotmessages, (typeof(t), msg))
end

CircoCore.onmessage(t::Trait2, me, msg::SecondTraitMsg, service) = begin
    push!(me.gotmessages, (typeof(t), t.config, msg))
end

CircoCore.onmessage(me::TraitTester, msg::MyMsg, service) = begin
    push!(me.gotmessages, (Nothing, msg))
end

@testset "Trait Order" begin
    ctx = CircoContext(;target_module=@__MODULE__)
    tester = TraitTester()
    scheduler = Scheduler(ctx, [tester])
    scheduler(;remote=false)
    send(scheduler, tester, SecondTraitMsg(2))
    send(scheduler, tester, AllTraitMsg(1))
    send(scheduler, tester, NonTraitedMsg(3))
    scheduler(;remote=false)
    @test tester.gotmessages == [
        (Trait2, 42, SecondTraitMsg(2)), (Nothing, SecondTraitMsg(2)),
        (Trait1, AllTraitMsg(1)), (Trait2, AllTraitMsg(1)), (Trait3, AllTraitMsg(1)), (Nothing, AllTraitMsg(1)),
        (Nothing, NonTraitedMsg(3))
        ]
    shutdown!(scheduler)
end

struct AutoDieTrait
    timeout::Float32
end

mutable struct AutoDieTraitTester <: Actor{Any}
    core
    AutoDieTraitTester() = new()
end

CircoCore.traits(::Type{AutoDieTraitTester}) = (AutoDieTrait(5))


@testet "AutoDieTrait" begin
    
end
end # module
