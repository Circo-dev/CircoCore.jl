# SPDX-License-Identifier: LGPL-3.0-only
include("typeregistry.jl")

using HTTP, Logging

mutable struct WebsocketService <: SchedulerPlugin
    actor_connections::Dict{ActorId, IO}
    typeregistry::TypeRegistry
    socket
    WebsocketService() = new(Dict(), TypeRegistry())
end

symbol(plugin::WebsocketService) = :websocket
localroutes(plugin::WebsocketService) = websocket_routes!

function setup!(service::WebsocketService)
    port = 8081
    try
        service.socket = Sockets.listen(Sockets.InetAddr(parse(IPAddr, "127.0.0.1"), port))
    catch e
        @warn "Unable to listen on port $port", e
    end
    @async HTTP.listen("127.0.0.1", port; server=service.socket) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
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
            write(ws, marshal(data))
        end
    end
end

function marshal(data)
    return data
end

function unmarshal(registry::TypeRegistry, buf)
    length(buf) > 0 || return nothing
    typename = ""
    try
        println("Unmarshal type $(typeof(buf)), length: $(length(buf))")
        io = IOBuffer(buf)
        typename = read(io, String)
        type = gettype(registry,typename)
        println("Got typename '$typename', created type: $type")
        return buf
    catch e
        e isa UndefVarError && @warn "Type $typename is not known"
    end
    return nothing
end


function shutdown!(service::WebsocketService)
    isdefined(service, :socket) && close(service.socket)
end

function websocket_routes!(scheduler::AbstractActorScheduler, message::AbstractMsg)::Bool
    return false
end