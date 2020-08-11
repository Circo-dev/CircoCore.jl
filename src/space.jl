# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

const I = 1.0
const TARGET_DISTANCE = 8.0

struct Space <: Plugin
end

@inline function localdelivery(space::Space, scheduler, msg, targetactor)
    apply_infoton(targetactor, msg.infoton)
    if rand(UInt8) < 30 # TODO: config and move to a hook
        apply_infoton(targetactor, scheduler_infoton(scheduler, targetactor))
        if rand(UInt8) < 15
            hooks(scheduler).actor_activity_sparse(targetactor)
        end
    end
    return false
end

"""
    apply_infoton(targetactor::AbstractActor, infoton::Infoton)

An infoton acting on an actor.

Please check the source and the examples for more info.
"""
@inline function apply_infoton(targetactor::AbstractActor, infoton::Infoton)
    @fastmath diff = infoton.sourcepos - targetactor.core.pos
    @fastmath difflen = norm(diff)
    energy = infoton.energy
    if @fastmath energy > 0 && difflen < TARGET_DISTANCE #|| energy < 0 && difflen > TARGET_DISTANCE / 2
        return nothing
        energy = -energy
    end
    @fastmath targetactor.core.pos += diff / difflen * energy * I
    return nothing
end
