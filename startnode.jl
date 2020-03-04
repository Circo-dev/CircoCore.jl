using CircoCore

function startfirstnode()
    root = ClusterActor("First Node")
    scheduler = ActorScheduler([root])
    println("First node started. To join to this cluster, use the address:")
    println(address(root))
    scheduler()
end

function startnodeandconnect(roots)
    root = ClusterActor(NodeInfo("Another Node"), roots)
    scheduler = ActorScheduler([root])
    println("Node started.")
    scheduler()
end

