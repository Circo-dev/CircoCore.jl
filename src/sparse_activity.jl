# SPDX-License-Identifier: MPL-2.0

module Activity

using Plugins
using ..CircoCore

mutable struct SparseActivityImpl <: CircoCore.SparseActivity
    counter::UInt
    SparseActivityImpl(;options...) = new(1)
end
__init__() = Plugins.register(SparseActivityImpl)

@inline function CircoCore.localdelivery(as::SparseActivityImpl, scheduler, msg, targetactor)
    if as.counter == 0
        scheduler.hooks.actor_activity_sparse16(scheduler, targetactor)
        as.counter = rand(UInt8) >> 3
        if as.counter % 2 == 1
            as.counter -= 1
        end
        if as.counter < 2
            scheduler.hooks.actor_activity_sparse256(scheduler, targetactor)
        end
    else
        as.counter -= 1
    end
    return false
end

end # module