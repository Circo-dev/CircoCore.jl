# SPDX-License-Identifier: LGPL-3.0-only

using Distributed

function initfirstnode()
    #@info "Starting first node on process $(myid())"
    root = ClusterActor("Node #$(myid())")
    scheduler = ActorScheduler([root])
    return root
end

function start()
    if nworkers() <= 1
        #startfirstnode()
    else
        firstnode = @fetchfrom 2 initfirstnode()
        println(firstnode)
        @info "Root address: $(address(firstnode))"
    end
end
