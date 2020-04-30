# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

struct SpaceService <: SchedulerPlugin
end

infotonhandler(plugin::SpaceService) = apply_infoton

const I = 1.0
const TARGET_DISTANCE = 150

function apply_infoton(space::SpaceService, scheduler, targetactor::AbstractActor, message)
    diff = message.infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    if difflen < TARGET_DISTANCE
        return nothing
    end
    targetactor.core.pos += diff / (difflen * I)
    return nothing
end
