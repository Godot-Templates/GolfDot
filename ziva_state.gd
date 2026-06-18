# ZivaState — Model 2 (durable-object state) client for the Ziva relay.
#
# Registered as an autoload named "ZivaState" (Project Settings > Autoload).
# Opens its OWN raw WebSocketPeer to a room — SEPARATE from any
# WebSocketMultiplayerPeer — and speaks the relay's world/shared-state control
# frames. The relay's Durable Object owns, orders and persists the state; this
# client is a thin codec + local cache.
#
# Why a separate socket: WebSocketMultiplayerPeer gives no hook to send/receive
# non-Godot frames, and a pure Model-2 game (card/turn-based) has no
# MultiplayerSpawner at all. One WebSocketPeer per client, used only for these
# control frames — the relay routes them by their first byte and never confuses
# them with Godot's @rpc/spawn/sync traffic.
extends Node

## Emitted once the socket is open and ready for save_world()/set_state().
signal connected
## A persisted world blob arrived (on join, or after another peer saved one).
signal world_loaded(blob: PackedByteArray)
## The relay committed our save_world() to durable storage.
signal world_save_acked
## A shared-state key changed — locally, from another peer, or from the
## join-time snapshot. `rev` is the relay's monotonic commit order.
signal state_changed(key: String, value: PackedByteArray, rev: int)

# Control opcodes — MUST match the relay's protocol. Their low 3 bits are never
# 7, so the relay can't confuse them with Godot traffic and we dispatch on the
# whole first byte.
const _WORLD_SAVE := 0xF1      # client -> relay: [0xF1][blob]
const _WORLD_LOAD := 0xF2      # relay -> client: [0xF2][blob]
const _WORLD_SAVE_ACK := 0xF3  # relay -> client: [0xF3]
const _STATE_SET := 0xF4       # client -> relay: [0xF4][u16 keyLen][key][value]
const _STATE_UPDATE := 0xF5    # relay -> all:    [0xF5][u32 rev][u16 keyLen][key][value]
const _STATE_SNAPSHOT := 0xF6  # relay -> joiner: [0xF6][u32 count]{entry}*

# The relay reassembles a chunked (>1MB) world into ONE frame, so the inbound
# buffer must clear the ~1MB persistence ceiling with headroom. The default
# WebSocketPeer buffer is 64 KiB — a large world would be silently dropped.
const _BUFFER_BYTES := 4 * 1024 * 1024
const _STATE_KEY_MAX_BYTES := 1024

var _ws := WebSocketPeer.new()
var _open := false
# Local cache + last-applied rev per key for last-writer-wins. The relay assigns
# the rev; we ignore any update whose rev is <= the one we already hold.
var _state: Dictionary = {}   # String -> PackedByteArray
var _rev: Dictionary = {}     # String -> int

## Open the relay socket for `room_id`. Reads the three ziva/multiplayer/*
## settings the plugin writes on enable. Fails loud (no silent default origin).
func connect_room(room_id: String) -> void:
	var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
	var game_id: String = ProjectSettings.get_setting("ziva/multiplayer/game_id", "")
	var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
	if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
		push_error("ZivaState: ziva/multiplayer settings missing — enable multiplayer in Settings > Ziva Cloud.")
		return
	_ws.inbound_buffer_size = _BUFFER_BYTES
	_ws.outbound_buffer_size = _BUFFER_BYTES
	var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, room_id, user_id, game_id]
	var err: int = _ws.connect_to_url(url)
	if err != OK:
		push_error("ZivaState: connect_to_url failed (%d) for %s" % [err, url])

## Persist an opaque world blob for the room (a save file the relay stores
## durably and hands to any future joiner). Emits world_save_acked on commit.
func save_world(blob: PackedByteArray) -> void:
	var frame := PackedByteArray()
	frame.append(_WORLD_SAVE)
	frame.append_array(blob)
	_send(frame)

## Write one shared-state key. The relay orders the write, assigns a rev, and
## broadcasts it back to everyone (including us) as a state_changed.
func set_state(key: String, value: PackedByteArray) -> void:
	var key_bytes := key.to_utf8_buffer()
	if key_bytes.is_empty() or key_bytes.size() > _STATE_KEY_MAX_BYTES:
		push_error("ZivaState.set_state: key must be 1..%d bytes (got %d)" % [_STATE_KEY_MAX_BYTES, key_bytes.size()])
		return
	var frame := PackedByteArray()
	frame.append(_STATE_SET)
	frame.append(key_bytes.size() & 0xFF)
	frame.append((key_bytes.size() >> 8) & 0xFF)
	frame.append_array(key_bytes)
	frame.append_array(value)
	_send(frame)

## Last value seen for `key`, or an empty buffer if unset. Use has_state() to
## tell "unset" apart from "set to empty".
func get_state(key: String) -> PackedByteArray:
	return _state.get(key, PackedByteArray())

func has_state(key: String) -> bool:
	return _state.has(key)

func _send(frame: PackedByteArray) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_error("ZivaState: send before socket open — call connect_room() and await the `connected` signal first.")
		return
	# Explicit binary: the relay drops text frames loudly, so never rely on the
	# peer's default write mode.
	var err: int = _ws.send(frame, WebSocketPeer.WRITE_MODE_BINARY)
	if err != OK:
		push_error("ZivaState: send failed (%d)" % err)

func _process(_delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _open:
			_open = true
			connected.emit()
		while _ws.get_available_packet_count() > 0:
			_handle(_ws.get_packet())
	elif st == WebSocketPeer.STATE_CLOSED:
		if _open:
			_open = false
			push_error("ZivaState: socket closed (%d %s)" % [_ws.get_close_code(), _ws.get_close_reason()])

func _handle(pkt: PackedByteArray) -> void:
	if pkt.size() < 1:
		return
	# Everything that isn't one of our opcodes (the 4-byte peer-id handshake,
	# Godot ADD_PEER/DEL_PEER/RELAY traffic) is not ours — ignore it.
	match pkt[0]:
		_WORLD_LOAD:
			world_loaded.emit(pkt.slice(1))
		_WORLD_SAVE_ACK:
			world_save_acked.emit()
		_STATE_UPDATE:
			_apply_update(pkt)
		_STATE_SNAPSHOT:
			_apply_snapshot(pkt)

func _apply_update(pkt: PackedByteArray) -> void:
	if pkt.size() < 7:
		push_error("ZivaState: STATE_UPDATE too small (%d)" % pkt.size())
		return
	var rev := _u32(pkt, 1)
	var key_len := _u16(pkt, 5)
	if pkt.size() < 7 + key_len:
		push_error("ZivaState: STATE_UPDATE truncated (keyLen %d, size %d)" % [key_len, pkt.size()])
		return
	var key := pkt.slice(7, 7 + key_len).get_string_from_utf8()
	var value := pkt.slice(7 + key_len)
	_apply(key, value, rev)

func _apply_snapshot(pkt: PackedByteArray) -> void:
	if pkt.size() < 5:
		push_error("ZivaState: STATE_SNAPSHOT too small (%d)" % pkt.size())
		return
	var count := _u32(pkt, 1)
	var off := 5
	for _i in count:
		if off + 6 > pkt.size():
			push_error("ZivaState: STATE_SNAPSHOT truncated header @%d" % off)
			return
		var rev := _u32(pkt, off); off += 4
		var key_len := _u16(pkt, off); off += 2
		if off + key_len + 4 > pkt.size():
			push_error("ZivaState: STATE_SNAPSHOT truncated key/valLen @%d" % off)
			return
		var key := pkt.slice(off, off + key_len).get_string_from_utf8(); off += key_len
		var val_len := _u32(pkt, off); off += 4
		if off + val_len > pkt.size():
			push_error("ZivaState: STATE_SNAPSHOT truncated value @%d" % off)
			return
		var value := pkt.slice(off, off + val_len); off += val_len
		_apply(key, value, rev)

# Apply one committed (key, value, rev) under last-writer-wins: a stale or
# replayed rev (<= the rev we already hold for this key) is ignored.
func _apply(key: String, value: PackedByteArray, rev: int) -> void:
	if _rev.get(key, 0) >= rev:
		return
	_rev[key] = rev
	_state[key] = value
	state_changed.emit(key, value, rev)

# Explicit little-endian readers — match the relay's LE encoding without relying
# on PackedByteArray.decode_* endianness defaults.
func _u16(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)

func _u32(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
