# SPDX-License-Identifier: LGPL-3.0-only
using CircoCore

struct MigrateCommand
    topostcode::PostCode
    stayeraddress::Address
end

struct MigrateDone
    newaddress::Address
end

mutable struct Stayer <: AbstractActor
    oldmigrantaddress::Address
    newaddressbyselfreport::Union{Address, Nothing}
    newaddressbyrecepientmoved::Union{Address, Nothing}
    responsereceived::Integer
    address::Address
    Stayer(migrantaddress) = new(migrantaddress, nothing, nothing, 0)
end

struct Request
    responseto::Address
end
struct Response end
struct Results
    stayer::Stayer
end

mutable struct Migrant <: AbstractActor
    stayeraddress::Union{Address, Nothing}
    stayercopy::Union{Stayer, Nothing}
    address::Address
    Migrant() = new(nothing, nothing)
end
