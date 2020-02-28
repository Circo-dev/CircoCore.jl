using CircoCore

include("remotesend-base.jl")

function sendtoremote(receiveraddress)
    po = PostOffice()
    source = Address("", UInt64(0))
    for i in 1:MESSAGE_COUNT
        message = Message{TestMessage}(source, receiveraddress, TestMessage(i, REMOTE_TEST_PAYLOAD))
        send(po, message)
    end
    shutdown!(po)
end