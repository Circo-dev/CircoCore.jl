# SPDX-License-Identifier: LGPL-3.0-only
module Queries
using ..CircoCore

abstract type AbstractQuery end
abstract type AbstractQueryService end

struct TypeQuery{T}
    query::T
end

struct NameQuery <: AbstractQuery
    query::String
end

struct NameService <: AbstractQueryService
    register::Dict{String, Address}
    NameService() = new(Dict())
end

struct NameRegRequest
    name::String
    handler::Address
end

struct NameRegResponse
    request::NameRegRequest
    accepted::Bool
end

struct NameUnregNotification
    port::Type
end

end