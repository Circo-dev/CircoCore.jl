# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore.onmessage
import CircoCore.onmigrate

include("migrate-base.jl")

function onmigrate(me::Migrant, service)
    println("Successfully migrated to $me")
    send(service, me, me.stayeraddress, MigrateDone(address(me)))
end

function onmessage(me::Migrant, message::Request, service)
    send(service, me, message.responseto, Response())
end

function onmessage(me::Migrant, message::Results, service)
    die(service, me)
end

function onmessage(me::ResultsHolder, message::Results, service)
    println("Got results $message")
    me.results = message
    die(service, me)
end

function startsource(targetpostcode, resultsholder_address)
    source = "include(\"test/migrate/migrate-source.jl\");migratetoremote(\"$targetpostcode\", $resultsholder_address)"
    run(pipeline(Cmd(["julia", "--project", "-e", source]);stdout=stdout,stderr=stderr);wait=false)
end

@testset "Migration" begin
    resultsholder = ResultsHolder()
    scheduler = ActorScheduler([resultsholder])
    startsource(postcode(scheduler),address(resultsholder))
    scheduler(;exit_when_done=true)
    shutdown!(scheduler)
    stayer = resultsholder.results.stayer
    @test stayer.responsereceived == 1
    @test isdefined(stayer, :newaddress_recepientmoved)
    @test stayer.newaddress_recepientmoved == stayer.newaddress_selfreport
end