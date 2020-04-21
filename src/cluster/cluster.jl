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
    addr::Addr
    NodeInfo(name) = new(name)
    NodeInfo() = new()
end

struct Joined <: Event
    peers::Array{NodeInfo}
end

struct PeerListUpdated <: Event
    peers::Array{NodeInfo}
end

mutable struct Friend
    addr::Addr
    score::UInt
    Friend(info) = new(info)
end
isless(a::Friend,b::Friend) = isless(a.score, b.score)

mutable struct ClusterActor <: AbstractActor
    myinfo::NodeInfo
    roots::Array{PostCode}
    joined::Bool
    joinrequestcount::UInt16
    peers::Dict{Addr,NodeInfo}
    upstream_friends::Dict{Addr,Friend}
    downstream_friends::Set{Addr}
    peerupdate_count::UInt
    servicename::String
    eventdispatcher::Addr
    core::CoreState
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
    peers::Array{NodeInfo}
    accepted::Bool
end

struct PeerJoinedNotification
    peer::NodeInfo
    creditto::Addr
end

struct PeerListRequest
    respondto::Addr
end

struct PeerListResponse
    peers::Array{NodeInfo}
end

struct FriendRequest
    requestor::Addr
end

struct FriendResponse
    responder::Addr
    accepted::Bool
end

struct UnfriendRequest
    requestor::Addr
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
    rootaddr = Addr(root)
    if isbaseaddress(rootaddr)
        send(service, me, Addr(root), NameQuery("cluster"))
    else
        send(service, me, rootaddr, JoinRequest(me.myinfo))
    end
end

function onschedule(me::ClusterActor, service)
    me.myinfo.addr = addr(me)
    me.eventdispatcher = spawn(service, EventDispatcher())
    requestjoin(me, service)
end

function setpeer(me::ClusterActor, peer::NodeInfo)
    me.peerupdate_count += 1
    if haskey(me.peers, peer.addr)
        return false
    end
    me.peers[peer.addr] = peer
    return true
end

function registerpeer(me::ClusterActor, newpeer::NodeInfo, service)
    if setpeer(me, newpeer)
        fire(service, me, PeerListUpdated(collect(values(me.peers))))
        for friend in me.downstream_friends
            send(service, me, friend, PeerJoinedNotification(newpeer, addr(me)))
        end
        return true
    end
    return false
end

function onmessage(me::ClusterActor, messsage::Subscribe{Joined}, service)
    if me.joined
        send(service, me, messsage.subscriber, Joined(collect(values(me.peers)))) #TODO handle late subscription to one-off events automatically
    end
    send(service, me, me.eventdispatcher, messsage)
end

function onmessage(me::ClusterActor, messsage::Subscribe{PeerListUpdated}, service)
    if length(me.peers) > 0
        send(service, me, messsage.subscriber, PeerListUpdated(collect(values(me.peers)))) # TODO State-change events may need a better (automatic) mechanism for handling initial state
    end
    send(service, me, me.eventdispatcher, messsage)
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
    if (length(me.upstream_friends) < TARGET_FRIEND_COUNT)
        send(service, me, newpeer.addr, FriendRequest(addr(me)))
    end
    if registerpeer(me, newpeer, service)
        @info "Got new peer $(newpeer.addr) . $(length(me.peers)) nodes in cluster."
    end
    send(service, me, newpeer.addr, JoinResponse(newpeer, me.myinfo, collect(values(me.peers)), true))
end

function onmessage(me::ClusterActor, message::JoinResponse, service)
    if message.accepted
        me.joined = true
        initpeers(me, message.peers, service)
        send(service, me, me.eventdispatcher, Joined(collect(values(me.peers))))
        println("Joined to cluster using root node $(message.responderinfo.addr)")
    else
        requestjoin(me, service)
    end
end

function initpeers(me::ClusterActor, peers::Array{NodeInfo}, service)
    for peer in peers
        setpeer(me, peer)
    end
    fire(service, me, PeerListUpdated(collect(values(me.peers))))
    for i in 1:min(TARGET_FRIEND_COUNT, length(peers))
        getanewfriend(me, service)
    end
end

function onmessage(me::ClusterActor, message::PeerListRequest, service)
    send(service, me, message.respondto, PeerListResponse(collect(values(me.peers))))
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
        # println("Peer joined: $(message.peer.addr.box) at $(me.addr.box)")
    end
end

function getanewfriend(me::ClusterActor, service)
    length(me.peers) > 0 || return
    while true
        peer = rand(me.peers)[2]
        if peer.addr != addr(me)
            send(service, me, peer.addr, FriendRequest(addr(me)))
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
    # println("Dropping friend with score $(weakestfriend.score)")
    send(service, me, weakestfriend.addr, UnfriendRequest(addr(me)))
    pop!(me.upstream_friends, weakestfriend.addr)
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
    send(service, me, message.requestor, FriendResponse(addr(me), accepted))
end

function onmessage(me::ClusterActor, message::FriendResponse, service)
    if message.accepted
        me.upstream_friends[message.responder] = Friend(message.responder)
    end
end

function onmessage(me::ClusterActor, message::UnfriendRequest, service)
    pop!(me.downstream_friends, message.requestor)
end