# SPDX-License-Identifier: LGPL-3.0-only
include("migrate-base.jl")
using Test
using CircoCore
import CircoCore.onmessage

function onmessage(me::Migrant, message::MigrateCommand, service)
    me.stayeraddress = message.stayeraddress
    migrate(service, me, message.topostcode)
end

function onmessage(me::Stayer, message::MigrateDone, service)
    me.newaddressbyselfreport = message.newaddress
    send(service, me, me.oldmigrantaddress, Request(address(me)))
end

function onmessage(me::Stayer, message::RecipientMoved, service)
    me.newaddressbyrecepientmoved = message.newaddress
    send(service, me, me.newaddressbyrecepientmoved, Request(address(me)))
end

function onmessage(me::Stayer, message::Response, service)
    me.responsereceived += 1
    send(service, me, me.newaddressbyrecepientmoved, Results(me))
    die(service, me)
end

function migratetoremote()
    migrant = Migrant()
    scheduler = ActorScheduler([migrant])
    stayer = Stayer(address(migrant))
    schedule!(scheduler, stayer)
    cmd = MigrateCommand("tcp://192.168.1.11:24721", address(stayer))#192.168.193.99
    source = Address()    
    message = Message{MigrateCommand}(source, address(migrant), cmd)
    scheduler(message; process_external=true)
    shutdown!(scheduler)
end