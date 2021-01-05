struct StoreKey
    key::ActorId
end

Base.hash(a::StoreKey, h::UInt) = xor(a.key, h)
Base.:(==)(a::StoreKey, b::StoreKey) = a.key == b.key

struct ActorStore{T}
    cache::Dict{StoreKey, T}
    ActorStore{T}(args...) where T = new{T}(Dict([map(p -> Pair(StoreKey(p.first), p.second), args)]...))
end
ActorStore(args...) = ActorStore{Any}(args...)

Base.getindex(s::ActorStore, key::ActorId) = s.cache[StoreKey(key)]
Base.setindex!(s::ActorStore, actor, key::ActorId) = s.cache[StoreKey(key)] = actor
Base.haskey(s::ActorStore, key::ActorId) = haskey(s.cache,StoreKey(key))
Base.get(s::ActorStore, key::ActorId, default) = get(s.cache, StoreKey(key), default)
Base.get(f::Function, s::ActorStore, key) = get(f, s.cache, StoreKey(key))
Base.delete!(s::ActorStore, key::ActorId) = delete!(s.cache, StoreKey(key))
Base.pop!(s::ActorStore, key::ActorId, default) = pop!(s.cache, StoreKey(key), default)
Base.length(s::ActorStore) = length(s.cache)
Base.iterate(s::ActorStore, state...) = begin
    inner = iterate(s.cache, state...)
    isnothing(inner) && return nothing
    return (Pair(inner[1][1].key, inner[1][2]), inner[2])
end
Base.values(s::ActorStore) = values(s.cache)
