class_name GolfHighscores
extends RefCounted
## Local highscore board data model: top named entries per hole and for the full
## course total. This is the DATA FOUNDATION only — it is deliberately NOT wired
## into gameplay recording, the highscores screen, or any online backend yet. The
## menu's "Highscores" button currently opens a placeholder; this class is what a
## real board (and later, a networked leaderboard) will read from and write to.
##
## Relationship to GolfScores: GolfScores tracks the *local* player's personal
## best per hole (no names). GolfHighscores is the *board* — a ranked list of
## (name, strokes) entries — which is the shape we'll eventually sync to a server
## for multiplayer leaderboards.

const LEVEL_COUNT := 20
const SAVE_PATH := "user://golf_highscores.cfg"
const PER_HOLE_SECTION := "hole"
const TOTAL_SECTION := "course"
const TOTAL_KEY := "total"

## How many ranked entries to keep per board.
const MAX_ENTRIES := 10

## --- Per-hole board -------------------------------------------------------

## Ranked entries for a hole as an Array of { "name": String, "strokes": int },
## sorted ascending by strokes (fewer is better). Empty if nothing recorded.
static func get_hole_scores(index: int) -> Array:
	return _load_board(PER_HOLE_SECTION, str(index))

## Submit a named result for a single hole. Keeps only the top MAX_ENTRIES.
## Returns the entry's rank (1-based) on the board, or -1 if it didn't place.
static func submit_hole_score(index: int, player_name: String, strokes: int) -> int:
	return _submit(PER_HOLE_SECTION, str(index), player_name, strokes)

## --- Full-course (total) board -------------------------------------------

## Ranked entries for the full 18/20-hole course total, sorted ascending.
static func get_course_scores() -> Array:
	return _load_board(TOTAL_SECTION, TOTAL_KEY)

## Submit a named full-course total. Returns 1-based rank, or -1 if it didn't place.
static func submit_course_score(player_name: String, total_strokes: int) -> int:
    return _submit(TOTAL_SECTION, TOTAL_KEY, player_name, total_strokes)

## --- Internals ------------------------------------------------------------

static func _load_board(section: String, key: String) -> Array:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return []
    var raw: Variant = cfg.get_value(section, key, [])
    if raw is Array:
        return (raw as Array).duplicate(true)
    return []

static func _submit(section: String, key: String, player_name: String, strokes: int) -> int:
    var clean_name := PlayerProfile.sanitize(player_name)
    if clean_name == "" or strokes < 0:
        return -1

    var board := _load_board(section, key)
    board.append({"name": clean_name, "strokes": strokes})
    board.sort_custom(_compare_entries)
    if board.size() > MAX_ENTRIES:
        board.resize(MAX_ENTRIES)

    var cfg := ConfigFile.new()
    cfg.load(SAVE_PATH)  # ignore error; may not exist yet
    cfg.set_value(section, key, board)
    cfg.save(SAVE_PATH)

    for i in range(board.size()):
        var e: Dictionary = board[i]
        if e["name"] == clean_name and int(e["strokes"]) == strokes:
            return i + 1
    return -1

static func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
    return int(a["strokes"]) < int(b["strokes"])
