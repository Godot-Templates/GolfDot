class_name GolfContact
extends RefCounted
## A single ball-vs-triangle contact. Mirrors golf_ball_contact_t plus the
## transient fields the solver mutates while resolving (is_ignored, etc).

var is_water: bool = false
var is_out_of_bounds: bool = false
var is_ignored: bool = false

var position: Vector3              # closest point on triangle
var normal: Vector3               # contact normal (face normal, or bp-cp for edge/vertex)
var triangle_normal: Vector3
var velocity: Vector3             # surface velocity (moving platforms)
var triangle_a: Vector3
var triangle_b: Vector3
var triangle_c: Vector3
var restitution: float
var friction: float
var vel_scale: float
var type: int                     # GolfMath.ContactType
var penetration: float
var water_dir: Vector3 = Vector3.ZERO
var distance: float               # ball-center to contact distance (used for sorting)

# Transient solver fields (debug / resolution)
var cull_dot: float = 0.0
var impulse_mag: float = 0.0

## Direct port of golf_ball_contact().
static func make(a: Vector3, b: Vector3, c: Vector3, vel: Vector3, bp: Vector3, br: float,
		cp: Vector3, dist: float, p_restitution: float, p_friction: float, p_vel_scale: float,
		p_type: int, p_is_water: bool, p_water_dir: Vector3, p_is_out_of_bounds: bool) -> GolfContact:
	var contact := GolfContact.new()
	contact.is_water = p_is_water
	contact.is_ignored = false
	contact.position = cp
	contact.triangle_normal = (b - a).cross(c - a).normalized()
	# The C original trusts mesh winding for outward normals. Godot meshes
	# (BoxMesh, imported OBJ) may be wound either way, so orient the face normal
	# toward the ball - always correct for a ball outside solid geometry.
	if contact.triangle_normal.dot(bp - cp) < 0.0:
		contact.triangle_normal = -contact.triangle_normal
	if p_type == GolfMath.ContactType.FACE:
		contact.normal = contact.triangle_normal
	else:
		contact.normal = (bp - cp).normalized()
	contact.velocity = vel
	contact.triangle_a = a
	contact.triangle_b = b
	contact.triangle_c = c
	contact.restitution = p_restitution
	contact.friction = p_friction
	contact.vel_scale = p_vel_scale
	contact.type = p_type
	contact.penetration = br - dist
	contact.water_dir = p_water_dir
	contact.is_out_of_bounds = p_is_out_of_bounds
	contact.distance = dist
	return contact
