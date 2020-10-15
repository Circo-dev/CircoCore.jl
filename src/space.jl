# SPDX-License-Identifier: MPL-2.0

using LinearAlgebra

const I = 1.0

const TARGET_DISTANCE = 8.0

"""
    pos(a::AbstractActor)::Pos

return the current position of the actor.

Call this on a spawned actor to get its position. Throws `UndefRefError` if the actor is not spawned.
"""
pos(a::AbstractActor) = a.core.pos

"""
    Pos(x::Real, y::Real, z::Real)
    Pos(coords)

A point in the 3D "actor space".

You can access the coords by pos.x, pos.y, pos.z.

Pos is implemented using an SVector{3, Float32}.
"""
struct Pos <: AbstractVector{Float32}
    coords::SVector{3, Float32}
    Pos(x, y, z) = new(SVector{3, Float32}(x, y, z))
    Pos(coords) = new(coords)
end

dist(a::Pos, b::Pos) = sqrt((a.coords[1]-b.coords[1])^2 + (a.coords[2]-b.coords[2])^2 + (a.coords[3]-b.coords[3])^2)
Base.:*(a::Pos, x::Real) = Pos(a.coords * x)
Base.:/(a::Pos, x::Real) = Pos(a.coords / x)
Base.:+(a::Pos, b::Pos) = Pos(a.coords + b.coords)
Base.:-(a::Pos, b::Pos) = Pos(a.coords - b.coords)
Base.getindex(pos::Pos, i::Int) = getindex(pos.coords, i)
Base.getproperty(pos::Pos, symbol::Symbol) = (symbol == :x) ? getfield(pos, :coords)[1] :
                                        (symbol == :y) ? getfield(pos, :coords)[2] :
                                        (symbol == :z) ? getfield(pos, :coords)[3] :
                                        getfield(pos, symbol)
Base.iterate(pos::Pos) = iterate(pos.coords)
Base.iterate(pos::Pos, state) = iterate(pos.coords, state)
Base.length(pos::Pos) = length(pos.coords)
Base.size(pos::Pos) = size(pos.coords)

Base.show(io::IO, ::MIME"text/plain", pos::Pos) = begin
    print(io, "Pos($(pos[1]), $(pos[2]), $(pos[3]))")
end

nullpos = Pos(0, 0, 0)

"""
    Infoton(sourcepos::Pos, energy::Real = 1)

Create an Infoton that carries `abs(energy)` amount of energy and has the sign `sign(energy)`.

The infoton mediates the force that awakens between communicating actors. When arriving at its
target actor, the infoton pulls/pushes the actor toward/away from its source, depending on its
sign (positive pulls).

The exact details of how the Infoton should act at its target is actively researched.
Please check or overload [`apply_infoton`](@ref).
"""
struct Infoton
    sourcepos::Pos
    energy::Float32
    Infoton(sourcepos::Pos, energy::Real = 1.0f0) = new(sourcepos, Float32(energy))
end
Infoton() = Infoton(nullpos, 0.0f0)

struct Space <: Plugin
    Space(;options...) = new()
end

posinit() = nullpos
posinit(scheduler, actor, actorid) = begin
    if isdefined(actor, :core) && pos(actor) != nullpos
        return pos(actor) # Predefined pos or migration
    end
    outpos = Ref(nullpos)
    actorpos = scheduler.hooks.spawnpos(scheduler, actor, outpos)
    return outpos[]
end
Plugins.customfield(::Space, ::Type{AbstractCoreState}) = Plugins.FieldSpec("pos", Pos, posinit)

infotoninit() = Infoton()
infotoninit(sender::AbstractActor, target, body, scheduler; energy = 1.0f0) = begin
    return Infoton(pos(sender), energy)
end
infotoninit(sender::Addr, target, body, scheduler; energy = 1.0f0) = Infoton() # Sourcepos not known, better to use zero energy

Plugins.customfield(::Space, ::Type{AbstractMsg}) = Plugins.FieldSpec("infoton", Infoton, infotoninit)

@inline localdelivery(space::Space, scheduler, msg, targetactor) = begin
    apply_infoton(targetactor, msg.infoton)
    return false
end

@inline actor_activity_sparse16(space::Space, scheduler, targetactor) = begin
    apply_infoton(targetactor, scheduler_infoton(scheduler, targetactor))
    return false
end

"""
    apply_infoton(targetactor::AbstractActor, infoton::Infoton)

An infoton acting on an actor.

Please check the source and the examples for more info.
"""
@inline @fastmath function apply_infoton(targetactor::AbstractActor, infoton::Infoton)
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

@inline @fastmath function scheduler_infoton(scheduler, actor::AbstractActor)
    diff = scheduler.pos - actor.core.pos
    distfromtarget = 2000 - norm(diff) # TODO configuration +easy redefinition from applications (including turning it off completely?)
    energy = sign(distfromtarget) * distfromtarget * distfromtarget * -2e-6
    return Infoton(scheduler.pos, energy)
end
