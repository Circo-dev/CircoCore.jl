# SPDX-License-Identifier: LGPL-3.0-only
# Sample circo.jl showing a minimal CircoCore application

using CircoCore
import CircoCore.onmessage
import CircoCore.onschedule

mutable struct SampleActor <: AbstractActor
    address::Address
    SampleActor() = new()
end

struct SampleMessage
    message::String
end

function onschedule(me::SampleActor, service)
    cluster = getname(service, "cluster")
    println("SampleActor scheduled on cluster: $cluster Sending a message to myself.")
    send(service, me, address(me), SampleMessage("This is a message from $(address(me))"))
end

function onmessage(me::SampleActor, message::SampleMessage, service)
    println("Got SampleMessage: '$(message.message)'")
end

zygote() = SampleActor()