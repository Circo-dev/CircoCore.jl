# SPDX-License-Identifier: MPL-2.0

using Test
using CircoCore
using Plugins

struct StartMsg end
struct Die
    exit::Bool
end

mutable struct Dummy <: Actor{Any}
    core::Any
    diemessagearrived::Bool

    Dummy(core) = new(core, false)
end

function CircoCore.onmessage(me::Dummy, msg::Die, service)
    me.diemessagearrived = true

    die(service, me; exit = msg.exit)
end

function createDummyActors(numberOfActor, ctx) 
    actors = []
    while numberOfActor != 0
        push!(actors, Dummy(emptycore(ctx)))
        numberOfActor -= 1
    end
    return actors
end

function validateActors(actors::Vector{Any}, expectedValue::Bool)
    # every actor has the same diemessagearrived  fieldvalue
    @test mapreduce(a -> a.diemessagearrived, *, actors) == expectedValue
end


@testset "Scheduler" begin

    @testset "Scheduler with remote = false and exit = false" begin
        ctx = ctx = CircoContext(target_module = @__MODULE__)
        dummy = Dummy(emptycore(ctx))

        sdl = Scheduler(ctx, [])
        spawn(sdl, dummy)

        @test isempty(sdl.msgqueue)
        @test sdl.actorcount >= sdl.startup_actor_count
        @test dummy.diemessagearrived == false

        send(sdl, dummy, StartMsg())

        @test !isempty(sdl.msgqueue)

        sdl(;remote = false)

        @test isempty(sdl.msgqueue)
        @test sdl.actorcount >= sdl.startup_actor_count
        @test dummy.diemessagearrived == false

        shutdown!(sdl)
    end
    
    @testset "Scheduler with remote false and exiting true" begin
        ctx = ctx = CircoContext(target_module = @__MODULE__)
        dummy = Dummy(emptycore(ctx))

        sdl = Scheduler(ctx, [])
        spawn(sdl, dummy)
        
        @test isempty(sdl.msgqueue)
        @test sdl.actorcount >= sdl.startup_actor_count
        @test dummy.diemessagearrived == false

        send(sdl, dummy, Die(true))

        @test !isempty(sdl.msgqueue)

        sdl(;remote = false)

        @test isempty(sdl.msgqueue)
        @test sdl.actorcount == sdl.startup_actor_count
        @test dummy.diemessagearrived == true

        shutdown!(sdl)
    end

    @testset "Scheduler with remote true and exiting true, more Actor" begin
        ctx = CircoContext(target_module = @__MODULE__)
        actors = createDummyActors(10, ctx)

        finishedSignal = Channel{}(2)
        sdl = Scheduler(ctx, [])
        map(a -> spawn(sdl, a), actors)

        @async begin
            sdl(;remote = true) #stops when all actors die

            @test isempty(sdl.msgqueue)
            @test sdl.actorcount == sdl.startup_actor_count

            # if every body got the Die message that means the scheduler didn't exited when got the first exit = true "call"
            validateActors(actors, true)

            put!(finishedSignal, true)
        end

        @test isempty(sdl.msgqueue)
        @test sdl.actorcount >= sdl.startup_actor_count

        validateActors(actors, false)

        for index in eachindex(actors)
            dummy = actors[index]

            send(sdl, dummy, Die(true))
            sleep(0.8)
            @test isempty(sdl.msgqueue)
            @test sdl.actorcount + index - length(actors) == sdl.startup_actor_count
            @test dummy.diemessagearrived == true
        end

        @test take!(finishedSignal)
        shutdown!(sdl)
    end
end

