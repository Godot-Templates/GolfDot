class_name GolfPhysics
extends RefCounted
## Faithful port of Open-Golf's deterministic ball solver (_physics_tick in
## src/golf/game.c) plus the fixed-timestep accumulator and render
## interpolation from golf_game_update. Run a level's collision through this
## instead of a generic physics engine to preserve the original feel.

const EPS := 0.001
const MAX_NUM_CONTACTS := 8
const PHYSICS_DT := 1.0 / 120.0
const GRAVITY := -9.8

# --- Tuning constants (ported from data/config/game.cfg) ---
const PHYSICS_HOLE_FORCE_DISTANCE := 0.5
const PHYSICS_HOLE_FORCE := 0.05
const PHYSICS_IN_HOLE_DELTA := Vector3(0, -0.65, 0)
const PHYSICS_IN_HOLE_RADIUS := 0.5
const PHYSICS_BALL_ROT_SCALE := 0.5
const PHYSICS_WATER_MAX_SPEED := 4.0
const PHYSICS_WATER_SPEED := 2.5
const PHYSICS_KILL_Y := -10.0

# --- World references ---
var world: GolfCollisionWorld
var holes: Array[GolfHole] = []

# --- Ball state (mirrors game.ball) ---
var ball_radius: float = 0.12
var ball_pos: Vector3 = Vector3.ZERO
var ball_draw_pos: Vector3 = Vector3.ZERO
var ball_start_pos: Vector3 = Vector3.ZERO   # reset target for out-of-bounds
var ball_vel: Vector3 = Vector3.ZERO
var ball_rot_vec: Vector3 = Vector3.ZERO
var ball_rot_vel: float = 0.0
var ball_orientation: Quaternion = Quaternion.IDENTITY
var ball_is_moving: bool = false
var ball_is_in_hole: bool = false
var ball_is_in_water: bool = false
var ball_is_out_of_bounds: bool = false
var ball_time_going_slow: float = 0.0
var ball_time_since_impact_sound: float = 0.0

# --- Accumulator state ---
var _time_behind: float = 0.0
var t: float = 0.0

# --- Debug ---
var last_num_contacts: int = 0

## Signals surfaced for sound/vfx hooks (so callers don't dig into the solver).
signal impact_sound
signal hit_water

func place_ball(p: Vector3) -> void:
    ball_pos = p
    ball_draw_pos = p
    ball_start_pos = p
    ball_vel = Vector3.ZERO
    ball_rot_vel = 0.0
    ball_rot_vec = Vector3.ZERO
    ball_orientation = Quaternion.IDENTITY
    ball_is_moving = false
    ball_is_in_hole = false
    ball_is_out_of_bounds = false
    ball_time_going_slow = 0.0

func launch(velocity: Vector3) -> void:
    ball_vel = velocity
    ball_is_moving = true
    ball_start_pos = ball_pos

## Advance the simulation by a frame dt, running fixed 120Hz ticks and
## interpolating draw_pos. Port of the relevant part of golf_game_update().
func update(dt: float) -> void:
    t += dt
    _time_behind += dt
    var bp_prev := ball_pos
    var num_ticks := 0
    while _time_behind >= 0.0 and num_ticks < 5:
        bp_prev = ball_pos
        _physics_tick(PHYSICS_DT)
        _time_behind -= PHYSICS_DT
        num_ticks += 1
    while _time_behind >= 0.0:
        _time_behind -= PHYSICS_DT
    var alpha := -_time_behind / PHYSICS_DT
    ball_draw_pos = ball_pos * (1.0 - alpha) + bp_prev * alpha

func _physics_tick(dt: float) -> void:
    var bp := ball_pos
    var br := ball_radius
    var bv := ball_vel
    var bs := bv.length()

    # Animate moving surfaces to the current time before collision (mirrors the
    # per-tick dynamic_bvh rebuild in game.c's _physics_tick).
    if world != null and world.mover_count() > 0:
        world.update_movers(t)

    # Find the closest hole + a hole the ball is currently inside of.
    var dist_to_hole := INF
    var dir_to_hole := Vector3.ZERO
    var hole_pos := Vector3.ZERO
    var close_hole: GolfHole = null
    for hole in holes:
        var hp := hole.get_hole_position()
        var dist := hp.distance_to(bp)
        if dist <= hole.radius:
            close_hole = hole
        if dist < dist_to_hole:
            dist_to_hole = dist
            dir_to_hole = (hp - bp).normalized()
            hole_pos = hp

    # Gather contacts.
    var contacts: Array = []
    if close_hole != null:
        _gather_hole_contacts(close_hole, bp, br, bs, contacts)
    else:
        world.ball_test(bp, br, contacts)

    last_num_contacts = contacts.size()

    # Sort contacts (port of _ball_contact_cmp).
    contacts.sort_custom(_contact_compare)

    # Pull toward the hole when close and touching something.
    if dist_to_hole < PHYSICS_HOLE_FORCE_DISTANCE and contacts.size() > 0:
        bv += dir_to_hole * PHYSICS_HOLE_FORCE

    _filter_contacts(contacts)

    # Resolve impulses.
    for contact in contacts:
        if contact.is_ignored or contact.is_water:
            continue
        var n: Vector3 = contact.normal
        var vr: Vector3 = bv - contact.velocity
        contact.cull_dot = n.dot(vr.normalized())
        if contact.cull_dot > EPS:
            contact.is_ignored = true
            continue
        var e: float = contact.restitution
        var v_scale: float = contact.vel_scale
        var imp: float = -(1.0 + e) * vr.dot(n)
        contact.impulse_mag = imp
        bv += n * imp
        bv *= v_scale

        ball_rot_vel = bv.length() / (PI * ball_radius)
        ball_rot_vec = n.cross(bv).normalized()

        var tang: Vector3 = bv - n * bv.dot(n)
        if tang.length() > EPS:
            tang = tang.normalized()
            var jt: float = -vr.dot(tang)
            if absf(jt) > EPS:
                var friction: float = contact.friction
                if jt > imp * friction:
                    jt = imp * friction
                elif jt < -imp * friction:
                    jt = -imp * friction
                bv += tang * jt

        if contact.impulse_mag > 1.0 and contact.cull_dot < -0.15:
            if ball_time_since_impact_sound > 0.1:
                impact_sound.emit()
                ball_time_since_impact_sound = 0.0
    ball_time_since_impact_sound += dt

    # Gravity + integrate.
    bv += Vector3(0, GRAVITY * dt, 0)
    bp += bv * dt

    # Positional penetration correction.
    for contact in contacts:
        if contact.is_ignored or contact.is_water:
            continue
        var pen: float = maxf(contact.penetration, 0.0)
        bp += contact.normal * (pen * 0.5)

    # Water currents.
    ball_is_in_water = false
    for contact in contacts:
        if contact.is_ignored or not contact.is_water:
            continue
        var water_vel: Vector3 = contact.water_dir * PHYSICS_WATER_MAX_SPEED
        bv += (water_vel - bv) * (PHYSICS_WATER_SPEED * dt)
        ball_is_in_water = true

    # Slow / stop tracking.
    if bv.length() < 0.1:
        ball_time_going_slow += dt
    else:
        ball_time_going_slow = 0.0

    if not ball_is_moving and bv.length() > 0.1:
        ball_is_moving = true
    if ball_is_moving:
        ball_pos = bp
        ball_vel = bv
        ball_rot_vel = ball_rot_vel - dt * ball_rot_vel * PHYSICS_BALL_ROT_SCALE
        ball_orientation = (Quaternion(ball_rot_vec, ball_rot_vel * dt) * ball_orientation).normalized() \
            if ball_rot_vec.length_squared() > EPS else ball_orientation
        if ball_time_going_slow > 0.5:
            ball_is_moving = false

    # In-hole check.
    var in_hole_check := hole_pos + PHYSICS_IN_HOLE_DELTA
    if in_hole_check.distance_to(bp) < PHYSICS_IN_HOLE_RADIUS:
        ball_is_in_hole = true

    # Out-of-bounds via contacts.
    for contact in contacts:
        if contact.is_out_of_bounds:
            ball_is_out_of_bounds = true

    if ball_is_in_water:
        hit_water.emit()

    # Kill plane.
    if ball_pos.y < PHYSICS_KILL_Y:
        ball_is_out_of_bounds = true

## Port of the close_hole branch: collide against the cup mesh with the
## special per-contact-type restitution/friction.
func _gather_hole_contacts(hole: GolfHole, bp: Vector3, br: float, bs: float, contacts: Array) -> void:
    var tris := hole.get_cup_triangles()
    var out_type: Array = [GolfMath.ContactType.FACE]
    for i in range(0, tris.size() - 2, 3):
        var a := tris[i]
        var b := tris[i + 1]
        var c := tris[i + 2]
        var cp := GolfMath.closest_point_on_triangle(bp, a, b, c, out_type)
        var dist := bp.distance_to(cp)
        if dist < br:
            var type: int = out_type[0]
            var restitution: float
            var friction: float
            var vel_scale: float
            if type == GolfMath.ContactType.AB or type == GolfMath.ContactType.AC or type == GolfMath.ContactType.BC:
                restitution = 0.4
                if bs > 2.0:
                    friction = 1.0
                    vel_scale = 0.95
                else:
                    friction = 0.0
                    vel_scale = 1.0
            else:
                restitution = 0.5
                friction = 0.5
                vel_scale = 1.0
            if contacts.size() < MAX_NUM_CONTACTS:
                contacts.append(GolfContact.make(a, b, c, Vector3.ZERO, bp, br, cp, dist,
                    restitution, friction, vel_scale, type, false, Vector3.ZERO, false))

## Port of _ball_contact_cmp: sort by distance, then vel_scale, then restitution.
func _contact_compare(bc0: GolfContact, bc1: GolfContact) -> bool:
    if bc0.distance != bc1.distance:
        return bc0.distance < bc1.distance
    if bc0.vel_scale != bc1.vel_scale:
        return bc0.vel_scale > bc1.vel_scale
    return bc0.restitution < bc1.restitution

## Port of the contact-filtering block: keep all face contacts, drop redundant
## edge contacts colinear with a kept triangle edge, drop redundant point
## contacts lying on a kept edge.
func _filter_contacts(contacts: Array) -> void:
    var processed: Array[Vector3] = []

    for contact in contacts:
        if contact.is_ignored or contact.type != GolfMath.ContactType.FACE:
            continue
        processed.append(contact.triangle_a)
        processed.append(contact.triangle_b)
        processed.append(contact.triangle_c)

    for contact in contacts:
        if contact.is_ignored:
            continue
        var ct: int = contact.type
        if ct != GolfMath.ContactType.AB and ct != GolfMath.ContactType.AC and ct != GolfMath.ContactType.BC:
            continue
        var e0 := Vector3.ZERO
        var e1 := Vector3.ZERO
        if ct == GolfMath.ContactType.AB:
            e0 = contact.triangle_a; e1 = contact.triangle_b
        elif ct == GolfMath.ContactType.AC:
            e0 = contact.triangle_a; e1 = contact.triangle_c
        else:
            e0 = contact.triangle_b; e1 = contact.triangle_c
        var j := 0
        while j < processed.size():
            var a := processed[j]
            var b := processed[j + 1]
            var c := processed[j + 2]
            if GolfMath.line_segments_on_same_line(a, b, e0, e1, EPS) \
                or GolfMath.line_segments_on_same_line(a, c, e0, e1, EPS) \
                or GolfMath.line_segments_on_same_line(b, c, e0, e1, EPS):
                contact.is_ignored = true
                break
            j += 3
        processed.append(contact.triangle_a)
        processed.append(contact.triangle_b)
        processed.append(contact.triangle_c)

    for contact in contacts:
        if contact.is_ignored:
            continue
        var ct: int = contact.type
        if ct != GolfMath.ContactType.A and ct != GolfMath.ContactType.B and ct != GolfMath.ContactType.C:
            continue
        var p := Vector3.ZERO
        if ct == GolfMath.ContactType.A:
            p = contact.triangle_a
        elif ct == GolfMath.ContactType.B:
            p = contact.triangle_b
        else:
            p = contact.triangle_c
        var j := 0
        while j < processed.size():
            var a := processed[j]
            var b := processed[j + 1]
            var c := processed[j + 2]
            if GolfMath.point_on_line_segment(p, a, b, EPS) \
                or GolfMath.point_on_line_segment(p, a, c, EPS) \
                or GolfMath.point_on_line_segment(p, b, c, EPS):
                contact.is_ignored = true
                break
            j += 3
        processed.append(contact.triangle_a)
        processed.append(contact.triangle_b)
        processed.append(contact.triangle_c)
