# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

struct SpaceService <: SchedulerPlugin
end

infotonhandler(plugin::SpaceService) = apply_infoton

const I = 1.0
const TARGET_DISTANCE = 350

function apply_infoton(space::SpaceService, scheduler, targetactor::AbstractActor, message)
    diff = message.infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    energy = message.infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE || energy < 0 && difflen > TARGET_DISTANCE * 3
        return nothing
    end
    targetactor.core.pos += diff / (difflen * energy * I)
    return nothing
end
