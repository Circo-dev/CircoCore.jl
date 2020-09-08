# SPDX-License-Identifier: LGPL-3.0-only

# Lifecycle hooks
schedule_start(::Plugin, ::Any) = false
schedule_stop(::Plugin, ::Any) = false

schedule_stop_hook = Plugins.create_lifecyclehook(schedule_stop)
schedule_start_hook = Plugins.create_lifecyclehook(schedule_start)

# Event hooks
function localdelivery end # just before calling onmessage
function localroutes end # Handle messages that are targeted to actors not (currently) scheduled locally (e.g. during migration).
function letin_remote end # Let external sources push messages into the queue (using deliver!).
function remoteroutes end # Deliver messages to external targets
function actor_activity_sparse16 end # An actor just received a message, called with 1/16 probability
function actor_activity_sparse256 end # An actor just received a message, called with 1/256 probability
function spawnpos end # An actor's position when its spawned

scheduler_hooks = [remoteroutes, localdelivery, localroutes, letin_remote,
    actor_activity_sparse16, actor_activity_sparse256, spawnpos]
