# Leaderboard — global, durable highscore boards for Golfdot.
#
# Registered as an autoload named "Leaderboard" (after ZivaState in the autoload
# order, since it depends on the ZivaState autoload). It owns the game's
# connection to ONE shared durable-object room on the Ziva relay and exposes two
# boards:
#
#   * per-hole   — the lowest stroke count each player has logged on a given hole
#   * overall    — each player's total strokes across ALL holes (lowest = best)
#
# State lives in the relay's Durable Object, so the boards survive every player
# disconnecting (Model 2 — see Ziva "Multiplayer limitations" docs). Each player
# only ever writes keys namespaced to their OWN name, so concurrent submissions
# from different players never clobber each other under last-writer-wins.
#
# Offline / multiplayer-not-enabled: the boards still work locally — they are
# seeded from this device's GolfScores bests so the player always sees their own
# numbers, and everything is pushed up to the relay the moment a connection opens.
#
# ZivaState is reached via the node tree (/root/ZivaState) rather than the
# compile-time autoload global so this script type-checks even before the editor
# has reloaded the autoload registry.
extends Node

const ROOM_ID := "golfdot-leaderboard-v1"
const LEVEL_COUNT := 20
const MAX_ENTRIES := 20

## Fires whenever a board changes (new submission, snapshot on join, or a remote
## peer's write arrives). UI screens connect to this to refresh themselves.
signal updated

var _zs: Node = null
var _connected: bool = false
# level:int -> { player_name:String -> best_strokes:int }
var _hole: Dictionary = {}
# player_name:String -> best_total_strokes:int
var _total: Dictionary = {}

func _ready() -> void:
    _seed_local()
    if not _settings_present():
        # Multiplayer not enabled yet — run local-only. Boards still show this
        # device's scores; nothing is sent to the relay.
        return
    _zs = get_node_or_null("/root/ZivaState")
    if _zs == null:
        push_warning("Leaderboard: ZivaState autoload missing — running local-only.")
        return
    _zs.state_changed.connect(_on_state_changed)
    _zs.connected.connect(_on_connected)
    _zs.connect_room(ROOM_ID)

## True once the relay socket is open and writes are being persisted globally.
func is_online() -> bool:
    return _connected

# The relay can only be reached if the plugin has written the three settings
# (multiplayer enabled in Settings > Ziva Cloud). Until then, run local-only.
func _settings_present() -> bool:
    for k in ["ziva/multiplayer/user_id", "ziva/multiplayer/game_id", "ziva/multiplayer/relay_url"]:
        if String(ProjectSettings.get_setting(k, "")).is_empty():
            return false
    return true

# --- Submitting ------------------------------------------------------------

## Record a player's best for a single hole. `strokes` should already be the
## player's BEST for that hole (we only ever publish improvements upward).
func submit_hole(level: int, player_name: String, strokes: int) -> void:
    var clean := PlayerProfile.sanitize(player_name)
    if clean == "" or strokes < 0 or level < 1 or level > LEVEL_COUNT:
        return
    if _cache_hole(level, clean, strokes) and _connected:
        _zs.set_state(_hole_key(level, clean), var_to_bytes({"n": clean, "s": strokes}))
    updated.emit()

## Record a player's best full-course total (sum of bests across all holes).
func submit_total(player_name: String, total: int) -> void:
    var clean := PlayerProfile.sanitize(player_name)
    if clean == "" or total < 0:
        return
    if _cache_total(clean, total) and _connected:
        _zs.set_state(_total_key(clean), var_to_bytes({"n": clean, "s": total}))
    updated.emit()

# --- Reading boards --------------------------------------------------------

## Ranked entries for a hole: Array of { "name": String, "strokes": int },
## sorted ascending (fewer strokes first), capped at MAX_ENTRIES.
func get_hole_board(level: int) -> Array:
    var board: Dictionary = _hole.get(level, {})
    var arr: Array = []
    for n in board:
        arr.append({"name": String(n), "strokes": int(board[n])})
    return _ranked(arr)

## Ranked entries for the overall (full-course total) board, sorted ascending.
func get_overall_board() -> Array:
    var arr: Array = []
    for n in _total:
        arr.append({"name": String(n), "strokes": int(_total[n])})
    return _ranked(arr)

# --- Internals -------------------------------------------------------------

func _ranked(arr: Array) -> Array:
    arr.sort_custom(_compare_entries)
    if arr.size() > MAX_ENTRIES:
        arr.resize(MAX_ENTRIES)
    return arr

func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
    if int(a["strokes"]) != int(b["strokes"]):
        return int(a["strokes"]) < int(b["strokes"])
    return String(a["name"]) < String(b["name"])

func _hole_key(level: int, clean: String) -> String:
    return "h:%d:%s" % [level, clean]

func _total_key(clean: String) -> String:
    return "t:%s" % clean

# Store a hole result, keeping only the best. Returns true if it changed the
# cached value (a new entry or an improvement) — i.e. worth publishing.
func _cache_hole(level: int, clean: String, strokes: int) -> bool:
    var board: Dictionary = _hole.get(level, {})
    if board.has(clean) and int(board[clean]) <= strokes:
        return false
    board[clean] = strokes
    _hole[level] = board
    return true

func _cache_total(clean: String, total: int) -> bool:
    if _total.has(clean) and int(_total[clean]) <= total:
        return false
    _total[clean] = total
    return true

# Seed the boards from this device's locally-stored bests so the player always
# sees their own scores even before (or without) a relay connection.
func _seed_local() -> void:
    var clean := PlayerProfile.get_player_name()
    if clean == "":
        return
    var total := 0
    var all_done := true
    for i in range(1, LEVEL_COUNT + 1):
        var best := GolfScores.get_best(i)
        if best >= 0:
            _cache_hole(i, clean, best)
            total += best
        else:
            all_done = false
    if all_done:
        _cache_total(clean, total)

# On connect, push everything we have locally up to the durable store so other
# players see this device's scores. Writes are idempotent (best-only), so this
# is safe to do on every (re)connect.
func _on_connected() -> void:
    _connected = true
    var clean := PlayerProfile.get_player_name()
    if clean != "":
        for level in _hole:
            var board: Dictionary = _hole[level]
            if board.has(clean):
                _zs.set_state(_hole_key(int(level), clean), var_to_bytes({"n": clean, "s": int(board[clean])}))
        if _total.has(clean):
            _zs.set_state(_total_key(clean), var_to_bytes({"n": clean, "s": int(_total[clean])}))
    updated.emit()

func _on_state_changed(key: String, value: PackedByteArray, _rev: int) -> void:
    var entry: Variant = bytes_to_var(value)
    if typeof(entry) != TYPE_DICTIONARY:
        return
    var clean := String(entry.get("n", ""))
    var strokes := int(entry.get("s", -1))
    if clean == "" or strokes < 0:
        return
    if key.begins_with("h:"):
        var parts := key.split(":")
        if parts.size() >= 3:
            _cache_hole(int(parts[1]), clean, strokes)
            updated.emit()
    elif key.begins_with("t:"):
        _cache_total(clean, strokes)
        updated.emit()
