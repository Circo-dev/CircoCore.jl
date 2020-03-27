# SPDX-License-Identifier: LGPL-3.0-only

import Base.getindex, Base.get

struct Plugins
    plugins::Dict{Symbol, SchedulerPlugin}
    localroutes::Array{Function}
end

function Plugins(plugins::AbstractArray)
    return Plugins(plugin_dict(plugins), localroutes(plugins))
end

plugin_dict(plugins) = Dict{Symbol, SchedulerPlugin}([(symbol(plugin), plugin) for plugin in plugins])
getindex(p::Plugins, idx) = getindex(p.plugins, idx)
get(p::Plugins, idx, def) = get(p.plugins, idx, def)

localroutes(plugins::AbstractArray) = [localroutes(plugin) for plugin in plugins if !isnothing(localroutes(plugin))]

@inline function route_locally(plugins::Plugins, scheduler::AbstractActorScheduler, message::AbstractMessage)
    for route in plugins.localroutes
        if route(scheduler, message)
            return true
        end
    end
    return false
    
end