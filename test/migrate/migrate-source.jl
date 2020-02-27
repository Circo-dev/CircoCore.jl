# SPDX-License-Identifier: LGPL-3.0-only
include("migrate-base.jl")
using CircoCore
import CircoCore.onmessage

function onmessage(me::Migrant, message::MigrateCommand, service)
    migrate(service, me, message.topostcode)
end

function migratetoremote()
    migrant = Migrant()
    scheduler = ActorScheduler([migrant])
    cmd = MigrateCommand("tcp://192.168.193.99:24721")
    source = Address("", UInt64(0))    
    message = Message{MigrateCommand}(source, address(migrant), cmd)
    scheduler(message)
    shutdown!(scheduler)
end