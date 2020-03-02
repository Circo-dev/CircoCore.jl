# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore.onmessage
import CircoCore.onmigrate

const PEER_COUNT = 500

@testset "Cluster" begin
    cluster = []
    root = ClusterActor("#$(length(cluster))")
    push!(cluster, root)
    scheduler = ActorScheduler(cluster)
    for i in 1:PEER_COUNT - 1
        node = ClusterActor(SchedulerInfo("#$(length(cluster))"), [address(root)])
        push!(cluster, node)
        schedule!(scheduler, node)
        if rand() < 0.7
            scheduler(;process_external=false)
        end
    end
    scheduler(;process_external=false)
    shutdown!(scheduler)
    avgpeers = sum([length(node.peers) for node in cluster]) / length(cluster)
    maxpeerupdates = maximum([node.peerupdate_count for node in cluster])
    println("Avg peer count: $avgpeers, max peer update: $maxpeerupdates")
    @test Int(avgpeers) == PEER_COUNT
    for i in 1:PEER_COUNT
        idx1 = rand(1:PEER_COUNT)
        node1 = cluster[idx1]
        idx2 = rand(1:PEER_COUNT)
        node2 = cluster[idx2]
        @test node1.peers[address(node2)].address == address(node2)
        @test node2.peers[address(node1)].address == address(node1)
    end
end