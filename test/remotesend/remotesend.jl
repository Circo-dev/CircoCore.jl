using Test
using CircoCore
import CircoCore.onmessage

include("remotesend-base.jl")

mutable struct Receiver{TCore} <: AbstractActor{TCore}
    messages::Array{TestMessage}
    core::TCore
end
Receiver(core) = Receiver(TestMessage[], core)

function onmessage(me::Receiver, message::TestMessage, service)
    push!(me.messages, message)
    if length(me.messages) >= MESSAGE_COUNT
        die(service, me)
    end
end

function startsender(receiveraddress)
    prefix = endswith(pwd(), "test") ? "" : "test/"
    source = "include(\"$(prefix)remotesend/remotesend-sender.jl\");sendtoremote(\"$receiveraddress\")"
    run(pipeline(Cmd(["julia", "--project", "-e", source]);stdout=stdout,stderr=stderr);wait=false)
end

@testset "Remote Send" begin
    ctx = CircoContext()
    receiver = Receiver(emptycore(ctx))
    scheduler = ActorScheduler(ctx, [receiver])
    sender = startsender(addr(receiver))
    scheduler(;exit=true)
    wait(sender) # Do not print test results before sender exit logs
    @test length(receiver.messages) == MESSAGE_COUNT
    @test receiver.messages[end].data == REMOTE_TEST_PAYLOAD
    @test receiver.messages[1].id == 1
    #@test receiver.messages[end].id == MESSAGE_COUNT
    shutdown!(scheduler)
end
