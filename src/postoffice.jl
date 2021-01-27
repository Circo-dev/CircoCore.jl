# SPDX-License-Identifier: MPL-2.0
module UDPPostOffice_

using Plugins
using ..CircoCore
import ..CircoCore: AbstractCoreState

using Serialization
using Sockets
using DataStructures

const PORT_RANGE = 24721:24999

struct PostException
    message::String
end

mutable struct UDPPostOffice <: CircoCore.PostOffice
    outsocket::UDPSocket
    inqueue::Deque{Any}
    stopped::Bool
    postcode::PostCode
    socket::UDPSocket
    intask
    UDPPostOffice(;options...) = begin
        return new(UDPSocket(), Deque{Any}(), false)
    end
end

__init__() = Plugins.register(UDPPostOffice)

addrinit() = nulladdr
addrinit(scheduler, actor, actorid) = Addr(postcode(scheduler.plugins[:postoffice]), actorid)
Plugins.customfield(::PostOffice, ::Type{AbstractCoreState}) = Plugins.FieldSpec("addr", Addr, addrinit)

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

Plugins.setup!(post::UDPPostOffice, scheduler) = begin
    postcode, socket = allocate_postcode()
    post.postcode = postcode
    post.socket = socket
end

CircoCore.schedule_start(post::UDPPostOffice, scheduler) = begin
    post.intask = @async arrivals(post) # TODO errors throwed here are not logged
end

CircoCore.schedule_stop(post::UDPPostOffice, scheduler) = begin
    post.stopped = true
    yield()
end

Plugins.shutdown!(post::UDPPostOffice) = close(post.socket)

@inline CircoCore.letin_remote(post::UDPPostOffice, scheduler::AbstractScheduler)::Bool = begin
    for i = 1:min(length(post.inqueue), 30)
        CircoCore.deliver!(scheduler, popfirst!(post.inqueue))
    end
    return false
end

function arrivals(post::UDPPostOffice)
    try
        while !post.stopped
            rawmsg = recv(post.socket) # TODO: this blocks, so we will only exit if an extra message comes in after stopping
            stream = IOBuffer(rawmsg)
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

function send(post::UDPPostOffice, msg::AbstractMsg)
    remoteroutes(post, nothing, msg)
end

@inline function CircoCore.remoteroutes(post::UDPPostOffice, scheduler, msg::AbstractMsg)::Bool
    @debug "PostOffice delivery at $(postcode(post)): $msg"
    try
        parts = split(postcode(target(msg)), ":")
        ip = parse(IPAddr, parts[1])
        port = parse(UInt16, parts[2])
        io = IOBuffer()
        serialize(io, msg)
        Sockets.send(post.outsocket, ip, port, take!(io))
    catch e
        @error "Unable to send $msg" exception = (e, catch_backtrace())
        return false
    end
    return true
end

end # module