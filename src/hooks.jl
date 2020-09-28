# SPDX-License-Identifier: LGPL-3.0-only

# Lifecycle hooks
stage(::Plugin, ::Any) = false
schedule_start(::Plugin, ::Any) = false
schedule_pause(::Plugin, ::Any) = false
schedule_continue(::Plugin, ::Any) = false
schedule_stop(::Plugin, ::Any) = false

stage_hook = Plugins.create_lifecyclehook(stage)
schedule_start_hook = Plugins.create_lifecyclehook(schedule_start)
schedule_pause_hook = Plugins.create_lifecyclehook(schedule_pause)
schedule_continue_hook = Plugins.create_lifecyclehook(schedule_continue)
schedule_stop_hook = Plugins.create_lifecyclehook(schedule_stop)

# Event hooks
function localdelivery end # deliver a message to an actor (e.g. call onmessage)
function localroutes end # Handle messages that are targeted to actors not (currently) scheduled locally (e.g. during migration).
function specialmsg end # Handle messages that are targeted to the scheduler (to the box 0)
function letin_remote end # Let external sources push messages into the queue (using deliver!).
function remoteroutes end # Deliver messages to external targets
function actor_activity_sparse16 end # An actor just received a message, called with 1/16 probability
function actor_activity_sparse256 end # An actor just received a message, called with 1/256 probability
function spawnpos end # Provide initial position of an actor when it is spawned

scheduler_hooks = [remoteroutes, localdelivery, localroutes, specialmsg, letin_remote,
    actor_activity_sparse16, actor_activity_sparse256, spawnpos]

# Plugin-Generated types

abstract type AbstractCoreState end
abstract type AbstractMsg{TBody} end

function call_lifecycle_hook(target, lfhook)
    res = lfhook(target.plugins, target)
    if !res.allok
        for (i, result) in enumerate(res.results)
            if result isa Tuple && result[1] isa Exception
                trimhook(s) = endswith(s, "_hook") ? s[1:end-5] : s
                @error "Error in calling '$(trimhook(string(lfhook)))' lifecycle hook of plugin $(typeof(target.plugins[i])):" result
            end
        end
    end
end
