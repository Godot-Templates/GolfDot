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

signal connection_problem(message: String)
signal status_changed(text: String)

var _players: Node3D
var _spawner: MultiplayerSpawner
var _host: int = 0
var _room: String = ""
var _local_name: String = "Player"
var _local_skin: String = PlayerProfile.DEFAULT_SKIN
var _local_pos: Vector3 = Vector3.ZERO
var _last_join_url: String = ""
var _last_join_room: String = ""
var _last_join_started_msec: int = 0
var _status_text: String = "Offline"

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
    var node: Node = _local_node()
    if node != null:
        node.set("pname", _local_name)

## Set the selected shop skin carried onto this peer's ghost ball.
func set_local_skin(value: String) -> void:
    _local_skin = value if value.strip_edges() != "" else PlayerProfile.DEFAULT_SKIN
    var node: Node = _local_node()
    if node != null:
        node.set("skin_id", _local_skin)

## Feed the local ball's world position each frame; pushed onto our own player
## node so the synchronizer replicates it (as the authoritative/at-rest position)
## to the other peers.
func update_local_pos(world_pos: Vector3) -> void:
    _local_pos = world_pos
    var node: Node = _local_node()
    if node != null:
        node.set("net_pos", world_pos)
        node.set("pname", _local_name)
        node.set("skin_id", _local_skin)

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
    _set_status_text("…")

    var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
    var game_id: String = ProjectSettings.get_setting("ziva/multiplayer/game_id", "")
    var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
    # Fail loudly enough to debug, but don't break local/offline play.
    if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
        _report_problem("Ziva multiplayer settings missing. Enable multiplayer in Settings → Ziva Cloud to use online ghost balls.")
        _set_status_text("Offline")
        return

    var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, room_id, user_id, game_id]
    _last_join_url = url
    _last_join_room = room_id
    _last_join_started_msec = Time.get_ticks_msec()

    var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
    var err: int = peer.create_client(url)
    if err != OK:
        _report_problem("create_client failed before opening the WebSocket (error %d). URL=%s" % [err, _redacted_url()])
        _set_status_text("Offline")
        return
    multiplayer.multiplayer_peer = peer
    print("GolfNet: joining room '%s' via %s" % [room_id, relay_url])

func _is_live() -> bool:
    var p: MultiplayerPeer = multiplayer.multiplayer_peer
    return p != null and not (p is OfflineMultiplayerPeer)

func status_text() -> String:
    return _status_text

func _set_status_text(value: String) -> void:
    if value == _status_text:
        return
    _status_text = value
    status_changed.emit(_status_text)

func _online_count() -> int:
    var me: int = multiplayer.get_unique_id()
    if me <= 1:
        return 0
    return _real_peers().size() + 1

func _refresh_status_text() -> void:
    var count: int = _online_count()
    if count <= 0:
        _set_status_text("Offline")
    else:
        _set_status_text("%d online" % count)

func _leave() -> void:
    for c: Node in _players.get_children():
        c.queue_free()
    _host = 0
    if _is_live():
        multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _redacted_url() -> String:
    if _last_join_url.is_empty():
        return "<none>"
    var safe_url: String = _last_join_url
    var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
    if not user_id.is_empty():
        safe_url = safe_url.replace("u=%s" % user_id, "u=<redacted>")
    return safe_url

func _relay_failure_hint() -> String:
    var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
    var has_user_id: bool = not String(ProjectSettings.get_setting("ziva/multiplayer/user_id", "")).is_empty()
    var has_game_id: bool = not String(ProjectSettings.get_setting("ziva/multiplayer/game_id", "")).is_empty()
    var has_relay_url: bool = not relay_url.is_empty()
    var hints: PackedStringArray = []
    if not has_user_id or not has_game_id or not has_relay_url:
        hints.append("missing ziva/multiplayer project settings; enable multiplayer in Settings → Ziva Cloud")
    hints.append("Ziva Cloud multiplayer may be disabled for this project/account, or the account may be over quota")
    hints.append("relay/network may be unreachable: %s" % (relay_url if has_relay_url else "<missing>"))
    return "; ".join(hints)

func _report_problem(message: String) -> void:
    var full_message: String = "GolfNet: %s" % message
    push_warning(full_message)
    connection_problem.emit(full_message)

# --- Host election -----------------------------------------------------------

func _real_peers() -> Array[int]:
    var out: Array[int] = []
    for p: int in multiplayer.get_peers():
        if p > 1:
            out.append(p)
    return out

# Host = lowest real peer id. include_self_floor lets the caller exclude `me` from
# the candidate set during the connect burst, when get_peers() may not yet list
# lower peers the relay is about to deliver (claiming self there would make this
# peer reject the real host's spawns until it caught up).
func _refresh_host(include_self_floor: bool = true) -> void:
    var cands: Array[int] = _real_peers()
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
    _refresh_status_text()
    _refresh_host(me == 2)
    if me == 2:
        _host_spawn_all()

func _on_peer(id: int) -> void:
    if id <= 1:
        return
    print("GolfNet: peer %d joined room '%s' (host=%d)" % [id, _room, _host])
    _refresh_status_text()
    _refresh_host()
    _host_spawn_all()

func _on_peer_gone(id: int) -> void:
    if _players.has_node("player_%d" % id):
        _players.get_node("player_%d" % id).queue_free()
    # Reactive failover: recompute host from the (now authoritative) roster. If we
    # became the new lowest peer, adopt the spawner and re-spawn everyone present.
    _refresh_status_text()
    _refresh_host()
    if _i_am_host():
        _host_spawn_all()

func _on_conn_failed() -> void:
    var elapsed_msec: int = max(0, Time.get_ticks_msec() - _last_join_started_msec)
    _report_problem("connection to relay failed after %d ms. room='%s', url=%s. Likely causes: %s" % [elapsed_msec, _last_join_room, _redacted_url(), _relay_failure_hint()])
    _leave()
    _set_status_text("Offline")

func _on_server_gone() -> void:
    _report_problem("relay disconnected while in room '%s'. url=%s" % [_last_join_room, _redacted_url()])
    _leave()
    _set_status_text("Offline")

# --- Spawn function (runs on every peer to build the node locally) ------------

func _spawn_player(data: Variant) -> Node:
    var id: int = int(data)
    var p: Node3D = Node3D.new()
    p.name = "player_%d" % id
    p.set_script(load(GHOST_SCRIPT))

    var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
    sync.name = "Sync"
    sync.replication_interval = 0.0  # push every network frame for lowest lag

    var cfg: SceneReplicationConfig = SceneReplicationConfig.new()
    cfg.add_property(NodePath(".:net_pos"))
    cfg.property_set_spawn(NodePath(".:net_pos"), true)
    cfg.property_set_replication_mode(NodePath(".:net_pos"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
    cfg.add_property(NodePath(".:pname"))
    cfg.property_set_spawn(NodePath(".:pname"), true)
    cfg.property_set_replication_mode(NodePath(".:pname"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
    cfg.add_property(NodePath(".:skin_id"))
    cfg.property_set_spawn(NodePath(".:skin_id"), true)
    cfg.property_set_replication_mode(NodePath(".:skin_id"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
    sync.replication_config = cfg
    sync.root_path = NodePath("..")
    p.add_child(sync)
    return p
