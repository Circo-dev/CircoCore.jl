# SPDX-License-Identifier: LGPL-3.0-only
using Test
using CircoCore
import CircoCore.onmessage
import CircoCore.onmigrate

const PEER_COUNT = 1000
const ROOT_COUNT = 3

@testset "Cluster" begin
    cluster = []
    scheduler = ActorScheduler([])
    rootaddresses = []
    for i in 1:ROOT_COUNT
        root = ClusterActor(NodeInfo("#$(length(cluster))"), rootaddresses)
        push!(cluster, root)
        schedule!(scheduler, root)
        scheduler(;process_external=false)
        rootaddresses = [address(node) for node in cluster]
    end
    
    for i in 1:PEER_COUNT - ROOT_COUNT
        node = ClusterActor(NodeInfo("#$(length(cluster))"), rootaddresses)
        push!(cluster, node)
        schedule!(scheduler, node)
        #if rand() < 0.5
            scheduler(;process_external=false)
        #end
    end
    scheduler(;process_external=false)
    shutdown!(scheduler)
    avgpeers = sum([length(node.peers) for node in cluster]) / length(cluster)
    maxpeerupdates = maximum([node.peerupdate_count for node in cluster])
    avgpeerupdate = sum([node.peerupdate_count for node in cluster]) / length(cluster)
    avgupstreamfriends = sum([length(node.upstream_friends) for node in cluster]) / length(cluster)
    println("Avg peer count: $avgpeers; Peer update max: $maxpeerupdates avg: $avgpeerupdate; Upstream friends avg: $avgupstreamfriends")
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