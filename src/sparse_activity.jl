# SPDX-License-Identifier: LGPL-3.0-only

mutable struct ActivityService <: Plugin
    counter::UInt
    ActivityService() = new(1)
end

Plugins.symbol(::ActivityService) = :activity

@inline function CircoCore.localdelivery(as::ActivityService, scheduler, msg, targetactor)
    if as.counter == 0
        hooks(scheduler).actor_activity_sparse16(targetactor)
        as.counter = rand(UInt8) >> 3
        if as.counter % 2 == 1
            as.counter -= 1
        end
        if as.counter < 2
            hooks(scheduler).actor_activity_sparse256(targetactor)
        end
    else
        as.counter -= 1
    end
    return false
end
