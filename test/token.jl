# SPDX-License-Identifier: MPL-2.0
module TokenTest

using Test
using Dates
using CircoCore
import CircoCore: onspawn, onmessage

MESSAGE_COUNT = 100

struct TRequest <: Request
    id::UInt64
    token::Token
    TRequest(id) = new(id, Token())
end

mutable struct Requestor{TCore} <: Actor{TCore}
    responsecount::Int
    timeoutcount::Int
    responder::Addr
    core::TCore
end
Requestor(core) = Requestor(0, 0, Addr(), core)

struct TResponse <: Response
    requestid::UInt64
    token::Token
end

mutable struct Responder{TCore} <: Actor{TCore}
    core::TCore
end

function onmessage(me::Responder, ::OnSpawn, service)
    registername(service, string(TRequest), me)
end

function onmessage(me::Requestor, ::OnSpawn, service)
    registername(service, string(TResponse), me)
    me.responder = getname(service, string(TRequest))
    for i=1:MESSAGE_COUNT
        send(service, me, me.responder, TRequest(i); timeout = 2.0)
    end
end

function onmessage(me::Responder, req::TRequest, service)
    if req.id % 2 == 1
        send(service, me, getname(service, string(TResponse)), TResponse(req.id, req.token))
    end
    if req.id == MESSAGE_COUNT
        die(service, me)
    end
end

function onmessage(me::Requestor, resp::TResponse, service)
    me.responsecount += 1
end

function onmessage(me::Requestor, timeout::Timeout, service)
    me.timeoutcount += 1
    if me.timeoutcount == MESSAGE_COUNT / 2
        println("Got $(me.timeoutcount) timeouts, exiting.")
        die(service, me; exit=true)
    end
end

@testset "Token" begin
    ctx = CircoContext(;target_module=@__MODULE__)
    requestor = Requestor(emptycore(ctx))
    responder = Responder(emptycore(ctx))
    scheduler = Scheduler(ctx, [responder, requestor])
    scheduler(;remote=true)
    @test requestor.responder == addr(responder)
    @test requestor.responsecount == MESSAGE_COUNT / 2
    @test length(scheduler.tokenservice.timeouts) == 0
    shutdown!(scheduler)
end

end
