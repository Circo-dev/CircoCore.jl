# SPDX-License-Identifier: LGPL-3.0-only
import Base.show

struct NameQuery
    name::String
end

struct NameResponse
    query::NameQuery
    handler::Union{Address, Nothing}
end

struct LocalRegistry
    register::Dict{String, Address}
    LocalRegistry() = new(Dict())
end

struct RegisteredException <: Exception
    name::String
end
Base.show(io::IO, e::RegisteredException) = print(io, "name '", e.name, "' already registered")

function registername(service::LocalRegistry, name::String, handler::Address)
    haskey(service.register, name) && throw(RegisteredException(name))
    service.register[name] = handler
    return true
end

function getname(registry::LocalRegistry, name::String)
    get(registry.register, name, nothing)
end

function handle_special!(scheduler::AbstractActorScheduler, message::Message{NameQuery})
    send(scheduler.postoffice, Message(
            address(scheduler),
            sender(message),
            NameResponse(body(message), getname(scheduler.registry, body(message).name))
        ))
end