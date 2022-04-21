# SPDX-License-Identifier: MPL-2.0
module ZMQPostOffices

using Plugins
using ..CircoCore
import ..CircoCore: AbstractCoreState

using Serialization, Sockets
using DataStructures
import ZMQ

mutable struct ZMQPostOffice <: CircoCore.PostOffice
    outsockets::Dict{PostCode, ZMQ.Socket}
    inqueue::Deque{Any}
    stopped::Bool
    postcode::PostCode
    socket::ZMQ.Socket
    intask
    ZMQPostOffice(;options...) = begin
        return new(Dict(), Deque{Any}(), false)
    end
end

addrinit() = nulladdr
addrinit(scheduler, actor, actorid) = Addr(postcode(scheduler.plugins[:postoffice]), actorid)
Plugins.customfield(::ZMQPostOffice, ::Type{AbstractCoreState}) = Plugins.FieldSpec("addr", Addr, addrinit)

__init__() = Plugins.register(ZMQPostOffice)

CircoCore.postcode(post::ZMQPostOffice) = post.postcode
CircoCore.addr(post::ZMQPostOffice) = Addr(postcode(post), 0)

function allocate_postcode()
    socket = ZMQ.Socket(ZMQ.PULL)
    for port in CircoCore.PORT_RANGE
        try
            buf = IOBuffer()
            print(buf, Sockets.getipaddr())
            ipstr = String(take!(buf))
            postcode = "$(ipstr):$port"
            ZMQ.bind(socket, "tcp://" * postcode)
            @info "ZMQPostOffice bound to $postcode"
            return postcode, socket
        catch e
            isa(e, ZMQ.StateError) || rethrow()
        end
    end
    throw(PostException("No available port found for a Post Office"))
end

CircoCore.setup!(post::ZMQPostOffice, scheduler) = begin
    postcode, socket = allocate_postcode()
    post.postcode = postcode
    post.socket = socket
end

CircoCore.schedule_start(post::ZMQPostOffice, scheduler) = begin
    post.intask = @async arrivals(post) # TODO errors throwed here are not logged
end

CircoCore.schedule_stop(post::ZMQPostOffice, scheduler) = begin
    post.stopped = true
    yield()
end

function shutdown!(post::ZMQPostOffice)
    close(post.socket)
    for socket in values(post.outsockets)
        ZMQ.close(socket)
    end
end

@inline CircoCore.letin_remote(post::ZMQPostOffice, scheduler::AbstractScheduler)::Bool = begin
    for i = 1:min(length(post.inqueue), 30)
        CircoCore.deliver!(scheduler, popfirst!(post.inqueue))
    end
    return false
end

function arrivals(post::ZMQPostOffice)
    try
        while !post.stopped
            message = recv(post.socket)
            stream = convert(IOStream, message)
            seek(stream, 0)
            msg = deserialize(stream)
            push!(post.inqueue, msg)
        end
    catch e
#        if !(e isa EOFError)
            @error "Exception in arrivals" exception = (e, catch_backtrace())
#        end
    end
end

function createsocket!(post::ZMQPostOffice, targetpostcode::PostCode)
    socket = ZMQ.Socket(ZMQ.PUSH)
    socketstr = "tcp://" * targetpostcode
    ZMQ.connect(socket, socketstr)
    post.outsockets[targetpostcode] = socket
    return socket
end
createsocket!(post::ZMQPostOffice, target::Addr) = createsocket!(post, postcode(target))

@inline function getsocket(post::ZMQPostOffice, target::Addr)
    socket = get(post.outsockets, postcode(target), nothing)
    if isnothing(socket)
        return createsocket!(post, target)
    end
    return socket
end

function send(post::ZMQPostOffice, msg::AbstractMsg)
    remoteroutes(post, nothing, msg)
end

@inline function send(post::PostOffice, message)
    #println("Sending out $message")
    socket = getsocket(post, target(message))
    io = IOBuffer()
    serialize(io, message)
    ZMQ.send(socket, ZMQ.Message(io))
end

@inline function CircoCore.remoteroutes(post::ZMQPostOffice, scheduler, msg::AbstractMsg)::Bool
    @debug "PostOffice delivery at $(postcode(post)): $msg"
    try
        socket = getsocket(post, target(msg))
        io = IOBuffer()
        serialize(io, msg)
        ZMQ.send(socket, ZMQ.Message(io))
    catch e
        @error "Unable to send $msg" exception = (e, catch_backtrace())
        error(42)
        return false
    end
    return true
end

end # module