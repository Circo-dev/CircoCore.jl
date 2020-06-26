# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

const I = 1.0
const TARGET_DISTANCE = 1.50

"""
    apply_infoton(targetactor::AbstractActor, infoton::Infoton)

An infoton acting on an actor.

Please check the source and the examples for more info.
"""
@inline function apply_infoton(targetactor::AbstractActor, infoton::Infoton)
    diff = infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    energy = infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE #|| energy < 0 && difflen > TARGET_DISTANCE / 2
        return nothing
        energy = -energy
    end
    targetactor.core.pos += diff / difflen * energy * I
    return nothing
end
