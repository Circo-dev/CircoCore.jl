using CircoCore

include("remotesend-base.jl")

ctx = CircoContext()

function sendtoremote(receiveraddress)
    scheduler = ActorScheduler(ctx)
    println("Sending out $MESSAGE_COUNT messages")
    @time begin
        for i in 1:MESSAGE_COUNT
            deliver!(scheduler, Addr(receiveraddress), TestMessage(i, REMOTE_TEST_PAYLOAD))
        end
        scheduler(;exit_when_done = true)
    end
    println("Messages sent.")
    shutdown!(scheduler)
end
