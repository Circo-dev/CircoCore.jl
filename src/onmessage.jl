# SPDX-License-Identifier: LGPL-3.0-only

mutable struct OnMessage <: Plugin
    OnMessage(;options...) = new()
end

@inline localdelivery(plugins::OnMessage, scheduler, msg, targetactor) = begin
    onmessage(targetactor, body(msg), scheduler.service)
    return false
end
