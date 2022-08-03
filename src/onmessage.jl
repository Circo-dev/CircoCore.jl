# SPDX-License-Identifier: MPL-2.0

abstract type OnMessage <: Delivery end
mutable struct OnMessageImpl <: OnMessage
    OnMessageImpl(;options...) = new()
end

@inline localdelivery(::OnMessage, scheduler, msg, targetactor) = begin
    _body = body(msg)
    _service = scheduler.service
    for trait in traits(typeof(targetactor))
        onmessage(trait isa Type ? trait() : trait, targetactor, _body, _service)
    end
    onmessage(targetactor, body(msg), scheduler.service)
    return false
end

"""
    traits(::Type{<:Actor}) = ()

You can declare the traits of an actor by defining a method of this function.

Traits can handle messages in the name of the actor,
helping to compose the behavior of the actor (See [`ontraitmessage()`](@ref).).
Return a tuple of traits, either instantiated or not.
Instantiated traits can hold values, while
traits given as types will be instantiated without arguments.

E.g.: The EventSource trait handles the Subscribe and UnSubscribe messages automatically (among others).

Anything can be a trait, but we recommend to use immutable structs.

Important: Traits _cannot_ hold state. If a trait needs to store state in the actor you have to add fields to the actor manually.

# Examples



"""
traits(::Type{<:Actor}) = ()

ontraitmessage(trait, me, msg, service) = nothing
