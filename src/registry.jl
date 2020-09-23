# SPDX-License-Identifier: LGPL-3.0-only
import Base.show

"""
    NameQuery(name::String) <: Request

A query that can be sent to a remote scheduler for querying its local registry.
"""
struct NameQuery <: Request
    name::String
    token::Token
    NameQuery(name, token) = new(name, token)
    NameQuery(name) = new(name, Token())
end

struct NameResponse <: Response
    query::NameQuery
    handler::Union{Addr, Nothing}
    token::Token
end

mutable struct RegistryHelper{TCore} <: AbstractActor{TCore}
    registry::Any
    core::TCore
end

mutable struct LocalRegistry <: Plugin
    register::Dict{String, Addr}
    helperactor::RegistryHelper
    LocalRegistry(;options...) = new(Dict())
end
Plugins.symbol(::LocalRegistry) = :registry

abstract type RegistryException end
struct RegisteredException <: RegistryException
    name::String
end
Base.show(io::IO, e::RegisteredException) = print(io, "name '", e.name, "' already registered")

struct NoRegistryException <: RegistryException
    msg::String
end

function Plugins.setup!(registry::LocalRegistry, scheduler)
    registry.helperactor = RegistryHelper(registry, emptycore(scheduler.service))
    spawn(scheduler.service, registry.helperactor)
end

function registername(registry::LocalRegistry, name::String, handler::Addr)
    haskey(registry.register, name) && throw(RegisteredException(name))
    registry.register[name] = handler
    return true
end

function getname(registry::LocalRegistry, name::String)::Union{Addr, Nothing}
    get(registry.register, name, nothing)
end

function handle_special!(scheduler::AbstractActorScheduler, message::AbstractMsg{NameQuery})
    @debug "Registry handle_special! $message"

    registry = get(scheduler.plugins, :registry, nothing)
    if isnothing(registry)
        @info "Registry plugin not found, dropping message $message"
        return nothing
    end
    registry::LocalRegistry
    send(scheduler.service,
        registry.helperactor,
        sender(message),
        NameResponse(body(message),
            getname(registry, body(message).name),
            body(message).token)
        )
    return nothing
end
