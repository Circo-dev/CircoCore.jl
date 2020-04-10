# SPDX-License-Identifier: LGPL-3.0-only
include("typeregistry.jl")

using HTTP, Logging, MsgPack

struct RegistrationRequest
    actoraddr::Addr
end
MsgPack.msgpack_type(::Type{RegistrationRequest}) = MsgPack.StructType()
MsgPack.msgpack_type(::Type{Msg{RegistrationRequest}}) = MsgPack.StructType()
MsgPack.msgpack_type(::Type{Addr}) = MsgPack.StructType()

mutable struct WebsocketService <: SchedulerPlugin
    actor_connections::Dict{ActorId, IO}
    typeregistry::TypeRegistry
    socket
    WebsocketService() = new(Dict(), TypeRegistry())
end

symbol(plugin::WebsocketService) = :websocket
localroutes(plugin::WebsocketService) = websocket_routes!

function setup!(service::WebsocketService)
    port = 2497 # CIWS
    try
        service.socket = Sockets.listen(Sockets.InetAddr(parse(IPAddr, "127.0.0.1"), port))
        @info "Web Socket listening on port $port"
    catch e
        @warn "Unable to listen on port $port", e
    end
    @async HTTP.listen("127.0.0.1", port; server=service.socket) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http; binary=true) do ws
                @info "Got WS connection", ws
                handle_connection(service, ws)
            end
        end
    end
end

function handle_connection(service::WebsocketService, ws)
    actors = Vector{ActorId}()
    while !eof(ws)
        buf = readavailable(ws)
        data = unmarshal(service.typeregistry, buf)
        if !isnothing(data)
            buf = marshal(data)
            write(ws, buf)
        end
    end
end

function marshal(data)
    buf = IOBuffer()
    println(buf, typeof(data))
    write(buf, pack(data))
    seek(buf, 0)
    return buf
end

function unmarshal(registry::TypeRegistry, buf)
    length(buf) > 0 || return nothing
    typename = ""
    try
        io = IOBuffer(buf)
        typename = readline(io)
        type = gettype(registry,typename)
        println("Got typename '$typename', created type: $type")
        return unpack(io, type)
    catch e
        e isa UndefVarError && @warn "Type $typename is not known"
        @info e
    end
    return nothing
end


function shutdown!(service::WebsocketService)
    isdefined(service, :socket) && close(service.socket)
end

function websocket_routes!(scheduler::AbstractActorScheduler, message::AbstractMsg)::Bool
    return false
end