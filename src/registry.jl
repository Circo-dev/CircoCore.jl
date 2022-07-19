# SPDX-License-Identifier: MPL-2.0

# Local, in-scheduler registry that can be queried from the outside
module Registry

using Plugins
using ..CircoCore

export NameQuery, NameResponse

"""
    NameQuery(name::String) <: Request

A query that can be sent to a remote scheduler for querying its local registry.
"""
struct NameQuery <: Request # TODO add respondto
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

mutable struct LocalRegistryImpl <: CircoCore.LocalRegistry
    register::Dict{String, Addr}
    helperactor::RegistryHelper
    LocalRegistryImpl(;options...) = new(Dict())
end
__init__() = Plugins.register(LocalRegistryImpl)

abstract type RegistryException end
struct RegisteredException <: RegistryException
    name::String
end
Base.show(io::IO, e::RegisteredException) = print(io, "name '", e.name, "' already registered")

struct NoRegistryException <: RegistryException
    msg::String
end

CircoCore.schedule_start(registry::LocalRegistryImpl, scheduler) = begin
    registry.helperactor = RegistryHelper(registry, emptycore(scheduler.service))
    spawn(scheduler, registry.helperactor)
end

function CircoCore.registername(registry::LocalRegistryImpl, name::String, handler::Addr, initiator::Union{Addr,Nothing}=nothing)
    if !isnothing(initiator) && initiator != handler
        if haskey(registry.register, name)
            throw(RegisteredException(name))
        end
        @info "Registering name $name to $handler by another actor: $(addr(initiator_actor))"
    end
    registry.register[name] = handler
    return true
end

function CircoCore.getname(registry::LocalRegistryImpl, name::String)::Union{Addr, Nothing}
    get(registry.register, name, nothing)
end

CircoCore.specialmsg(registry::LocalRegistryImpl, scheduler, message) = false
CircoCore.specialmsg(registry::LocalRegistryImpl, scheduler, message::AbstractMsg{NameQuery}) = begin
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