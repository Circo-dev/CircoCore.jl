using CircoCore

include("remotesend-base.jl")

function sendtoremote(receiveraddress)
    po = PostOffice()
    source = Address("", UInt64(0))
    println("Sending out $MESSAGE_COUNT messages")
    @time for i in 1:MESSAGE_COUNT
        message = Message(source, Address(receiveraddress), TestMessage(i, REMOTE_TEST_PAYLOAD))
        send(po, message)
        sleep(0.001)
    end
    println("Messages sent.")
    shutdown!(po)
end