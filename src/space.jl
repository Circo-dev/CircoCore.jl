# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

struct SpaceService <: SchedulerPlugin
end

infotonhandler(plugin::SpaceService) = apply_infoton

function apply_infoton(space::SpaceService, scheduler, targetactor::AbstractActor, message)
    diff = message.infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    if difflen < 150.0
        return nothing
    end
    targetactor.core.pos += diff / difflen
    return nothing
end
