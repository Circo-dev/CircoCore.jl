# SPDX-License-Identifier: MPL-2.0

mutable struct OnMessage <: Plugin
    OnMessage(;options...) = new()
end

Plugins.symbol(::OnMessage) = :delivery

@inline localdelivery(plugins::OnMessage, scheduler, msg, targetactor) = begin
    onmessage(targetactor, body(msg), scheduler.service)
    return false
end
