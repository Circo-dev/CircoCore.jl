# SPDX-License-Identifier: MPL-2.0
module Registry

using Plugins
using ..CircoCore

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

abstract type LocalRegistry <: Plugin end

mutable struct DefLocalRegistry <: LocalRegistry
    register::Dict{String, Addr}
    helperactor::RegistryHelper
    DefLocalRegistry(;options...) = new(Dict())
end
Plugins.symbol(::DefLocalRegistry) = :registry

function __init__()
    Plugins.register(DefLocalRegistry)
end

abstract type RegistryException end
struct RegisteredException <: RegistryException
    name::String
end
Base.show(io::IO, e::RegisteredException) = print(io, "name '", e.name, "' already registered")

struct NoRegistryException <: RegistryException
    msg::String
end

schedule_start(registry::DefLocalRegistry, scheduler) = begin
    registry.helperactor = RegistryHelper(registry, emptycore(scheduler.service))
    spawn(scheduler.service, registry.helperactor)
end

function registername(registry::DefLocalRegistry, name::String, handler::Addr)
    haskey(registry.register, name) && throw(RegisteredException(name))
    registry.register[name] = handler
    return true
end

function getname(registry::DefLocalRegistry, name::String)::Union{Addr, Nothing}
    get(registry.register, name, nothing)
end

specialmsg(registry::DefLocalRegistry, scheduler, message) = false
specialmsg(registry::DefLocalRegistry, scheduler, message::AbstractMsg{NameQuery}) = begin
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

end # module