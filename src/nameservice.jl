# SPDX-License-Identifier: LGPL-3.0-only
import Base.show

struct NameQuery
    name::String
end

struct NameResponse
    query::NameQuery
    handler::Union{Address, Nothing}
end

struct NameService
    register::Dict{String, Address}
    NameService() = new(Dict())
end

struct RegisteredException <: Exception
    name::String
end
Base.show(io::IO, e::RegisteredException) = print(io, "name '", e.name, "' already registered")

function registername(service::NameService, name::String, handler::Address)
    haskey(service.register, name) && throw(RegisteredException(name))
    service.register[name] = handler
    return true
end

function handle_special!(scheduler::AbstractActorScheduler, message::Message{NameQuery})
    send(scheduler.postoffice, Message(
            address(scheduler),
            sender(message),
            NameResponse(body(message), get(scheduler.nameservice.register, body(message).name, nothing))
        ))
end