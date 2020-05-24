# SPDX-License-Identifier: LGPL-3.0-only

using LinearAlgebra

struct SpaceService <: Plugin
end

const I = 1.0
const TARGET_DISTANCE = .80

function apply_infoton(targetactor::T, infoton::Infoton) where {T<:AbstractActor}
    diff = infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    energy = infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE #|| energy < 0 && difflen > TARGET_DISTANCE / 2
        return nothing
    end
    targetactor.core.pos += diff / difflen * energy * I
    return nothing
end
