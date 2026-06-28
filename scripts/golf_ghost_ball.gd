extends Node3D
## A remote player's golf ball, replicated over the Ziva relay.
##
## One of these is spawned per connected peer by GolfNet's host-authority
## MultiplayerSpawner. The node is named "player_<peer_id>"; authority is derived
## from that name in _enter_tree (identical on every peer, no networked handoff).
##
## Motion is reproduced by REPLAYING the shot, not by streaming position: the
## owner broadcasts each shot (start + launch velocity) and reset via RPC, and the
## remote replays it through its own GolfPhysics sim that shares the level's
## collision world. The continuously-replicated `net_pos` is only used for spawn
## placement and a gentle correction once the ball is at rest. We hide our OWN
## ghost — locally we already render the real, physics-driven ball.

const BALL_MESH := preload("res://assets/models/golf_ball.obj")
const BALL_RADIUS := 0.12
const NAME_PLATE_HEIGHT := 0.5

# Replicated authoritative position from the owner. Used for spawn placement and
# for the "position sink" correction once the ball is at rest. It is NOT read for
# motion while a shot is in flight — instead we replay the shot through a local
# GolfPhysics sim (see shot()), so remote balls move with real physics.
var net_pos: Vector3 = Vector3.ZERO
var pname: String = "" : set = _set_pname
var skin_id: String = PlayerProfile.DEFAULT_SKIN:
    set(value):
        skin_id = value.strip_edges().to_lower()
        if skin_id == "":
            skin_id = PlayerProfile.DEFAULT_SKIN
        _apply_skin_color()

var _label: Label3D
var _mesh: MeshInstance3D
# Local physics sim that shares this level's collision world; replays shots.
var _phys: GolfPhysics
var _simulating: bool = false
# Last rendered position — the mesh is rolled by the distance travelled each frame.
var _prev_render_pos: Vector3 = Vector3.ZERO
var _have_render_pos: bool = false

func _enter_tree() -> void:
    # Owner = the peer id encoded in the node name. Set before _ready so authority
    # is correct the instant the node exists on every peer.
    var owner_id: int = int(str(name).trim_prefix("player_"))
    set_multiplayer_authority(owner_id)

func _ready() -> void:
    _mesh = MeshInstance3D.new()
    _mesh.name = "Mesh"
    _mesh.mesh = BALL_MESH
    _mesh.transform = Transform3D(Basis().scaled(Vector3.ONE * BALL_RADIUS), Vector3.ZERO)
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_color = SkinShop.color_for_skin(skin_id)
    _mesh.material_override = mat
    add_child(_mesh)

    _label = GolfPlay.make_name_plate(pname)
    _label.position = Vector3.UP * NAME_PLATE_HEIGHT
    add_child(_label)

    position = net_pos
    _prev_render_pos = net_pos
    _have_render_pos = true

    # Our own ghost is hidden (we already render our real, physics-driven ball)
    # and is never simulated — we only broadcast shots/positions from it.
    if is_multiplayer_authority():
        visible = false
        return

    # Remote ghost: build a sim that SHARES this level's collision world so a
    # replayed shot behaves exactly like the real ball does for its owner.
    var scene: Node = get_tree().current_scene
    if scene is GolfPlay:
        _phys = scene.make_ghost_physics()
        _phys.place_ball(net_pos)

func _physics_process(delta: float) -> void:
    if is_multiplayer_authority():
        return
    var render_pos: Vector3 = position
    if _simulating and _phys != null:
        # Replay the shot locally for smooth, physical motion.
        _phys.update(delta)
        render_pos = _phys.ball_draw_pos
        if not _phys.ball_is_moving:
            _simulating = false
    else:
        # At rest: ease onto the authoritative position (the occasional sink).
        render_pos = position.lerp(net_pos, clampf(delta * 12.0, 0.0, 1.0))
        if _phys != null:
            _phys.ball_pos = render_pos
            _phys.ball_draw_pos = render_pos

    if _have_render_pos:
        _roll(render_pos - _prev_render_pos)
    position = render_pos
    _prev_render_pos = render_pos
    _have_render_pos = true

# --- Shot events broadcast by the owning peer --------------------------------

## Begin replaying a shot from `start` with launch velocity `vel`.
@rpc("authority", "call_remote", "reliable")
func shot(start: Vector3, vel: Vector3) -> void:
    if _phys == null:
        return
    _phys.place_ball(start)
    _phys.launch(vel)
    position = start
    _prev_render_pos = start
    _simulating = true

## Instantly (re)place the ball — tee resets and out-of-bounds respots, where a
## smooth glide across the green would look wrong.
@rpc("authority", "call_remote", "reliable")
func place(pos: Vector3) -> void:
    net_pos = pos
    _simulating = false
    position = pos
    _prev_render_pos = pos
    if _phys != null:
        _phys.place_ball(pos)

# Roll the visible mesh by the horizontal distance travelled this frame, about the
# axis perpendicular to motion, so it tumbles like a real ball. The root only
# translates, so the nameplate stays upright.
func _roll(moved: Vector3) -> void:
    if _mesh == null:
        return
    var horizontal := Vector3(moved.x, 0.0, moved.z)
    var dist := horizontal.length()
    if dist < 0.0001:
        return
    var axis := Vector3.UP.cross(horizontal / dist)
    if axis.length() < 0.0001:
        return
    _mesh.global_rotate(axis.normalized(), dist / BALL_RADIUS)

func _set_pname(value: String) -> void:
    pname = value
    if _label != null:
        _label.text = value if value.strip_edges() != "" else "Player"

func _apply_skin_color() -> void:
    if _mesh == null:
        return
    var mat: StandardMaterial3D = _mesh.material_override as StandardMaterial3D
    if mat == null:
        mat = StandardMaterial3D.new()
        _mesh.material_override = mat
    mat.albedo_color = SkinShop.color_for_skin(skin_id)
