# SPDX-License-Identifier: LGPL-3.0-only
using CircoCore

struct MigrateCommand
    topostcode::PostCode
    stayeraddress::Addr
end

struct MigrateDone
    newaddress::Addr
end

mutable struct Stayer <: AbstractActor
    oldmigrantaddress::Addr
    resultsholder_address::Addr
    responsereceived::Integer
    newaddress_selfreport::Addr
    newaddress_recepientmoved::Addr
    addr::Addr
    Stayer(migrantaddress, resultsholder_address) = new(migrantaddress, resultsholder_address, 0)
end

struct SimpleRequest
    responseto::Addr
end

struct SimpleResponse end

struct Results
    stayer::Stayer
end

mutable struct ResultsHolder <: AbstractActor
    results::Results
    addr::Addr
    ResultsHolder() = new()
end

mutable struct Migrant <: AbstractActor
    stayeraddress::Addr
    addr::Addr
    Migrant() = new()
end
