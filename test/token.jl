# SPDX-License-Identifier: MPL-2.0
module TokenTest

using Test
using Dates
using CircoCore

MESSAGE_COUNT = 201

struct TRequest <: Request
    id::UInt64
    token::Token
    TRequest(id) = new(id, Token())
end

mutable struct Requestor{TCore} <: Actor{TCore}
    replycount::Int
    failurecount::Int
    timeoutcount::Int
    responder::Addr
    core::TCore
    Requestor(core) = new{typeof(core)}(0, 0, 0, Addr(), core)
end

struct TReply <: Reply
    requestid::UInt64
    token::Token
end

struct TFailure <: Failure
    requestid::UInt64
    token::Token
end

mutable struct Responder{TCore} <: Actor{TCore}
    core::TCore
end

CircoCore.onmessage(me::Responder, ::OnSpawn, service) = begin
    registername(service, string(TRequest), me)
end

CircoCore.onmessage(me::Requestor, ::OnSpawn, service) = begin
    registername(service, "requestor", me)
    me.responder = getname(service, string(TRequest))
    for i=1:MESSAGE_COUNT
        send(service, me, me.responder, TRequest(i); timeout = 2.0)
    end
end

CircoCore.onmessage(me::Responder, req::TRequest, service) = begin
    if req.id % 3 == 1
        send(service, me, getname(service, "requestor"), TReply(req.id, req.token))
    end
    if req.id % 3 == 2
        send(service, me, getname(service, "requestor"), TFailure(req.id, req.token))
    end
    if req.id == MESSAGE_COUNT
        die(service, me)
    end
end

CircoCore.onmessage(me::Requestor, resp::TReply, service) = begin
    me.replycount += 1
end

CircoCore.onmessage(me::Requestor, resp::TFailure, service) = begin
    me.failurecount += 1
end

CircoCore.onmessage(me::Requestor, timeout::Timeout, service) = begin
    me.timeoutcount += 1
    if me.timeoutcount == MESSAGE_COUNT / 3
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
    @test requestor.replycount == MESSAGE_COUNT / 3
    @test requestor.failurecount == MESSAGE_COUNT / 3
    @test length(scheduler.tokenservice.timeouts) == 0
    shutdown!(scheduler)
end

end
