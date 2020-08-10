# SPDX-License-Identifier: LGPL-3.0-only
using Serialization
using Sockets
using DataStructures

const PORT_RANGE = 24721:24999

struct PostException
    message::String
end

mutable struct PostOffice <: Plugin
    outsocket::UDPSocket
    inqueue::Deque{Any}
    postcode::PostCode
    socket::UDPSocket
    stopped::Bool
    intask
    PostOffice() = begin
        postcode, socket = allocate_postcode()    
        return new(UDPSocket(), Deque{Any}(), postcode, socket, false)
    end
end

Plugins.symbol(plugin::PostOffice) = :postoffice

postcode(post::PostOffice) = post.postcode
addr(post::PostOffice) = Addr(postcode(post), 0)

function allocate_postcode()
    socket = UDPSocket()
    ipaddr = Sockets.getipaddr()
    for port in PORT_RANGE
        postcode = "$(ipaddr):$port"
        bound = bind(socket, ipaddr, port)
        bound || continue
        @debug "Bound to $postcode"
        return postcode, socket
    end
    throw(PostException("No available port found for a Post Office"))
end

function schedule_start(post::PostOffice, scheduler) # called directly for now
    post.intask = @async arrivals(post) # TODO errors throwed here are not logged
end

function schedule_stop(post::PostOffice, scheduler)
    post.stopped = true
    yield()
end

function shutdown!(post::PostOffice)
    close(post.socket)
end

function letin_remote(post::PostOffice, scheduler::AbstractActorScheduler)::Bool
    for i = 1:min(length(post.inqueue), 30)
        deliver!(scheduler, popfirst!(post.inqueue)) 
    end
    return false
end

function arrivals(post::PostOffice)
    try
        while !post.stopped 
            rawmessage = recv(post.socket) # TODO: this blocks, so we will only exit if an extra message comes in after stopping
            stream = IOBuffer(rawmessage)
            msg = deserialize(stream)
            @debug "Postoffice got message $msg"
            push!(post.inqueue, msg)
        end
    catch e
        if !(e isa EOFError)
            @info "Exception in arrivals", e
        end
    end
end

@inline function send(post::PostOffice, message)
    @debug "PostOffice delivery at $(postcode(post)): $message"
    parts = split(postcode(target(message)), ":")
    ip = parse(IPAddr, parts[1])
    port = parse(UInt16, parts[2])
    io = IOBuffer()
    serialize(io, message)
    Sockets.send(post.outsocket, ip, port, take!(io))
end