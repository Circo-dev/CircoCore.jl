using HTTP, Logging

mutable struct WebsocketService <: SchedulerPlugin
    socket
    WebsocketService() = new()
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
                while !eof(ws)
                    data = readavailable(ws)
                    write(ws, data)
                end
            end
        end
    end
end

function shutdown!(service::WebsocketService)
    isdefined(service, :socket) && close(service.socket)
end

function websocket_routes!(scheduler::AbstractActorScheduler, message::AbstractMessage)::Bool
    return false
end