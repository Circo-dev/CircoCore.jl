# SPDX-License-Identifier: LGPL-3.0-only
include("typeregistry.jl")

using HTTP, Logging, MsgPack

struct RegistrationRequest
    actoraddr::Addr
end
struct Registered
    actoraddr::Addr
    accepted::Bool
end

MsgPack.msgpack_type(::Type) = MsgPack.StructType() # TODO this drops the warning "incremental compilation may be fatally broken for this module"

MsgPack.msgpack_type(::Type{ActorId}) = MsgPack.StringType()
MsgPack.to_msgpack(::MsgPack.StringType, id::ActorId) = string(id, base=16)
MsgPack.from_msgpack(::Type{ActorId}, str::AbstractString) = parse(ActorId, str;base=16)


mutable struct WebsocketService <: SchedulerPlugin
    actor_connections::Dict{ActorId, IO}
    typeregistry::TypeRegistry
    socket
    WebsocketService() = new(Dict(), TypeRegistry())
end

symbol(plugin::WebsocketService) = :websocket
localroutes(plugin::WebsocketService) = websocket_routes!

function setup!(service::WebsocketService, scheduler)
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
                handle_connection(service, ws, scheduler)
            end
        end
    end
end

function sendws(msg::Msg, ws)
    try
        write(ws, marshal(msg))
    catch e
        @info "Unable to write to websocket (target: $(target(msg)))", e
    end
end

function handlemsg(service::WebsocketService, msg::Msg{RegistrationRequest}, ws, scheduler)
    actorid = box(body(msg).actoraddr)
    service.actor_connections[actorid] = ws
    newaddr = Addr(postcode(scheduler), actorid)
    response = Msg(target(msg), sender(msg), Registered(newaddr, true))
    sendws(response, ws)
    return nothing
end

function handlemsg(service::WebsocketService, query::Msg{NameQuery}, ws, scheduler)
    sendws(Msg(target(query),
            sender(query),
            NameResponse(body(query), getname(scheduler.registry, body(query).name), body(query).token)
            ), ws)
    return nothing
end

function handlemsg(service::WebsocketService, msg::Msg, ws, scheduler)
    deliver!(scheduler, msg)
    return nothing
end

handlemsg(service::WebsocketService, msg, ws, scheduler) = nothing

function handle_connection(service::WebsocketService, ws, scheduler)
    try
        while !eof(ws)
            buf = readavailable(ws)
            msg = unmarshal(service.typeregistry, buf)
            handlemsg(service, msg, ws, scheduler)
        end
    catch e
        @info e
    end
    @debug "Websocket closed", ws
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
        return unpack(io, type)
    catch e
        if e isa UndefVarError
             @warn "Type $typename is not known"
        else
            rethrow(e)
        end
    end
    return nothing
end


function shutdown!(service::WebsocketService)
    isdefined(service, :socket) && close(service.socket)
end

function websocket_routes!(ws_plugin::WebsocketService, scheduler::AbstractActorScheduler, msg::AbstractMsg)::Bool
    ws = get(ws_plugin.actor_connections, box(target(msg)), nothing)
    if !isnothing(ws)
        sendws(msg, ws)
        return true
    end
    return false
end