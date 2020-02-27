# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore.onmessage
import CircoCore.onmigrate

include("migrate-base.jl")

function onmessage(me::Migrant, message::Request, service)
    send(service, me, message.responseto, Response())
end

function onmessage(me::Migrant, message::Results, service)
    me.stayercopy = message.stayer
    println("got results: $message")
    die(service, me)
end

function onmigrate(me::Migrant, service)
    println("Successfully migrated to $me")
    send(service, me, me.stayeraddress, MigrateDone(address(me)))
end

function startsource()
    source = "include(\"test/migrate/migrate-source.jl\");migratetoremote()"
    run(pipeline(Cmd(["julia", "--project", "-e", source]);stdout=stdout,stderr=stderr);wait=false)
end

@testset "Migration" begin
    scheduler = ActorScheduler([])
    startsource()
    scheduler()
    shutdown!(scheduler)
    @test stayer.responsereceived == 1
    @test !isnothing(stayer.newaddressbyrecepientmoved)
    @test stayer.newaddressbyrecepientmoved == stayer.newaddressbyselfreport
end