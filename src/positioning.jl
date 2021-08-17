module Positioning
using Random
using Plugins
using ..CircoCore

const HOST_VIEW_SIZE = 1000 # TODO eliminate

mutable struct SimplePositioner <: CircoCore.Positioner
    isroot::Bool
    hostid::UInt64 # TODO: eliminate non-core notions
    center::Pos
    SimplePositioner(;options...) = new(
        length(get(options, :roots, [])) == 0 # TODO eliminate dirtiness
    )
end

__init__() = Plugins.register(SimplePositioner)

function randpos(rng = Random.GLOBAL_RNG)
    return Pos(
        rand(rng, Float32) * HOST_VIEW_SIZE - HOST_VIEW_SIZE / 2,
        rand(rng, Float32) * HOST_VIEW_SIZE - HOST_VIEW_SIZE / 2,
        rand(rng, Float32) * HOST_VIEW_SIZE - HOST_VIEW_SIZE / 2
    )
end

flat_gridpoints(grids) = Pos.(vec(collect(Iterators.product(grids...))))

function gridpos(idx)
    @assert idx < 17300 # This method may fail to generate unique values for higher idxes (and it is slow anyway).
    edge_length = floor(idx^(1/3)) / 2 + 1
    edge = -edge_length:edge_length
    points = sort(flat_gridpoints((edge, edge, edge)))
    return points[idx]
end

function hostrelative_schedulerpos(positioner, postcode)
    # return randpos()
    p = port(postcode)
    return gridpos(p - 24721 + 1) * HOST_VIEW_SIZE
end

function hostpos(positioner, postcode)
    if positioner.isroot
        return Pos(0, 0, 0)
    else
        rng = MersenneTwister(positioner.hostid)
        return randpos(rng) * 5.0
    end
end

function Plugins.setup!(p::SimplePositioner, scheduler)
    postoffice = get(scheduler.plugins, :postoffice, nothing)
    host = get(scheduler.plugins, :host, nothing)
    p.hostid = isnothing(host) ? 0 : host.hostid
    if isnothing(postoffice)
        p.center = nullpos
        scheduler.pos = randpos()
    else
        p.center = hostpos(p, postcode(postoffice))
        scheduler.pos = p.center + hostrelative_schedulerpos(p, postcode(postoffice))
    end
    return nothing
end

function CircoCore.spawnpos(p::SimplePositioner, scheduler, actor, result::Ref{Pos})
    result[] = randpos() + p.center
    return true
end

end
