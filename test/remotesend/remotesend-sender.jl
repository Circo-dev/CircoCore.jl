using CircoCore

include("remotesend-base.jl")

function sendtoremote(receiveraddress)
    po = PostOffice()
    source = Addr("", UInt64(0))
    println("Sending out $MESSAGE_COUNT messages")
    @time for i in 1:MESSAGE_COUNT
        message = Msg(source, Addr(receiveraddress), TestMessage(i, REMOTE_TEST_PAYLOAD))
        send(po, message)
        sleep(0.001)
    end
    println("Messages sent.")
    shutdown!(po)
end