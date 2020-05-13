# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

struct SpaceService <: SchedulerPlugin
end

infotonhandler(plugin::SpaceService) = apply_infoton

const I = 1.0
const TARGET_DISTANCE = 80

@inline function scheduler_infoton(scheduler, actor::AbstractActor)
    diff = scheduler.pos - actor.core.pos
    distfromtarget = 2000 - norm(diff)
    energy = sign(distfromtarget) * distfromtarget * distfromtarget * -6 / 2000000
    return Infoton(scheduler.pos, energy)
end

@inline function collide(actor::AbstractActor, infoton::Infoton)
    diff = infoton.sourcepos - actor.core.pos
    difflen = norm(diff)
    energy = infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE #|| energy < 0 && difflen > TARGET_DISTANCE / 2
        return nothing
    end
    actor.core.pos += diff / (difflen / energy * I)
    return nothing
end

function apply_infoton(space::SpaceService, scheduler, targetactor::AbstractActor, message)
    collide(targetactor, message.infoton)
    if (rand(UInt8) < 30)
        collide(targetactor, scheduler_infoton(scheduler, targetactor))
    end
    return nothing
end
