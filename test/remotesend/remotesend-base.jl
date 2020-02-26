using CircoCore
import CircoCore.onmessage

REMOTE_TEST_PAYLOAD = "Sent remotely"
MESSAGE_COUNT = 10

struct TestMessage
    id::UInt64
    data::String
end
