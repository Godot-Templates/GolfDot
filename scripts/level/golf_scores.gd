class_name GolfScores
extends RefCounted
## Per-hole par and persisted best-score tracking. Mirrors Open-Golf, which has
## no "par" field in level data but persists the lowest stroke count per hole
## (storage key "stroke_count_level_%d"); we keep the same best-score behaviour
## and add a per-hole par for display.

const LEVEL_COUNT := 20
const SAVE_PATH := "user://golf_scores.cfg"
const SAVE_SECTION := "best"

## Par for each hole (1-based index -> par). Open-Golf ships no par data, so we
## use a standard mini-golf par of 3 per hole.
const PAR: Array[int] = [
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
]

static func get_par(index: int) -> int:
    if index >= 1 and index <= PAR.size():
        return PAR[index - 1]
    return 3

## Best (lowest) recorded stroke count for a hole, or -1 if never completed.
static func get_best(index: int) -> int:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return -1
    return int(cfg.get_value(SAVE_SECTION, str(index), -1))

## Number of holes with any saved completion.
static func get_completed_count() -> int:
    var count: int = 0
    for i: int in range(1, LEVEL_COUNT + 1):
        if get_best(i) >= 0:
            count += 1
    return count

## True once every ported hole has a saved best score.
static func all_completed() -> bool:
    return get_completed_count() >= LEVEL_COUNT

## Sum of per-hole best scores, or -1 until all holes are completed.
static func get_total_best() -> int:
    var total: int = 0
    for i: int in range(1, LEVEL_COUNT + 1):
        var best: int = get_best(i)
        if best < 0:
            return -1
        total += best
    return total

## Record a completed hole's strokes; keeps it only if it beats the stored best.
## Returns true if this was a new best.
static func record(index: int, strokes: int) -> bool:
    var cfg := ConfigFile.new()
    cfg.load(SAVE_PATH)  # ignore error; may not exist yet
    var prev := int(cfg.get_value(SAVE_SECTION, str(index), -1))
    if prev == -1 or strokes < prev:
        cfg.set_value(SAVE_SECTION, str(index), strokes)
        cfg.save(SAVE_PATH)
        return true
    return false
