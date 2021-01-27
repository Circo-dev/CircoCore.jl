module Profiles

import ..CircoCore

abstract type AbstractProfile end

function core_plugins end

struct EmptyProfile <: AbstractProfile
    options
    EmptyProfile(;options...) = new(options)
end

core_plugins(::EmptyProfile) = []

struct MinimalProfile <: AbstractProfile
    options
    MinimalProfile(;options...) = new(options)
end

core_plugins(profile::MinimalProfile) = [CircoCore.OnMessage]

struct TinyProfile <: AbstractProfile
    options
    TinyProfile(;options...) = new(options)
end

function core_plugins(profile::TinyProfile)
    options = profile.options
    return [
        CircoCore.Registry.LocalRegistry,
        CircoCore.ActivityService,
        CircoCore.Space,
        core_plugins(MinimalProfile(;options...))...,
    ]
end

struct DefaultProfile <: AbstractProfile
    options
    DefaultProfile(;options...) = new(options)
end

function core_plugins(profile::DefaultProfile)
    options = profile.options
    return [
        CircoCore.Positioning.Positioner,
        CircoCore.RemoteMessaging.PostOffice,
        core_plugins(TinyProfile(;options...))...,
    ]
end

end
