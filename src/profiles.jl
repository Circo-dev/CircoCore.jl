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

core_plugins(profile::MinimalProfile) = [CircoCore.OnMessage(;profile.options...)]

struct TinyProfile <: AbstractProfile
    options
    TinyProfile(;options...) = new(options)
end

function core_plugins(profile::TinyProfile)
    options = profile.options
    return [
        core_plugins(MinimalProfile(;options...))...,
        CircoCore.LocalRegistry(;options...),
        CircoCore.ActivityService(;options...),
        CircoCore.Space(;options...)
    ]
end

struct DefaultProfile <: AbstractProfile
    options
    DefaultProfile(;options...) = new(options)
end

function core_plugins(profile::DefaultProfile)
    options = profile.options
    return [
        core_plugins(TinyProfile(;options...))...,
        CircoCore.PostOffice(;options...),
        CircoCore.Positioning.BasicPositioner(;options...)
    ]
end

end