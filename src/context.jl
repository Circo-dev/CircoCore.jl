struct CircoContext <: AbstractContext
    userpluginsfn::Union{Nothing, Function}
    profile::Profiles.AbstractProfile
    options
    corestate_type::DataType
end

function CircoContext(;options...)
    profile = get(() -> Profiles.DefaultProfile(;options...), options, :profile)
    userpluginsfn = get(() -> (() -> []), options, :userpluginsfn)
    plugins = instantiate_plugins(profile, userpluginsfn)
    types = generate_types(plugins)
    return CircoContext(userpluginsfn, profile, options, types.corestate_type)
end

function instantiate_plugins(profile, userpluginsfn)
    return Plugins.PluginStack([userpluginsfn()..., Profiles.core_plugins(profile)...], scheduler_hooks)
end

function instantiate_plugins(ctx::AbstractContext)
    return instantiate_plugins(ctx.profile, ctx.userpluginsfn)
end

function generate_types(pluginstack::Plugins.PluginStack)
    return (corestate_type = Plugins.customtype(pluginstack, :CoreState, AbstractCoreState),)
end

emptycore(ctx::AbstractContext) = ctx.corestate_type()
