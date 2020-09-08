module Positioning
using Plugins
using ..CircoCore

const HOST_VIEW_SIZE = 1000 # TODO eliminate

function randpos()
    return Pos(
        rand(Float32) * HOST_VIEW_SIZE - HOST_VIEW_SIZE / 2,
        rand(Float32) * HOST_VIEW_SIZE - HOST_VIEW_SIZE / 2,
        rand(Float32) * HOST_VIEW_SIZE - HOST_VIEW_SIZE / 2
    )
end

mutable struct BasicPositioner <: Plugin
    isroot::Bool
    center::Pos
    BasicPositioner(;options...) = new(length(get(options, :roots, [])) == 0) # TODO eliminate dirtiness
end

function hostrelative_pos(positioner, postcode)
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
        return randpos() * 5.0
    end
end

function getpos(positioner, postcode)
    return hostpos(positioner, postcode) + hostrelative_pos(positioner, postcode)
end

function Plugins.setup!(p::BasicPositioner, scheduler)
    postoffice = get(scheduler.plugins, :postoffice, nothing)
    if isnothing(postoffice)
        scheduler.pos = randpos()
    else
        p.center = getpos(p, postcode(postoffice))
        scheduler.pos = p.center
    end
    return nothing
end

function CircoCore.spawnpos(p::BasicPositioner, scheduler, actor, result::Ref{Pos})
    result[] = randpos()
    return true
end

end
