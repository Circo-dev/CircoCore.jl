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
    me.newaddress_selfreport = message.newaddress
    send(service, me, me.oldmigrantaddress, Request(address(me)))
end

function onmessage(me::Stayer, message::RecipientMoved, service)
    me.newaddress_recepientmoved = message.newaddress
    send(service, me, me.newaddress_recepientmoved, Request(address(me)))
end

function onmessage(me::Stayer, message::Response, service)
    me.responsereceived += 1
    send(service, me, me.resultsholder_address, Results(me))
    send(service, me, me.newaddress_recepientmoved, Results(me))
    die(service, me)
end

function migratetoremote(targetpostcode, resultsholder_address)
    migrant = Migrant()
    scheduler = ActorScheduler([migrant])
    stayer = Stayer(address(migrant), resultsholder_address)
    schedule!(scheduler, stayer)
    cmd = MigrateCommand(targetpostcode, address(stayer))
    message = Message(Address(), address(migrant), cmd)
    scheduler(message; process_external=true)
    shutdown!(scheduler)
end