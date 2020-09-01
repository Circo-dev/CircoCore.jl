module Profiles

import ..CircoCore

abstract type AbstractProfile end

function core_plugins end

struct EmptyProfile <: AbstractProfile
    options
    EmptyProfile(options = NamedTuple()) = new(options)
end

function core_plugins(profile::EmptyProfile)
    return []
end

struct MinimalProfile <: AbstractProfile
    options
    MinimalProfile(options = NamedTuple()) = new(options)
end

function core_plugins(profile::MinimalProfile)
    return [
        CircoCore.LocalRegistry(;options = profile.options),
        CircoCore.ActivityService(;options = profile.options),
        CircoCore.Space(;options = profile.options)
    ]
end

struct DefaultProfile <: AbstractProfile
    options
    DefaultProfile(options = NamedTuple()) = new(options)
end

function core_plugins(profile::DefaultProfile)
    return [
        core_plugins(MinimalProfile(profile.options))...,
        CircoCore.PostOffice(;options = profile.options)
    ]
end

end
