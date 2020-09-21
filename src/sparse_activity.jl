# SPDX-License-Identifier: LGPL-3.0-only

mutable struct ActivityService <: Plugin
    counter::UInt
    ActivityService(;options...) = new(1)
end

Plugins.symbol(::ActivityService) = :activity

@inline function CircoCore.localdelivery(as::ActivityService, scheduler, msg, targetactor)
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
