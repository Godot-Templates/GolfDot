class_name GolfAudio
extends Node
## Plays Open-Golf's sound effects on the matching gameplay events
## (see golf_audio_start_sound calls in game.c).

const SND_HIT := preload("res://assets/audio/impactPlank_medium_000.ogg")
const SND_IMPACT := preload("res://assets/audio/footstep_grass_004.ogg")
const SND_IN_HOLE := preload("res://assets/audio/confirmation_002.ogg")
const SND_OUT_OF_BOUNDS := preload("res://assets/audio/error_008.ogg")
const SND_WATER := preload("res://assets/audio/in_water.ogg")

var _hit: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _in_hole: AudioStreamPlayer
var _oob: AudioStreamPlayer
var _water: AudioStreamPlayer
var _water_fade: Tween

func _ready() -> void:
    _hit = _make_player(SND_HIT, 0.0)
    _impact = _make_player(SND_IMPACT, 0.0)
    _in_hole = _make_player(SND_IN_HOLE, 0.0)
    _oob = _make_player(SND_OUT_OF_BOUNDS, 0.0)

    # Water is a looping ambience at low volume (vol 0.1 in the original).
    var water_stream: AudioStream = SND_WATER.duplicate()
    if water_stream is AudioStreamOggVorbis:
        (water_stream as AudioStreamOggVorbis).loop = true
    _water = _make_player(water_stream, linear_to_db(0.1))

func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.stream = stream
    p.volume_db = volume_db
    add_child(p)
    return p

func play_hit() -> void:
    _hit.play()

func play_impact() -> void:
    _impact.play()

func play_in_hole() -> void:
    _in_hole.play()

func play_out_of_bounds() -> void:
    _oob.play()

## Start/stop the looping water sound, with a short fade-out on stop (game.c:706).
func set_water(active: bool) -> void:
    if active:
        if _water_fade != null:
            _water_fade.kill()
            _water_fade = null
        _water.volume_db = linear_to_db(0.1)
        if not _water.playing:
            _water.play()
    elif _water.playing and _water_fade == null:
        _water_fade = create_tween()
        _water_fade.tween_property(_water, "volume_db", linear_to_db(0.0001), 0.2)
        _water_fade.tween_callback(_water.stop)
        _water_fade.tween_callback(func() -> void: _water_fade = null)
