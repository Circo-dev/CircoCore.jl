using Test
using CircoCore
import CircoCore.onmessage

include("remotesend-base.jl")

mutable struct Receiver <: AbstractActor
    messages::Array{TestMessage}
    address::Address
    Receiver() = new([])
end

function onmessage(me::Receiver, message::TestMessage, service)
    push!(me.messages, message)
    if length(me.messages) == MESSAGE_COUNT
        die(service, me)
    end
end

function startsender(receiverid)
    source = "include(\"test/remotesend/remotesend-sender.jl\");sendtoremote($receiverid)"
    run(Cmd(["julia", "--project", "-e", source]))
end

@testset "Remote Send" begin
    receiver = Receiver()
    scheduler = ActorScheduler([receiver])
    startsender(id(receiver))
    scheduler()
    @test receiver.messages[end].data == REMOTE_TEST_PAYLOAD
    @test receiver.messages[1].id == 1
    @test receiver.messages[end].id == MESSAGE_COUNT
    shutdown!(scheduler)
end