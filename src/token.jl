# SPDX-License-Identifier: LGPL-3.0-only
using Dates
import Base.isless

TokenId = UInt64
struct Token
    id::TokenId
    Token() = new(rand(TokenId))
end
abstract type Tokenized end
token(t::Tokenized) = t.token

abstract type Request <: Tokenized end
abstract type Response <: Tokenized end

struct Timeout
    watcher::Addr
    token::Token
    deadline::DateTime
end
Timeout(watcher::AbstractActor, token::Token, timeout::Second=Second(2)) = Timeout(address(watcher), token, Dates.now() + timeout)
Base.isless(a::Timeout, b::Timeout) = isless(a.deadline, b.deadline)

struct TimeoutKey
    watcher::Addr
    token::Token
end
TimeoutKey(t::Timeout) = TimeoutKey(t.watcher, t.token)

struct TokenService
    timeouts::Dict{TimeoutKey, Timeout}
    TokenService() = new(Dict())
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

@inline function poptimeouts!(tokenservice::TokenService)::Vector{Timeout}
    retval = Vector{Timeout}()
    firedkeys= Vector{TimeoutKey}()
    currenttime = Dates.now()
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