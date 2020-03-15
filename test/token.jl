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
    responder::Address
    address::Address
    Requestor() = new(0)
end

struct TResponse <: Response
    requestid::UInt64
    token::Token
end

mutable struct Responder <: AbstractActor
    address::Address
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
    if req.id != 51
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
    println("Got Timeout: $timeout")
    die(service, me)
end

@testset "Token" begin
    requestor = Requestor()
    responder = Responder()
    scheduler = ActorScheduler([responder, requestor])
    scheduler(exit_when_done=true)
    shutdown!(scheduler)
    @test requestor.responder == address(responder)
    @test requestor.responsecount == MESSAGE_COUNT - 1
end

end