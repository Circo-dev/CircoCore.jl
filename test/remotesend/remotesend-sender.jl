using CircoCore

include("remotesend-base.jl")

function sendtoremote(receiverid)
    po = PostOffice()
    source = Address("", UInt64(0))
    target = Address("tcp://localhost:24721", UInt64(receiverid))
    for i in 1:MESSAGE_COUNT
        message = Message{TestMessage}(source, target, TestMessage(i, REMOTE_TEST_PAYLOAD))
        send(po, message)
    end
    shutdown!(po)
end