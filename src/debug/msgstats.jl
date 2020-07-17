using Plugins

struct MsgStats <: Plugin
    typefrequencies::Dict{DataType, Int}
    MsgStats() = new(Dict())
end

symbol(::MsgStats) = :msgstats

@inline function CircoCore.localdelivery(stats::MsgStats, scheduler, msg::CircoCore.Msg{T}, targetactor) where T
    current = get(stats.typefrequencies, T, nothing)
    if isnothing(current)
        stats.typefrequencies[T] = 1
        return false
    end
    stats.typefrequencies[T] = current + 1
    return false
end

# function Base.show(io::IO, stats::MsgStats)
#     Base.show(io, stats.typefrequencies)
# end
