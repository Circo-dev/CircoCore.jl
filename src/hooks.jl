# SPDX-License-Identifier: MPL-2.0

# Lifecycle hooks
prepare(::Plugin, ::Any) = false
schedule_start(::Plugin, ::Any) = false
schedule_pause(::Plugin, ::Any) = false
schedule_continue(::Plugin, ::Any) = false
schedule_stop(::Plugin, ::Any) = false
stage(::Plugin, ::Any) = false

prepare_hook = Plugins.create_lifecyclehook(prepare) # For staging. Will be called only once per ctx, do not use the plugin instance!
schedule_start_hook = Plugins.create_lifecyclehook(schedule_start)
schedule_pause_hook = Plugins.create_lifecyclehook(schedule_pause)
schedule_continue_hook = Plugins.create_lifecyclehook(schedule_continue)
schedule_stop_hook = Plugins.create_lifecyclehook(schedule_stop)
stage_hook = Plugins.create_lifecyclehook(stage)

# Event hooks
function actor_activity_sparse16 end # An actor just received a message, called with 1/16 probability
function actor_activity_sparse256 end # An actor just received a message, called with 1/256 probability
function actor_spawning end # called when the actor is already spawned, but before onspawn.
function actor_dying end # called when the actor will die, but before ondeath.
function actor_state_write end # A write to an actor state will be applied (transaction commit)
function idle end # called irregularly while the message queue is empty.
function letin_remote end # Let external sources push messages into the queue (using deliver!).
function localdelivery end # deliver a message to an actor (e.g. call onmessage)
function localroutes end # Handle messages that are targeted to actors not (currently) scheduled locally (e.g. during migration).
function remoteroutes end # Deliver messages to external targets
function spawnpos end # Provide initial position of an actor when it is spawned
function specialmsg end # Handle messages that are targeted to the scheduler (to the box 0)

scheduler_hooks = [remoteroutes, localdelivery, actor_spawning, actor_dying,
    actor_state_write,
    localroutes, specialmsg, letin_remote,
    actor_activity_sparse16, actor_activity_sparse256, idle, spawnpos]

# Plugin-assembled types
abstract type AbstractCoreState end
abstract type AbstractMsg{TBody} end # TODO rename to AbstractEnvelope

# Helpers

function call_lifecycle_hook(target, lfhook, args...)
    res = lfhook(target.plugins, target, args...)
    if !res.allok
        for (i, result) in enumerate(res.results)
            if result isa Tuple && result[1] isa Exception
                trimhook(s) = endswith(s, "_hook") ? s[1:end-5] : s
                @error "Error in calling '$(trimhook(string(lfhook)))' lifecycle hook of plugin $(typeof(target.plugins[i])):" result
            end
        end
    end
end
