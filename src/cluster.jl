# SPDX-License-Identifier: LGPL-3.0-only
const MAX_JOINREQUEST_COUNT = 100

mutable struct SchedulerInfo
    name::String
    address::Address
    SchedulerInfo(name) = new(name)
    SchedulerInfo() = new()
end

mutable struct ClusterActor <: AbstractActor
    myinfo::SchedulerInfo
    roots::Array{Address}
    joined::Bool
    joinrequestcount::UInt16
    peers::Dict{Address,SchedulerInfo}
    peerupdate_count::UInt
    address::Address
    ClusterActor(myinfo, roots) = new(myinfo, roots, false, 0, Dict(), 0)
    ClusterActor(myinfo::SchedulerInfo) = ClusterActor(myinfo, [])
    ClusterActor(name::String) = ClusterActor(SchedulerInfo(name))
end

struct JoinRequest
    info::SchedulerInfo
end

struct JoinResponse
    requestorinfo::SchedulerInfo
    responderinfo::SchedulerInfo
    accepted::Bool
end

struct PeerJoinedNotification
    peer::SchedulerInfo
end

struct PeerListRequest
    respondto::Address
end

struct PeerListResponse
    peers::Array{SchedulerInfo}
end

function requestjoin(me, service)
    if length(me.roots) == 0
        println("I am the first actor: $(address(me))")
        registerpeer(me, me.myinfo, service)
        return
    end
    root = rand(me.roots)
    if me.joinrequestcount >= MAX_JOINREQUEST_COUNT
        error("Cannot join: $(me.joinrequestcount) unsuccesful attempt.")
    end
    me.joinrequestcount += 1
    send(service, me, root, JoinRequest(me.myinfo))
end

function onschedule(me::ClusterActor, service)
    me.myinfo.address = address(me)
    requestjoin(me, service)
end

function setpeer(me::ClusterActor, peer::SchedulerInfo)
    me.peerupdate_count += 1
    if haskey(me.peers, peer.address)
        return false
    end
    me.peers[peer.address] = peer
    return true
end

function registerpeer(me::ClusterActor, newpeer::SchedulerInfo, service)
    if setpeer(me, newpeer)
        for peer in values(me.peers)
            send(service, me, peer.address, PeerJoinedNotification(newpeer))
        end
        return true
    end
    return false
end

function onmessage(me::ClusterActor, message::JoinRequest, service)
    #println("Join request from $(message.info.address.box)")
    newpeer = message.info
    send(service, me, newpeer.address, JoinResponse(newpeer, me.myinfo, true))
    registerpeer(me, newpeer, service)
end

function onmessage(me::ClusterActor, message::JoinResponse, service)
    if message.accepted
        #println("Join accepted: $(me.address)")
        me.joined = true
        send(service, me, message.responderinfo.address, PeerListRequest(address(me)))
    else
        requestjoin(me, service)
    end
end

function onmessage(me::ClusterActor, message::PeerListRequest, service)
    #println("Peer list request from $(message.respondto.box)")
    send(service, me, message.respondto, PeerListResponse(collect(values(me.peers))))
end

function onmessage(me::ClusterActor, message::PeerListResponse, service)
    for peer in message.peers
        setpeer(me, peer)
    end
end

function onmessage(me::ClusterActor, message::PeerJoinedNotification, service)
    if registerpeer(me, message.peer, service)
        # println("Peer joined: $(message.peer.address.box) at $(me.address.box)")
    end
end