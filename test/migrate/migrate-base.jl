using CircoCore

struct MigrateCommand
    topostcode::PostCode
end

mutable struct Migrant <: AbstractActor
    address::Address
    Migrant() = new()
end
