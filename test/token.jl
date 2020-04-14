# SPDX-License-Identifier: LGPL-3.0-only
module TokenTest

using Test
using CircoCore
import CircoCore.onschedule
import CircoCore.onmessage

MESSAGE_COUNT = 100

struct TRequest <: Request
    id::UInt64
    token::Token
    TRequest(id) = new(id, Token())
end

mutable struct Requestor <: AbstractActor
    responsecount::UInt
    timeoutcount::UInt
    responder::Addr
    core::CoreState
    Requestor() = new(0, 0)
end

struct TResponse <: Response
    requestid::UInt64
    token::Token
end

mutable struct Responder <: AbstractActor
    core::CoreState
    Responder() = new()
end

function onschedule(me::Responder, service)
    registername(service, string(TRequest), me)
end

function onschedule(me::Requestor, service)
    registername(service, string(TResponse), me)
    me.responder = getname(service, string(TRequest))
    for i=1:MESSAGE_COUNT
        send(service, me, me.responder, TRequest(i))
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
        die(service, me)
    end
end

@testset "Token" begin
    requestor = Requestor()
    responder = Responder()
    scheduler = ActorScheduler([responder, requestor])
    scheduler(exit_when_done=true)
    @test requestor.responder == addr(responder)
    @test requestor.responsecount == MESSAGE_COUNT / 2
    @test length(scheduler.tokenservice.timeouts) == 0
    shutdown!(scheduler)
end

end