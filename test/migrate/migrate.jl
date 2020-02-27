# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore.onmessage
import CircoCore.migrated

include("migrate-base.jl")

function migrated(me::Migrant, service)
    println("Successfully migrated to $me")
end

function startsource()
    source = "include(\"test/migrate/migrate-source.jl\");migratetoremote()"
    run(Cmd(["julia", "--project", "-e", source]))
end

@testset "Migration" begin
    scheduler = ActorScheduler([])
    startsource()
    scheduler()
    shutdown!(scheduler)
end