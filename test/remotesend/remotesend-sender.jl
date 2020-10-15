using CircoCore

include("remotesend-base.jl")

ctx = CircoContext()

function sendtoremote(receiveraddress)
    scheduler = Scheduler(ctx)
    println("Sending out $MESSAGE_COUNT messages")
    @time begin
        sentout = 0
        while sentout < MESSAGE_COUNT
            for i in 1:min(100, MESSAGE_COUNT - sentout)
                send(scheduler, Addr(receiveraddress), TestMessage(i, REMOTE_TEST_PAYLOAD))
                sentout += 1
            end
            scheduler(;exit = true)
            sleep(0.1)
        end
    end
    println("Messages sent.")
    shutdown!(scheduler)
end
