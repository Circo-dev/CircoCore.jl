# SPDX-License-Identifier: LGPL-3.0-only
import Base.show

struct NameQuery
    name::String
end

struct NameResponse
    query::NameQuery
    handler::Union{Addr, Nothing}
end

struct LocalRegistry
    register::Dict{String, Addr}
    LocalRegistry() = new(Dict())
end

struct RegisteredException <: Exception
    name::String
end
Base.show(io::IO, e::RegisteredException) = print(io, "name '", e.name, "' already registered")

function registername(service::LocalRegistry, name::String, handler::Addr)
    haskey(service.register, name) && throw(RegisteredException(name))
    service.register[name] = handler
    return true
end

function getname(registry::LocalRegistry, name::String)
    get(registry.register, name, nothing)
end

function handle_special!(scheduler::AbstractActorScheduler, message::Msg{NameQuery})
    send(scheduler.postoffice, Msg(
            address(scheduler),
            sender(message),
            NameResponse(body(message), getname(scheduler.registry, body(message).name))
        ))
end