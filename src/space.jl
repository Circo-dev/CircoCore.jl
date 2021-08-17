# SPDX-License-Identifier: MPL-2.0

using LinearAlgebra

"""
    pos(a::Actor)::Pos

return the current position of the actor.

Call this on a spawned actor to get its position. Throws `UndefRefError` if the actor is not spawned.
"""
pos(a::Actor) = a.core.pos

"""
    Pos(x::Real, y::Real, z::Real)
    Pos(coords)

A point in the 3D "actor space".

You can access the coords by pos.x, pos.y, pos.z.
"""
struct Pos <: AbstractVector{Float32}
    coords::Tuple{Float32, Float32, Float32}
    Pos(x, y, z) = new((x, y, z))
    Pos(coords) = new(coords)
end

dist(a::Pos, b::Pos) = sqrt((a.coords[1]-b.coords[1])^2 + (a.coords[2]-b.coords[2])^2 + (a.coords[3]-b.coords[3])^2)
Base.isless(a::Pos, b::Pos) = norm(a) < norm(b)
Base.:*(a::Pos, x::Real) = Pos(a.coords[1] * x, a.coords[2] * x, a.coords[3] * x)
Base.:/(a::Pos, x::Real) = Pos(a.coords[1] / x, a.coords[2] / x, a.coords[3] / x)
Base.:+(a::Pos, b::Pos) = Pos(a.coords[1] + b.coords[1], a.coords[2] + b.coords[2], a.coords[3] + b.coords[3])
Base.:-(a::Pos, b::Pos) = Pos(a.coords[1] - b.coords[1], a.coords[2] - b.coords[2], a.coords[3] - b.coords[3])
Base.getindex(pos::Pos, i::Int) = getindex(pos.coords, i)
Base.getproperty(pos::Pos, symbol::Symbol) = (symbol == :x) ? getfield(pos, :coords)[1] :
                                        (symbol == :y) ? getfield(pos, :coords)[2] :
                                        (symbol == :z) ? getfield(pos, :coords)[3] :
                                        getfield(pos, symbol)
Base.iterate(pos::Pos) = iterate(pos.coords)
Base.iterate(pos::Pos, state) = iterate(pos.coords, state)
Base.length(pos::Pos) = length(pos.coords)
Base.size(pos::Pos) = 3

Base.show(io::IO, ::MIME"text/plain", pos::Pos) = begin
    print(io, "Pos($(pos[1]), $(pos[2]), $(pos[3]))")
end

nullpos = Pos(0, 0, 0)

struct EuclideanSpaceImpl <: EuclideanSpace # registered at CircoCore.__init__
    EuclideanSpaceImpl(;options...) = new()
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
