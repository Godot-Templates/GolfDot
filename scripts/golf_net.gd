class_name GolfNet
extends Node
## Networked "ghost balls" over the Ziva relay.
##
## Each peer connects to a room keyed by the current hole (so everyone playing
## hole N shares a room). Motion is reproduced by REPLAYING shots, not streaming:
## the owner broadcasts each shot (start + launch velocity) and reset via RPC, and
## remote peers replay them through a local physics sim (see golf_ghost_ball.gd).
## The continuously-replicated `net_pos` is only the authoritative/at-rest position
## used for spawn placement and a gentle correction once the ball stops.
##
## The relay is a flat message switch with no dedicated server, so authority is
## elected deterministically: HOST = the lowest real peer id (ids > 1; id 1 is
## the relay's phantom server slot). The host owns the MultiplayerSpawner and is
## the only peer that spawns player nodes.

const GHOST_SCRIPT := "res://scripts/golf_ghost_ball.gd"

var _players: Node3D
var _spawner: MultiplayerSpawner
var _host: int = 0
var _room: String = ""
var _local_name: String = "Player"
var _local_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
    _players = Node3D.new()
    _players.name = "Players"
    add_child(_players)

    _spawner = MultiplayerSpawner.new()
    _spawner.name = "Spawner"
    add_child(_spawner)
    _spawner.spawn_path = _spawner.get_path_to(_players)
    _spawner.spawn_function = Callable(self, "_spawn_player")

    multiplayer.peer_connected.connect(_on_peer)
    multiplayer.peer_disconnected.connect(_on_peer_gone)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_conn_failed)
    multiplayer.server_disconnected.connect(_on_server_gone)

## Set the display name carried onto this peer's ghost ball.
func set_local_name(value: String) -> void:
    _local_name = value if value.strip_edges() != "" else "Player"

## Feed the local ball's world position each frame; pushed onto our own player
## node so the synchronizer replicates it (as the authoritative/at-rest position)
## to the other peers.
func update_local_pos(world_pos: Vector3) -> void:
    _local_pos = world_pos
    var node: Node = _local_node()
    if node != null:
        node.set("net_pos", world_pos)
        node.set("pname", _local_name)

## Returns our own player node (the one the local peer has authority over), or null.
func _local_node() -> Node:
    var me: int = multiplayer.get_unique_id()
    if me <= 1:
        return null
    return _players.get_node_or_null("player_%d" % me)

## Broadcast a shot so remote peers replay it through their local physics sim.
func broadcast_shot(start: Vector3, vel: Vector3) -> void:
    var node: Node = _local_node()
    if node != null:
        node.shot.rpc(start, vel)

## Broadcast an instant ball placement (tee/reset/out-of-bounds) to remote peers.
func broadcast_place(pos: Vector3) -> void:
    var node: Node = _local_node()
    if node != null:
        node.set("net_pos", pos)
        node.place.rpc(pos)

## Connect to (or switch to) the relay room for the given id. No-op if already in
## that room. Reconnects when the hole changes so players only meet on the same hole.
func join_room(room_id: String) -> void:
    if room_id == _room and _is_live():
        return
    _leave()
    _room = room_id

    var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
    var game_id: String = ProjectSettings.get_setting("ziva/multiplayer/game_id", "")
    var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
    # Fail loud rather than silently connect nowhere.
    if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
        push_error("GolfNet: Ziva multiplayer settings missing — enable multiplayer in Settings → Ziva Cloud.")
        return

    var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, room_id, user_id, game_id]
    var peer := WebSocketMultiplayerPeer.new()
    var err: int = peer.create_client(url)
    if err != OK:
        push_error("GolfNet: create_client failed (%d) for %s" % [err, url])
        return
    multiplayer.multiplayer_peer = peer
    print("GolfNet: joining room '%s'" % room_id)

func _is_live() -> bool:
    var p: MultiplayerPeer = multiplayer.multiplayer_peer
    return p != null and not (p is OfflineMultiplayerPeer)

func _leave() -> void:
    for c in _players.get_children():
        c.queue_free()
    _host = 0
    if _is_live():
        multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

# --- Host election -----------------------------------------------------------

func _real_peers() -> Array:
    var out: Array = []
    for p in multiplayer.get_peers():
        if int(p) > 1:
            out.append(int(p))
    return out

# Host = lowest real peer id. include_self_floor lets the caller exclude `me` from
# the candidate set during the connect burst, when get_peers() may not yet list
# lower peers the relay is about to deliver (claiming self there would make this
# peer reject the real host's spawns until it caught up).
func _refresh_host(include_self_floor: bool = true) -> void:
    var cands: Array = _real_peers()
    var me: int = multiplayer.get_unique_id()
    if include_self_floor and me > 1:
        cands.append(me)
    cands.sort()
    if cands.size() > 0:
        _host = int(cands[0])
        _spawner.set_multiplayer_authority(_host)

func _i_am_host() -> bool:
    return multiplayer.get_unique_id() == _host and _host > 0

func _host_spawn(id: int) -> void:
    if not _i_am_host() or id <= 1:
        return
    if _players.has_node("player_%d" % id):
        return
    _spawner.spawn(id)

func _host_spawn_all() -> void:
    if not _i_am_host():
        return
    _host_spawn(multiplayer.get_unique_id())
    for id in _real_peers():
        _host_spawn(id)

# --- Connection callbacks ----------------------------------------------------

func _on_connected() -> void:
    # id 2 is the only id that provably has no lower peer, so it is the only peer
    # that may treat itself as the host floor on connect and self-spawn.
    var me: int = multiplayer.get_unique_id()
    print("GolfNet: connected to relay as peer %d (room '%s')" % [me, _room])
    _refresh_host(me == 2)
    if me == 2:
        _host_spawn_all()

func _on_peer(id: int) -> void:
    if id <= 1:
        return
    print("GolfNet: peer %d joined room '%s' (host=%d)" % [id, _room, _host])
    _refresh_host()
    _host_spawn_all()

func _on_peer_gone(id: int) -> void:
    if _players.has_node("player_%d" % id):
        _players.get_node("player_%d" % id).queue_free()
    # Reactive failover: recompute host from the (now authoritative) roster. If we
    # became the new lowest peer, adopt the spawner and re-spawn everyone present.
    _refresh_host()
    if _i_am_host():
        _host_spawn_all()

func _on_conn_failed() -> void:
    push_error("GolfNet: connection to relay failed")
    _leave()

func _on_server_gone() -> void:
    _leave()

# --- Spawn function (runs on every peer to build the node locally) ------------

func _spawn_player(data: Variant) -> Node:
    var id: int = int(data)
    var p := Node3D.new()
    p.name = "player_%d" % id
    p.set_script(load(GHOST_SCRIPT))

    var sync := MultiplayerSynchronizer.new()
    sync.name = "Sync"
    sync.replication_interval = 0.0  # push every network frame for lowest lag

    var cfg := SceneReplicationConfig.new()
    cfg.add_property(NodePath(".:net_pos"))
    cfg.property_set_spawn(NodePath(".:net_pos"), true)
    cfg.property_set_replication_mode(NodePath(".:net_pos"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
    cfg.add_property(NodePath(".:pname"))
    cfg.property_set_spawn(NodePath(".:pname"), true)
    cfg.property_set_replication_mode(NodePath(".:pname"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
    sync.replication_config = cfg
    sync.root_path = NodePath("..")
    p.add_child(sync)
    return p
