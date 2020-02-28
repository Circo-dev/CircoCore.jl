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
    resultsholder_address::Address
    newaddress_selfreport::Union{Address, Nothing}
    newaddress_recepientmoved::Union{Address, Nothing}
    responsereceived::Integer
    address::Address
    Stayer(migrantaddress, resultsholder_address) = new(migrantaddress, resultsholder_address, nothing, nothing, 0)
end

struct Request
    responseto::Address
end

struct Response end

struct Results
    stayer::Stayer
end

mutable struct ResultsHolder <: AbstractActor
    results::Results
    address::Address
    ResultsHolder() = new()
end

mutable struct Migrant <: AbstractActor
    stayeraddress::Union{Address, Nothing}
    stayercopy::Union{Stayer, Nothing}
    address::Address
    Migrant() = new(nothing, nothing)
end
