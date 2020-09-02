module Profiles

import ..CircoCore

abstract type AbstractProfile end

function core_plugins end

struct EmptyProfile <: AbstractProfile
    options
    EmptyProfile(;options...) = new(options)
end

function core_plugins(profile::EmptyProfile)
    return []
end

struct MinimalProfile <: AbstractProfile
    options
    MinimalProfile(;options...) = new(options)
end

function core_plugins(profile::MinimalProfile)
    options = profile.options
    return [
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
        core_plugins(MinimalProfile(;options...))...,
        CircoCore.PostOffice(;options...)
    ]
end

end
