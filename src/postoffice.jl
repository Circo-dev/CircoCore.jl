# SPDX-License-Identifier: LGPL-3.0-only
using ZMQ
using Serialization, Sockets

const PORT_RANGE = 24721:24999

struct PostException
    message::String
end

struct PostOffice
    outsockets::Dict{PostCode, Socket}
    postcode::PostCode
    socket::Socket
end
PostOffice() = PostOffice(Dict{PostCode, Socket}(), allocate_postcode()...)

postcode(post::PostOffice) = post.postcode

function allocate_postcode()
    socket = Socket(PULL)
    for port in PORT_RANGE
        try
            buf = IOBuffer()
            print(buf, Sockets.getipaddr())
            ipstr = String(take!(buf))
            postcode = "tcp://$(ipstr):$port"
            bind(socket, postcode)
            println("Bound to $postcode")
            return postcode, socket
        catch e
            isa(e, StateError) || rethrow()
        end
    end
    throw(PostException("No available port found for a Post Office"))
end

function shutdown!(post::PostOffice)
    close(post.socket)
    for socket in values(post.outsockets)
        close(socket)
    end
end

function getmessage(post::PostOffice)
    message = recv(post.socket)
    stream = convert(IOStream, message)
    seek(stream, 0)
    return deserialize(stream)
end

function createsocket!(post::PostOffice, targetpostcode::PostCode)
    socket = ZMQ.Socket(ZMQ.PUSH)
    connect(socket, targetpostcode)
    post.outsockets[targetpostcode] = socket
    return socket
end
createsocket!(post::PostOffice, target::Address) = createsocket!(post, postcode(target))

function getsocket(post::PostOffice, target::Address)
    socket = get(post.outsockets, postcode(target), nothing)
    if isnothing(socket)
        return createsocket!(post, target)
    end
    return socket
end

function send(post::PostOffice, message)
    socket = getsocket(post, target(message))
    io = IOBuffer()
    serialize(io, message)
    ZMQ.send(socket, ZMQ.Message(io))
end