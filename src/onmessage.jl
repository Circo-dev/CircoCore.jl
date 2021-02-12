# SPDX-License-Identifier: MPL-2.0

abstract type OnMessage <: Delivery end
mutable struct OnMessageImpl <: OnMessage
    OnMessageImpl(;options...) = new()
end

@inline localdelivery(::OnMessage, scheduler, msg, targetactor) = begin
    onmessage(targetactor, body(msg), scheduler.service)
    return false
end
