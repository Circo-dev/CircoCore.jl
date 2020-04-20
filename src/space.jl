# SPDX-License-Identifier: LGPL-3.0-only

const INFO = 1.0e-2 # Informational constant. TODO define it meaningfully

struct SpaceService <: SchedulerPlugin
end

infotonhandler(plugin::SpaceService) = apply_infoton

function apply_infoton(space::SpaceService, scheduler, targetactor::AbstractActor, message)
    targetactor.core.pos = targetactor.core.pos - (targetactor.core.pos - message.infoton.sourcepos) * INFO
end
