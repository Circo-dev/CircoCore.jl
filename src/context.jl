"""
    CircoContext(;options...) <: AbstractContext

Store configuration and manage staging (code generation) for Circo.
"""
struct CircoContext <: AbstractContext
    userpluginsfn::Union{Nothing, Function}
    profile::Profiles.AbstractProfile
    plugins::Plugins.PluginStack
    options
    corestate_type::Type
    msg_type::Type
end

function CircoContext(;options...)
    profile = get(() -> Profiles.DefaultProfile(;options...), options, :profile)
    userpluginsfn = get(() -> (() -> []), options, :userpluginsfn)
    plugins = instantiate_plugins(profile, userpluginsfn)
    types = generate_types(plugins)
    ctx = CircoContext(userpluginsfn, profile, plugins, options, types...)
    call_lifecycle_hook(ctx, stage_hook)
    return ctx
end

function instantiate_plugins(profile, userpluginsfn)
    return Plugins.PluginStack([userpluginsfn()..., Profiles.core_plugins(profile)...], scheduler_hooks)
end

function instantiate_plugins(ctx::AbstractContext)
    return instantiate_plugins(ctx.profile, ctx.userpluginsfn)
end

function generate_types(pluginstack::Plugins.PluginStack)
    return (
        corestate_type = Plugins.customtype(pluginstack, :CoreState, AbstractCoreState, Symbol[], CircoCore),
        msg_type = Plugins.customtype(pluginstack, :Msg, AbstractMsg, [:TBody], CircoCore),
    )
end

emptycore(ctx::AbstractContext) = ctx.corestate_type()
