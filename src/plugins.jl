# SPDX-License-Identifier: LGPL-3.0-only

import Base.getindex, Base.get

abstract type Plugin end

# Plugin interface
localroutes(plugin::Plugin) = nothing
infotonhandler(plugin::Plugin) = nothing
symbol(plugin::Plugin) = :nothing
setup!(plugin::Plugin, scheduler) = nothing
shutdown!(plugin::Plugin) = nothing

struct LocalRoute
    routerfn::Function
    plugin::Plugin
end

struct InfotonHandler
    handlerfn::Function
    plugin::Plugin
end

struct Plugins
    plugins::Dict{Symbol, Plugin}
    localroutes::Array{LocalRoute}
    infotonhandlers::Array{InfotonHandler}
end

function Plugins(plugins::AbstractArray)
    return Plugins(plugin_dict(plugins), localroutes(plugins), infotonhandlers(plugins))
end

plugin_dict(plugins) = Dict{Symbol, Plugin}([(symbol(plugin), plugin) for plugin in plugins])
getindex(p::Plugins, idx) = getindex(p.plugins, idx)
get(p::Plugins, idx, def) = get(p.plugins, idx, def)

localroutes(plugins::AbstractArray) = [LocalRoute(localroutes(plugin), plugin) for plugin in plugins if !isnothing(localroutes(plugin))]
infotonhandlers(plugins::AbstractArray) = [InfotonHandler(infotonhandler(plugin), plugin) for plugin in plugins if !isnothing(infotonhandler(plugin))]

@inline function route_locally(plugins::Plugins, scheduler::AbstractActorScheduler, message::AbstractMsg)
    for route in plugins.localroutes
        if route.routerfn(route.plugin, scheduler, message)
            return true
        end
    end
    return false
    
end

@inline function apply_infoton(plugins::Plugins, scheduler::AbstractActorScheduler, targetactor::AbstractActor, infoton::Infoton)
    for handler in plugins.infotonhandlers
        handler.handlerfn(handler.plugin, scheduler, targetactor, infoton)
    end
    return nothing
end

setup!(plugins::Plugins, scheduler) = for plugin in values(plugins.plugins) setup!(plugin, scheduler) end
shutdown!(plugins::Plugins) = shutdown!.(values(plugins.plugins))
