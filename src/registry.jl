# SPDX-License-Identifier: MPL-2.0
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

mutable struct RegistryHelper{TCore} <: Actor{TCore}
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

schedule_start(registry::LocalRegistry, scheduler) = begin
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

specialmsg(registry::LocalRegistry, scheduler, message) = false
specialmsg(registry::LocalRegistry, scheduler, message::AbstractMsg{NameQuery}) = begin
    @debug "Registry specialmsg $message"
    send(scheduler.service,
        registry.helperactor,
        sender(message),
        NameResponse(body(message),
            getname(registry, body(message).name),
            body(message).token)
        )
    return true
end
