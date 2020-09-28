# Plugin Lifecycle

Plugins.customfield(plugin, parent_type)

prepare(plugin, ctx) # Initial stage

Plugins.setup!(plugin, scheduler) # Allocate resources

    schedule_start(plugin, scheduler)

        schedule_continue(plugin, scheduler)

            localdelivery() # Deliver a message to an actor (e.g. call onmessage)
            localroutes() # Handle messages that are targeted to actors not (currently) scheduled locally (e.g. during migration).
            specialmsg() # Handle messages that are targeted to the scheduler (to the box 0)
            remoteroutes() # Deliver messages to external targets
            actor_activity_sparse16() # An actor just received a message, called with 1/16 probability
            actor_activity_sparse256() # An actor just received a message, called with 1/256 probability
            spawnpos() # Provide initial position of an actor when it is spawned

            letin_remote() # Let external sources push messages into the queue (using deliver!).

        schedule_pause(plugin, scheduler)

        stage(plugin, scheduler) # Next stage

    schedule_stop(plugin, scheduler)

Plugins.shutdown!(plugin, scheduler) # Release resources