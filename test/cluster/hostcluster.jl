module HostClusterTest

using Test, Printf
using CircoCore
import CircoCore:onschedule, onmessage, onmigrate

const CLUSTER_SIZE = 30

@testset "HostCluster" begin
    @testset "Host cluster with internal root" begin
        host = Host(CLUSTER_SIZE, default_plugins)
        hosttask = @async host()
        sleep(CLUSTER_SIZE * 0.2 + 9.0)
        for i in 1:CLUSTER_SIZE
            scheduler = host.schedulers[i]
            helperaddr = scheduler.plugins[:cluster].helper
            helperactor = CircoCore.getactorbyid(scheduler, box(helperaddr))
            @test length(helperactor.peers) == CLUSTER_SIZE
        end
        shutdown!(host)
    end
end
end