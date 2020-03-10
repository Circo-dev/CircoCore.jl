# SPDX-License-Identifier: LGPL-3.0-only
using Logging
import Base.isless

const NAME = "cluster"
const MAX_JOINREQUEST_COUNT = 10
const MAX_DOWNSTREAM_FRIENDS = 25
const TARGET_FRIEND_COUNT = 5
const MIN_FRIEND_COUNT = 3

mutable struct NodeInfo
    name::String
    address::Address
    NodeInfo(name) = new(name)
    NodeInfo() = new()
end

mutable struct Friend
    address::Address
    score::UInt
    Friend(info) = new(info)
end
isless(a::Friend,b::Friend) = isless(a.score, b.score)

mutable struct ClusterActor <: AbstractActor
    myinfo::NodeInfo
    roots::Array{PostCode}
    joined::Bool
    joinrequestcount::UInt16
    peers::Dict{Address,NodeInfo}
    upstream_friends::Dict{Address,Friend}
    downstream_friends::Set{Address}
    peerupdate_count::UInt
    servicename::String
    address::Address
    ClusterActor(myinfo, roots) = new(myinfo, roots, false, 0, Dict(), Dict(), Set(), 0, NAME)
    ClusterActor(myinfo::NodeInfo) = ClusterActor(myinfo, [])
    ClusterActor(name::String) = ClusterActor(NodeInfo(name))
end

struct JoinRequest
    info::NodeInfo
end

struct JoinResponse
    requestorinfo::NodeInfo
    responderinfo::NodeInfo
    accepted::Bool
end

struct PeerJoinedNotification
    peer::NodeInfo
    creditto::Address
end

struct PeerListRequest
    respondto::Address
end

struct PeerListResponse
    peers::Array{NodeInfo}
end

struct FriendRequest
    requestor::Address
end

struct FriendResponse
    responder::Address
    accepted::Bool
end

struct UnfriendRequest
    requestor::Address
end

function requestjoin(me, service)
    if !isempty(me.servicename)
        registername(service, NAME, me)
    end
    if length(me.roots) == 0
        registerpeer(me, me.myinfo, service)
        return
    end
    root = rand(me.roots)
    if me.joinrequestcount >= MAX_JOINREQUEST_COUNT
        error("Cannot join: $(me.joinrequestcount) unsuccesful attempt.")
    end
    me.joinrequestcount += 1
    rootaddr = Address(root)
    if isbaseaddress(rootaddr)
        send(service, me, Address(root), NameQuery("cluster"))
    else
        send(service, me, rootaddr, JoinRequest(me.myinfo))
    end
end

function onschedule(me::ClusterActor, service)
    me.myinfo.address = address(me)
    requestjoin(me, service)
end

function setpeer(me::ClusterActor, peer::NodeInfo)
    me.peerupdate_count += 1
    if haskey(me.peers, peer.address)
        return false
    end
    me.peers[peer.address] = peer
    return true
end

function registerpeer(me::ClusterActor, newpeer::NodeInfo, service)
    if setpeer(me, newpeer)
        for friend in me.downstream_friends
            send(service, me, friend, PeerJoinedNotification(newpeer, address(me)))
        end
        return true
    end
    return false
end

function onmessage(me::ClusterActor, message::NameResponse, service)
    root = message.handler
    if isnothing(root)
        requestjoin(me, service)
    else
        send(service, me, root, JoinRequest(me.myinfo))
    end
end

function onmessage(me::ClusterActor, message::JoinRequest, service)
    newpeer = message.info
    send(service, me, newpeer.address, JoinResponse(newpeer, me.myinfo, true))
    if (length(me.upstream_friends) < TARGET_FRIEND_COUNT)
       send(service, me, newpeer.address, FriendRequest(address(me)))
    end
    if registerpeer(me, newpeer, service)
        @info "Got new peer $(newpeer.address) . $(length(me.peers)) nodes in cluster."
    end
end

function onmessage(me::ClusterActor, message::JoinResponse, service)
    if message.accepted
        me.joined = true
        println("Joined successfully.")
        send(service, me, message.responderinfo.address, PeerListRequest(address(me)))
    else
        requestjoin(me, service)
    end
end

function onmessage(me::ClusterActor, message::PeerListRequest, service)
    send(service, me, message.respondto, PeerListResponse(collect(values(me.peers))))
end

function onmessage(me::ClusterActor, message::PeerListResponse, service)
    for peer in message.peers
        setpeer(me, peer)
    end
    for i in 1:min(TARGET_FRIEND_COUNT, length(me.peers))
        getanewfriend(me, service)
    end
end

function onmessage(me::ClusterActor, message::PeerJoinedNotification, service)
    if registerpeer(me, message.peer, service)
        friend = get(me.upstream_friends, message.creditto, nothing)
        isnothing(friend) && return
        friend.score += 1
        if friend.score == 100
            replaceafriend(me, service)
            for f in values(me.upstream_friends)
                f.score = 0
            end
        elseif friend.score % 10 == 0
            if length(me.upstream_friends) < MIN_FRIEND_COUNT
                getanewfriend(me, service)
            end
        end
        #println("Peer joined: $(message.peer.address.box) at $(me.address.box)")
    end
end

function getanewfriend(me::ClusterActor, service)
    length(me.peers) > 0 || return
    while true
        peer = rand(me.peers)[2]
        if peer.address != address(me)
            send(service, me, peer.address, FriendRequest(address(me)))
            return nothing
        end
    end
end

function dropafriend(me::ClusterActor, service)
    length(me.upstream_friends) > MIN_FRIEND_COUNT || return
    weakestfriend = minimum(values(me.upstream_friends))
    if weakestfriend.score > 0
        return
    end
    #println("Dropping friend with score $(weakestfriend.score)")
    send(service, me, weakestfriend.address, UnfriendRequest(address(me)))
    pop!(me.upstream_friends, weakestfriend.address)
end

function replaceafriend(me::ClusterActor, service)
    dropafriend(me, service)
    if length(me.upstream_friends) < MIN_FRIEND_COUNT
        getanewfriend(me, service)
    end
end

function onmessage(me::ClusterActor, message::FriendRequest, service)
    friendsalready = message.requestor in me.downstream_friends
    accepted = !friendsalready && length(me.downstream_friends) < MAX_DOWNSTREAM_FRIENDS
    if accepted
        push!(me.downstream_friends, message.requestor)
    end
    send(service, me, message.requestor, FriendResponse(address(me), accepted))
end

function onmessage(me::ClusterActor, message::FriendResponse, service)
    if message.accepted
        me.upstream_friends[message.responder] = Friend(message.responder)
    end
end

function onmessage(me::ClusterActor, message::UnfriendRequest, service)
    pop!(me.downstream_friends, message.requestor)
end