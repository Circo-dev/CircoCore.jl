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

function CircoContext(; options...)
    target_module = get(options, :target_module, Main)
    # Use :profilefn if provided, :profile otherwise
    directprofget = (;opts...) -> ((;opts...) -> get(() -> Profiles.DefaultProfile(;opts...), opts, :profile))
    profilefn = get(directprofget, options, :profilefn)
    profile = profilefn(;options...)
    userpluginsfn = get(() -> (() -> []), options, :userpluginsfn)
    plugins = instantiate_plugins(profile, userpluginsfn)
    types = generate_types(plugins; target_module)
    ctx = CircoContext(userpluginsfn, profile, plugins, options, types...)
    call_lifecycle_hook(ctx, prepare_hook)
    return ctx
end

Base.show(io::IO, ::MIME"text/plain", ctx::CircoContext) = begin
    print(io, "CircoContext with $(length(ctx.plugins)) plugins")
end

function instantiate_plugins(profile, userpluginsfn)
    userplugins = userpluginsfn()
    if !(userplugins isa AbstractArray) && !(userplugins isa Tuple)
        error("The userpluginsfn option of CircoContext should return a tuple or an array.")
    end
    allplugins = [userplugins..., Profiles.core_plugins(profile)...]
    return Plugins.PluginStack(allplugins, scheduler_hooks; profile.options...)
end

function instantiate_plugins(ctx::AbstractContext)
    return instantiate_plugins(ctx.profile, ctx.userpluginsfn)
end

function generate_types(pluginstack::Plugins.PluginStack; target_module=Main)
    return (
        corestate_type = Plugins.customtype(pluginstack, :CoreState, AbstractCoreState, Symbol[], target_module),
        msg_type = Plugins.customtype(pluginstack, :Msg, AbstractMsg, [:TBody], target_module),
    )
end

emptycore(ctx::AbstractContext) = ctx.corestate_type()
