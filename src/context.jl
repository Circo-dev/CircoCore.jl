# SPDX-License-Identifier: MPL-2.0

"""
    CircoContext(;options...) <: AbstractContext

Store configuration, manage staging and run-time code optimizations for Circo.
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
    directprofget = (;options...) -> ((;options...) -> get(() -> Profiles.DefaultProfile(;options...), options, :profile))
    profilefn = get(directprofget, options, :profilefn) # Use :profilefn is provided, :profile otherwise
    profile = profilefn(;options...)
    userpluginsfn = get(() -> (() -> []), options, :userpluginsfn)
    plugins = instantiate_plugins(profile, userpluginsfn)
    types = generate_types(plugins)
    ctx = CircoContext(userpluginsfn, profile, plugins, options, types...)
    call_lifecycle_hook(ctx, prepare_hook)
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
