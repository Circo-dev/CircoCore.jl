# SPDX-License-Identifier: LGPL-3.0-only

struct Infoton
    sourcepos::Pos
    energy::Float16
end

const INFO = 1.0 # Informational constant. TODO define it meaningfully

struct SpaceService <: SchedulerPlugin
end

infotonhandler(plugin::SpaceService) = apply_infoton

function apply_infoton(space::SpaceService, scheduler, targetactor::AbstractActor, message)
    targetactor.core.pos = targetactor.core.pos + Pos(1.0, 0.0, 0.0)
end
