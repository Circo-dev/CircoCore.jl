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

CircoCore.ontraitmessage(t::Union{Trait1, Trait2, Trait3}, me, msg::AllTraitMsg, service) = begin
    push!(me.gotmessages, (typeof(t), msg))
end

CircoCore.ontraitmessage(t::Trait2, me, msg::SecondTraitMsg, service) = begin
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
    @test tester.gotmessages[1] == (Trait2, 42, SecondTraitMsg(2))
    @test tester.gotmessages[2] == (Nothing, SecondTraitMsg(2))
    @test tester.gotmessages[3] == (Trait1, AllTraitMsg(1))
    @test tester.gotmessages[4] == (Trait2, AllTraitMsg(1))
    @test tester.gotmessages[5] == (Trait3, AllTraitMsg(1))
    @test tester.gotmessages[6] == (Nothing, AllTraitMsg(1))
    @test tester.gotmessages[7] == (Nothing, NonTraitedMsg(3))
    shutdown!(scheduler)
end

end # module
