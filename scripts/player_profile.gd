class_name PlayerProfile
extends RefCounted
## Persists the local player's display name. This is intentionally lightweight and
## local-only for now; when multiplayer lands, this name becomes the identity the
## player carries into a session and onto the highscore boards.
##
## The name is required on first launch (see name_entry.gd / main_menu.gd), so
## has_name() is the gate that decides whether the boot flow forces name entry.

const SAVE_PATH := "user://profile.cfg"
const SAVE_SECTION := "player"
const NAME_KEY := "name"
const SKIN_KEY := "skin"
const DEFAULT_SKIN := "white"

const MIN_NAME_LENGTH := 1
const MAX_NAME_LENGTH := 16

## True once the player has chosen a (non-empty) name.
static func has_player_name() -> bool:
    return get_player_name() != ""

## The stored player name, or "" if none has been set yet.
## NOTE: not named get_name() to avoid colliding with Object.get_name().
static func get_player_name() -> String:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return ""
    return str(cfg.get_value(SAVE_SECTION, NAME_KEY, ""))

## Persist a chosen name. Returns true if it was valid and saved.
## NOTE: not named set_name() to avoid colliding with Object.set_name().
static func set_player_name(value: String) -> bool:
    var clean := sanitize(value)
    if clean == "":
        return false
    var cfg := ConfigFile.new()
    cfg.load(SAVE_PATH)  # ignore error; may not exist yet
    cfg.set_value(SAVE_SECTION, NAME_KEY, clean)
    return cfg.save(SAVE_PATH) == OK

## The selected ball skin id. Falls back to white if unset or no longer valid.
static func get_skin() -> String:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return DEFAULT_SKIN
    var skin: String = str(cfg.get_value(SAVE_SECTION, SKIN_KEY, DEFAULT_SKIN))
    return skin if skin != "" else DEFAULT_SKIN

## Persist a selected ball skin id.
static func set_skin(value: String) -> bool:
    var skin: String = value.strip_edges().to_lower()
    if skin == "":
        return false
    var cfg := ConfigFile.new()
    cfg.load(SAVE_PATH)  # ignore error; may not exist yet
    cfg.set_value(SAVE_SECTION, SKIN_KEY, skin)
    return cfg.save(SAVE_PATH) == OK

## Trim, collapse whitespace and clamp to the allowed length. Returns "" if the
## result is empty (i.e. not an acceptable name).
static func sanitize(value: String) -> String:
    var clean := value.strip_edges()
    if clean.length() > MAX_NAME_LENGTH:
        clean = clean.substr(0, MAX_NAME_LENGTH)
    if clean.length() < MIN_NAME_LENGTH:
        return ""
    return clean

## True if the given string would be accepted by set_name().
static func is_valid(value: String) -> bool:
    return sanitize(value) != ""
