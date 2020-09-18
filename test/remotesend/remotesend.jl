using Test
using CircoCore
import CircoCore.onmessage

include("remotesend-base.jl")

mutable struct Receiver <: AbstractActor{TCoreState}
    messages::Array{TestMessage}
    core::CoreState
    Receiver() = new([])
end

function onmessage(me::Receiver, message::TestMessage, service)
    push!(me.messages, message)
    if length(me.messages) >= MESSAGE_COUNT
        die(service, me)
    end
end

function startsender(receiveraddress)
    source = "include(\"remotesend/remotesend-sender.jl\");sendtoremote(\"$receiveraddress\")"
    run(pipeline(Cmd(["julia", "--project", "-e", source]);stdout=stdout,stderr=stderr);wait=false)
end

@testset "Remote Send" begin
    ctx = CircoContext()
    receiver = Receiver()
    scheduler = ActorScheduler(ctx, [receiver])
    sender = startsender(addr(receiver))
    scheduler(;exit_when_done=true)
    wait(sender) # Do not print test results before sender exit logs
    @test length(receiver.messages) == MESSAGE_COUNT
    @test receiver.messages[end].data == REMOTE_TEST_PAYLOAD
    @test receiver.messages[1].id == 1
    @test receiver.messages[end].id == MESSAGE_COUNT
    shutdown!(scheduler)
end
