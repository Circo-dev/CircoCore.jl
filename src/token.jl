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

struct Timeout
    watcher::Addr
    token::Token
    deadline::Float64
end
Timeout(watcher::Actor, token::Token, timeout_secs = 2.0) = Timeout(addr(watcher), token, Base.Libc.time() + timeout_secs)
Base.isless(a::Timeout, b::Timeout) = isless(a.deadline, b.deadline)

struct TimeoutKey
    watcher::Addr
    token::Token
end
TimeoutKey(t::Timeout) = TimeoutKey(t.watcher, t.token)

mutable struct TokenService # TODO <: Plugin
    next_timeoutcheck_ts::Float64
    timeouts::Dict{TimeoutKey, Timeout}
    TokenService() = new(Base.Libc.time() + TIMEOUTCHECK_INTERVAL, Dict())
end

@inline function settimeout(tokenservice::TokenService, timeout::Timeout)
    key = TimeoutKey(timeout)
    tokenservice.timeouts[key] = timeout
end

@inline function cleartimeout(tokenservice::TokenService, key::TimeoutKey)
    removed = pop!(tokenservice.timeouts, key, nothing)
end
cleartimeout(tokenservice::TokenService, token::Token, watcher::Addr) = cleartimeout(tokenservice, TimeoutKey(watcher, token))
cleartimeout(tokenservice::TokenService, timeout::Timeout) = cleartimeout(tokenservice, timeout.token, timeout.watcher)

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
    firedkeys= Vector{TimeoutKey}()
    for (key, timeout) in tokenservice.timeouts
        if timeout.deadline < currenttime
            push!(retval, timeout)
            push!(firedkeys, key)
        end
    end
    for key in firedkeys
        delete!(tokenservice.timeouts, key)
    end
    return retval
end
