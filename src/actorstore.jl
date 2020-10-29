struct StoreKey
    key::ActorId
end

Base.hash(a::StoreKey, h::UInt) = xor(a.key, h)
Base.:(==)(a::StoreKey, b::StoreKey) = a.key == b.key

struct ActorStore
    cache::Dict{StoreKey, Any}
    ActorStore(args...) = new(Dict([map(p -> Pair(StoreKey(p.first), p.second), args)]...))
end

Base.getindex(s::ActorStore, key::ActorId) = s.cache[StoreKey(key)]
Base.setindex!(s::ActorStore, actor, key::ActorId) = s.cache[StoreKey(key)] = actor
Base.haskey(s::ActorStore, key::ActorId) = haskey(s.cache,StoreKey(key))
Base.get(s::ActorStore, key::ActorId, default) = get(s.cache, StoreKey(key), default)
Base.delete!(s::ActorStore, key::ActorId) = delete!(s.cache, StoreKey(key))
Base.length(s::ActorStore) = length(s.cache)
Base.iterate(s::ActorStore, state...) = begin
    inner = iterate(s.cache, state...)
    isnothing(inner) && return nothing
    return (Pair(inner[1][1].key, inner[1][2]), inner[2])
end
Base.values(s::ActorStore) = values(s.cache)
