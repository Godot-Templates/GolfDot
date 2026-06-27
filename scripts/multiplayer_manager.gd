class_name GolfMultiplayerManager
extends Node
## Lightweight cross-scene multiplayer utilities.
##
## Presence uses Ziva's Model-2 shared-state protocol on its own raw WebSocketPeer
## so it does not interfere with GolfNet's per-hole WebSocketMultiplayerPeer or
## Leaderboard's ZivaState room. Each client heartbeats one tiny key containing
## the hole they are currently playing; level select counts fresh entries.

signal presence_counts_changed(counts: Dictionary)

const PRESENCE_ROOM_ID := "golfdot-presence-v1"
const LEVEL_COUNT := 20
const HEARTBEAT_SECONDS := 5.0
const STALE_SECONDS := 20.0
const _BUFFER_BYTES := 4 * 1024 * 1024
const _STATE_KEY_MAX_BYTES := 1024
const _STATE_SET := 0xF4
const _STATE_UPDATE := 0xF5
const _STATE_SNAPSHOT := 0xF6

var _ws: WebSocketPeer = WebSocketPeer.new()
var _open: bool = false
var _connecting: bool = false
var _session_id: String = ""
var _current_hole: int = 0
var _heartbeat_timer: float = 999.0
var _presence: Dictionary = {}
var _rev: Dictionary = {}
var _counts: Dictionary = {}

func _ready() -> void:
    _session_id = _make_session_id()
    _connect_presence_room()

func _process(delta: float) -> void:
    _poll_presence_socket()
    _heartbeat_timer += delta
    if _open and _heartbeat_timer >= HEARTBEAT_SECONDS:
        _heartbeat_timer = 0.0
        _publish_presence()
    _refresh_counts(false)

## Set the hole this local player is actively playing. Use 0 for menu/off-course.
func set_current_hole(hole: int) -> void:
    _current_hole = clampi(hole, 0, LEVEL_COUNT)
    if _open:
        _publish_presence()

func get_level_counts() -> Dictionary:
    _refresh_counts(false)
    return _counts.duplicate()

func get_level_count(level: int) -> int:
    _refresh_counts(false)
    return int(_counts.get(level, 0))

func _connect_presence_room() -> void:
    if _open or _connecting:
        return
    var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
    var game_id: String = ProjectSettings.get_setting("ziva/multiplayer/game_id", "")
    var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
    if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
        push_warning("Presence: Ziva multiplayer settings missing — enable multiplayer in Settings → Ziva Cloud.")
        return
    _ws = WebSocketPeer.new()
    _ws.inbound_buffer_size = _BUFFER_BYTES
    _ws.outbound_buffer_size = _BUFFER_BYTES
    var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, PRESENCE_ROOM_ID, user_id, game_id]
    var err: int = _ws.connect_to_url(url)
    if err != OK:
        push_warning("Presence: connect_to_url failed (%d)." % err)
        return
    _connecting = true

func _poll_presence_socket() -> void:
    if not _connecting and not _open:
        return
    _ws.poll()
    var state: int = _ws.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if not _open:
            _open = true
            _connecting = false
            _heartbeat_timer = HEARTBEAT_SECONDS
        while _ws.get_available_packet_count() > 0:
            _handle_packet(_ws.get_packet())
    elif state == WebSocketPeer.STATE_CLOSED:
        if _open or _connecting:
            _open = false
            _connecting = false
            push_warning("Presence: socket closed (%d %s)." % [_ws.get_close_code(), _ws.get_close_reason()])

func _publish_presence() -> void:
    if not _open:
        return
    var entry: Dictionary = {
        "hole": _current_hole,
        "name": PlayerProfile.get_player_name(),
        "seen": Time.get_unix_time_from_system(),
    }
    _send_state(_presence_key(), var_to_bytes(entry))

func _send_state(key: String, value: PackedByteArray) -> void:
    var key_bytes: PackedByteArray = key.to_utf8_buffer()
    if key_bytes.is_empty() or key_bytes.size() > _STATE_KEY_MAX_BYTES:
        return
    if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    var frame: PackedByteArray = PackedByteArray()
    frame.append(_STATE_SET)
    frame.append(key_bytes.size() & 0xFF)
    frame.append((key_bytes.size() >> 8) & 0xFF)
    frame.append_array(key_bytes)
    frame.append_array(value)
    var err: int = _ws.send(frame, WebSocketPeer.WRITE_MODE_BINARY)
    if err != OK:
        push_warning("Presence: send failed (%d)." % err)

func _handle_packet(packet: PackedByteArray) -> void:
    if packet.size() < 1:
        return
    match packet[0]:
        _STATE_UPDATE:
            _apply_update(packet)
        _STATE_SNAPSHOT:
            _apply_snapshot(packet)

func _apply_update(packet: PackedByteArray) -> void:
    if packet.size() < 7:
        return
    var rev: int = _u32(packet, 1)
    var key_len: int = _u16(packet, 5)
    if packet.size() < 7 + key_len:
        return
    var key: String = packet.slice(7, 7 + key_len).get_string_from_utf8()
    var value: PackedByteArray = packet.slice(7 + key_len)
    _apply_presence_value(key, value, rev)

func _apply_snapshot(packet: PackedByteArray) -> void:
    if packet.size() < 5:
        return
    var count: int = _u32(packet, 1)
    var offset: int = 5
    for _i: int in count:
        if offset + 6 > packet.size():
            return
        var rev: int = _u32(packet, offset)
        offset += 4
        var key_len: int = _u16(packet, offset)
        offset += 2
        if offset + key_len + 4 > packet.size():
            return
        var key: String = packet.slice(offset, offset + key_len).get_string_from_utf8()
        offset += key_len
        var value_len: int = _u32(packet, offset)
        offset += 4
        if offset + value_len > packet.size():
            return
        var value: PackedByteArray = packet.slice(offset, offset + value_len)
        offset += value_len
        _apply_presence_value(key, value, rev)

func _apply_presence_value(key: String, value: PackedByteArray, rev: int) -> void:
    if not key.begins_with("p:"):
        return
    if int(_rev.get(key, 0)) >= rev:
        return
    var decoded: Variant = bytes_to_var(value)
    if typeof(decoded) != TYPE_DICTIONARY:
        return
    _rev[key] = rev
    _presence[key] = decoded
    _refresh_counts(true)

func _refresh_counts(force_emit: bool) -> void:
    var now: float = Time.get_unix_time_from_system()
    var next_counts: Dictionary = {}
    for i: int in range(1, LEVEL_COUNT + 1):
        next_counts[i] = 0
    for key: Variant in _presence.keys():
        var entry: Dictionary = _presence[key]
        var hole: int = int(entry.get("hole", 0))
        var seen: float = float(entry.get("seen", 0.0))
        if hole >= 1 and hole <= LEVEL_COUNT and now - seen <= STALE_SECONDS:
            next_counts[hole] = int(next_counts[hole]) + 1
    if force_emit or _counts.is_empty() or not _same_counts(next_counts, _counts):
        _counts = next_counts
        presence_counts_changed.emit(_counts.duplicate())

func _same_counts(a: Dictionary, b: Dictionary) -> bool:
    for i: int in range(1, LEVEL_COUNT + 1):
        if int(a.get(i, 0)) != int(b.get(i, 0)):
            return false
    return true

func _presence_key() -> String:
    return "p:%s" % _session_id

func _make_session_id() -> String:
    var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "local")
    return "%s-%d-%d" % [user_id, Time.get_unix_time_from_system(), randi()]

func _u16(bytes: PackedByteArray, offset: int) -> int:
    return bytes[offset] | (bytes[offset + 1] << 8)

func _u32(bytes: PackedByteArray, offset: int) -> int:
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)
