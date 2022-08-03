abstract type Signal end

"""
    SigTerm(cause=Nothing; exit=Nothing)

Signal to terminate an actor.

The default handler terminates the actor without delay.
"""
struct SigTerm <: Signal
    cause
    exit::Union{Nothing, Bool} # Whether the scheduler should exit when this was the last actor and no more work
    SigTerm(cause=nothing; exit=nothing) = new(cause, exit)
end

onmessage(me::Actor, msg::SigTerm, service) = begin
    @debug "$(box(me)): Dying on" msg
    die(service, me; exit=isnothing(msg.exit) ? exitwhenlast(me) : msg.exit)
end

exitwhenlast(me::Actor) = true

