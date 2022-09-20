# SPDX-License-Identifier: MPL-2.0
import Base.isless

const TIMEOUTCHECK_INTERVAL = 1.0

TokenId = UInt64
struct Token
    id::TokenId
    Token() = new(rand(TokenId))
    Token(id::TokenId) = new(id)
end

"""
    abstract type Tokenized end

Tokenized messages can be tracked automatically by the scheduler.

When an actor sends out a [`Request`](@ref), a timeout will be set up
to track the fulfillment of the request. When a `Response` with the same token
is received, the timeout will be cancelled. See also: [`send`](@ref).
"""
abstract type Tokenized end
token(t::Tokenized) = t.token

abstract type Request <: Tokenized end
abstract type Response <: Tokenized end

"""
    abstract type Failure <: Response end

`Failure` is a type of `Response` to a `Request` that fails to fulfill it.
"""
abstract type Failure <: Response end

struct Timer
    timeout_secs::Float64
end

struct Timeout{TCause}
    watcher::Addr
    token::Token
    deadline::Float64
    cause::TCause
end
Timeout(watcher::Actor, token::Token, timeout_secs, cause = Timer(timeout_secs)) = Timeout{typeof(cause)}(addr(watcher), token, Base.Libc.time() + timeout_secs, cause)
Base.isless(a::Timeout, b::Timeout) = isless(a.deadline, b.deadline)

mutable struct TokenService # TODO <: Plugin
    next_timeoutcheck_ts::Float64
    timeouts::Dict{Token, Timeout}
    TokenService() = new(Base.Libc.time() + TIMEOUTCHECK_INTERVAL, Dict())
end

@inline function settimeout(tokenservice::TokenService, timeout::Timeout)
    tokenservice.timeouts[timeout.token] = timeout
end

@inline function cleartimeout(tokenservice::TokenService, token::Token)
    removed = pop!(tokenservice.timeouts, token, nothing)
end

@inline function needchecktimeouts!(tokenservice::TokenService)
    ts = Base.Libc.time()
    if tokenservice.next_timeoutcheck_ts > ts
        return false
    end
    tokenservice.next_timeoutcheck_ts = ts + TIMEOUTCHECK_INTERVAL
    return true
end

# TODO optimize
@inline function poptimeouts!(tokenservice::TokenService, currenttime = Base.Libc.time())::Vector{Timeout}
    retval = Vector{Timeout}()
    firedtokens = Vector{Token}()
    for (token, timeout) in tokenservice.timeouts
        if timeout.deadline < currenttime
            push!(retval, timeout)
            push!(firedtokens, token)
        end
    end
    for token in firedtokens
        delete!(tokenservice.timeouts, token)
    end
    return retval
end
