# SPDX-License-Identifier: LGPL-3.0-only
using CircoCore

struct MigrateCommand
    topostcode::PostCode
end

mutable struct Migrant <: AbstractActor
    data::Int
    address::Address
    Migrant() = new(42)
end
