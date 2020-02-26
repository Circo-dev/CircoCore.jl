include("migrate-base.jl")
using CircoCore
import CircoCore.onmessage

function onmessage(me::Migrant, message::MigrateCommand, service)
    println("migrate start")
    migrate(service, me, message.topostcode)
end

function migratetoremote()
    migrant = Migrant()
    scheduler = ActorScheduler([migrant])
    cmd = MigrateCommand("tcp://localhost:24721")
    source = Address("", UInt64(0))    
    message = Message{MigrateCommand}(source, address(migrant), cmd)
    scheduler(message)
    shutdown!(scheduler)
end