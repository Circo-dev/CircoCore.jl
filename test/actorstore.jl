using Test
using CircoCore

struct Actor1 <: Actor{Any}
    core
end

@testset "ActorStore" begin
    s = CircoCore.ActorStore(UInt64(1) => Actor1(1), UInt64(2) => Actor1(2))
    @test length(s) == 2
    @test haskey(s, UInt64(1))
    @test s[UInt64(1)].core == 1
    @test get(s, UInt64(2), nothing).core == 2
    for p in s
        @test p isa Pair{UInt64, Actor1}
    end
    for a in values(s)
        @test a isa Actor1
    end
    delete!(s, UInt64(1))
    @test !haskey(s, UInt64(1))
    @test length(s) == 1
    s[UInt64(1)] = Actor1(42)
    @test s[UInt64(1)].core == 42
    @test length(s) == 2
end