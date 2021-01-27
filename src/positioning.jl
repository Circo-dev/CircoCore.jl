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

function hostrelative_schedulerpos(positioner, postcode)
    # return randpos()
    p = port(postcode)
    p == 24721 && return Pos(-1, 0, 0) * HOST_VIEW_SIZE
    p == 24722 && return Pos(1, 0, 0) * HOST_VIEW_SIZE
    p == 24723 && return Pos(0, -1, 0) * HOST_VIEW_SIZE
    p == 24724 && return Pos(0, 1, 0) * HOST_VIEW_SIZE
    p == 24725 && return Pos(0, 0, -1) * HOST_VIEW_SIZE
    p == 24726 && return Pos(0, 0, 1) * HOST_VIEW_SIZE
    return randpos()
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
