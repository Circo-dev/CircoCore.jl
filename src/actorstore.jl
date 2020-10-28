struct StoreKey
    key::ActorId
end

Base.hash(a::StoreKey, h::UInt) = xor(a.key, h)
Base.:(==)(a::StoreKey, b::StoreKey) = a.key == b.key

struct ActorStore
    cache::Dict{StoreKey, Any}
    ActorStore() = new(Dict())
end

Base.getindex(s::ActorStore, key::ActorId) = s.cache[StoreKey(key)]
Base.setindex!(s::ActorStore, actor, key::ActorId) = s.cache[StoreKey(key)] = actor
Base.haskey(s::ActorStore, key::ActorId) = haskey(s.cache,StoreKey(key))
Base.get(s::ActorStore, key::ActorId, default) = get(s.cache, StoreKey(key), default)
Base.delete!(s::ActorStore, key::ActorId) = delete!(s.cache, StoreKey(key))
Base.length(s::ActorStore) = length(s.cache)