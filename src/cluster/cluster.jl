# SPDX-License-Identifier: LGPL-3.0-only
using Logging
import Base.isless

const NAME = "cluster"
const MAX_JOINREQUEST_COUNT = 10
const MAX_DOWNSTREAM_FRIENDS = 25
const TARGET_FRIEND_COUNT = 5
const MIN_FRIEND_COUNT = 3

mutable struct ClusterService <: Plugin
    roots::Array{PostCode}
    helper::Addr
    ClusterService(;options = NamedTuple()) = new(get(options, :roots, []))
end
CircoCore.symbol(::ClusterService) = :cluster
CircoCore.setup!(cluster::ClusterService, scheduler) = begin
    helper = ClusterActor(;roots=cluster.roots)
    cluster.helper = spawn(scheduler.service, helper)
end

mutable struct NodeInfo
    name::String
    addr::Addr
    pos::Pos
    NodeInfo(name) = new(name)
    NodeInfo() = new()
end
pos(i::NodeInfo) = i.pos
addr(i::NodeInfo) = i.addr
postcode(i::NodeInfo) = postcode(addr(i))

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
    ClusterActor(;roots=[]) = ClusterActor(NodeInfo("unnamed"), roots)
end
monitorextra(me::ClusterActor) = (myinfo=me.myinfo, peers=values(me.peers))
monitorprojection(::Type{ClusterActor}) = JS("projections.nonimportant")

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

struct ForceAddRoot
    root::PostCode
end

function requestjoin(me::ClusterActor, service)
    @debug "$(addr(me)) : Requesting join"
    if !isempty(me.servicename)
        registername(service, NAME, me)
    end
    if length(me.roots) == 0
        registerpeer(me, me.myinfo, service)
        return
    end
    if me.joinrequestcount >= MAX_JOINREQUEST_COUNT
        error("Cannot join: $(me.joinrequestcount) unsuccesful attempt.")
    end
    querycluster_thensendjoinrequest(me, rand(me.roots), service)
end

function querycluster_thensendjoinrequest(me::ClusterActor, root::PostCode, service)
    me.joinrequestcount += 1
    @debug "$(addr(me)) : Querying name 'cluster'"
    send(service, me, Addr(root), NameQuery("cluster");timeout=Second(10))
end

function onmessage(me::ClusterActor, msg::ForceAddRoot, service)
    @debug "$(addr(me)) : Got $msg"
    push!(me.roots, msg.root)
    querycluster_thensendjoinrequest(me, msg.root, service)
end

function onschedule(me::ClusterActor, service)
    me.myinfo.addr = addr(me)
    me.myinfo.pos = pos(service)
    me.eventdispatcher = spawn(service, EventDispatcher())
    requestjoin(me, service)
end

function setpeer(me::ClusterActor, peer::NodeInfo)
    me.peerupdate_count += 1
    if haskey(me.peers, peer.addr)
        return false
    end
    me.peers[peer.addr] = peer
    @debug "$(addr(me)) : Peer $(addr(peer)) set"
    return true
end

function registerpeer(me::ClusterActor, newpeer::NodeInfo, service)
    if setpeer(me, newpeer)
        event = PeerListUpdated(collect(values(me.peers)))
        @debug "$(addr(me)) : Firing $event"
        fire(service, me, event)
        for friend in me.downstream_friends
            @debug "$(addr(me)) : Sending out PeerJoinedNotification to $friend"
            send(service, me, friend, PeerJoinedNotification(newpeer, addr(me)))
        end
        return true
    end
    return false
end

function onmessage(me::ClusterActor, msg::Subscribe{Joined}, service)
    if me.joined
        event = Joined(collect(values(me.peers)))
        @debug "$(addr(me)) : Sending out event to late subscriber $(msg.subscriber): $event"
        send(service, me, msg.subscriber, event) #TODO handle late subscription to one-off events automatically
    end
    @debug "$(addr(me)) : New subscriber to Joined $(msg.subscriber)"
    send(service, me, me.eventdispatcher, msg)
end

function onmessage(me::ClusterActor, msg::Subscribe{PeerListUpdated}, service)
    if length(me.peers) > 0
        event = PeerListUpdated(collect(values(me.peers)))
        @debug "$(addr(me)) : Sending out event to late subscriber $(msg.subscriber): $event"
        send(service, me, msg.subscriber, event) # TODO State-change events may need a better (automatic) mechanism for handling initial state
    end
    send(service, me, me.eventdispatcher, msg)
end

function onmessage(me::ClusterActor, msg::NameResponse, service)
    if msg.query.name !== "cluster"
        @info "$(addr(me)) : Got invalid $msg"
        return
    end
    root = msg.handler
    if isnothing(root)
        requestjoin(me, service)
    else
        sendjoinrequest(me, root, service)
    end
end

function sendjoinrequest(me::ClusterActor, root::Addr, service)
    send(service, me, root, JoinRequest(me.myinfo))
end

function onmessage(me::ClusterActor, msg::JoinRequest, service)
    @debug "$(addr(me)) : Got $msg"
    newpeer = msg.info
    if (length(me.upstream_friends) < TARGET_FRIEND_COUNT)
        send(service, me, newpeer.addr, FriendRequest(addr(me)))
    end
    if registerpeer(me, newpeer, service)
        @info "Got new peer $(newpeer.addr) . $(length(me.peers)) nodes in cluster."
    end
    send(service, me, newpeer.addr, JoinResponse(newpeer, me.myinfo, collect(values(me.peers)), true))
end

function onmessage(me::ClusterActor, msg::JoinResponse, service)
    @debug "$(addr(me)) : Got $msg"
    if msg.accepted
        me.joined = true
        initpeers(me, msg.peers, service)
        send(service, me, me.eventdispatcher, Joined(collect(values(me.peers))))
        @info "Joined to cluster using root node $(msg.responderinfo.addr). ($(length(msg.peers)) peers)"
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

function onmessage(me::ClusterActor, msg::PeerListRequest, service)
    @debug "$(addr(me)) : Got $msg"
    send(service, me, msg.respondto, PeerListResponse(collect(values(me.peers))))
end

function onmessage(me::ClusterActor, msg::PeerJoinedNotification, service)
    @debug "$(addr(me)) : Got $msg"
    if registerpeer(me, msg.peer, service)
        friend = get(me.upstream_friends, msg.creditto, nothing)
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
        # @info "Peer joined: $(message.peer.addr.box) at $(addr(me).box)"
    end
end

function getanewfriend(me::ClusterActor, service)
    @debug "$(addr(me)) : getanewfriend with peer count: $(length(me.peers))"
    length(me.peers) > 0 || return
    while true
        peer = rand(me.peers)[2]
        if peer.addr != addr(me)
            req = FriendRequest(addr(me))
            @debug "$(addr(me)) : Sending $req"
            send(service, me, peer.addr, req)
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

function onmessage(me::ClusterActor, msg::FriendRequest, service)
    @debug "$(addr(me)) : Got $msg"
    friendsalready = msg.requestor in me.downstream_friends
    accepted = !friendsalready && length(me.downstream_friends) < MAX_DOWNSTREAM_FRIENDS
    if accepted
        push!(me.downstream_friends, msg.requestor)
    end
    send(service, me, msg.requestor, FriendResponse(addr(me), accepted))
end

function onmessage(me::ClusterActor, message::FriendResponse, service)
    if message.accepted
        me.upstream_friends[message.responder] = Friend(message.responder)
    end
end

function onmessage(me::ClusterActor, message::UnfriendRequest, service)
    pop!(me.downstream_friends, message.requestor)
end

# TODO: update peers
#@inline function CircoCore.actor_activity_sparse(cluster::ClusterService, scheduler, actor::AbstractActor)
#   if rand(UInt8) == 0
#        
#    end
#end
