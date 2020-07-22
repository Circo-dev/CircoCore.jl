using Plugins
using CircoCore

mutable struct MsgStats <: Plugin
    typefrequencies::Dict{DataType, Int}
    helper::Addr
    MsgStats() = begin
        return new(Dict())
    end
end

mutable struct MsgStatsHelper <: AbstractActor
    stats::MsgStats
    core::CoreState
    MsgStatsHelper(stats) = new(stats)
end

struct ResetStats a::UInt8 end
registermsg(ResetStats, ui=true)

CircoCore.monitorextra(actor::MsgStatsHelper) = (
    (; (Symbol(k) => v for (k,v) in actor.stats.typefrequencies)...)
)
    
CircoCore.symbol(::MsgStats) = :msgstats

Plugins.setup!(stats::MsgStats, scheduler) = begin
    helper = MsgStatsHelper(stats)
    stats.helper = spawn(scheduler, helper)
end

@inline function CircoCore.localdelivery(stats::MsgStats, scheduler, msg::CircoCore.Msg{T}, targetactor) where T
    current = get(stats.typefrequencies, T, nothing)
    if isnothing(current)
        stats.typefrequencies[T] = 1
        return false
    end
    stats.typefrequencies[T] = current + 1
    return false
end

CircoCore.onmessage(me::MsgStatsHelper, msg::ResetStats, service) = begin
    empty!(me.stats.typefrequencies)
end

# function Base.show(io::IO, stats::MsgStats)
#     Base.show(io, stats.typefrequencies)
# end
