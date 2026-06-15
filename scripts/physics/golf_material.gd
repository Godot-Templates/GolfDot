class_name GolfMaterial
extends Resource
## Physical surface properties for a golf collision triangle/mesh.
## Mirrors golf_material_t (friction/restitution/vel_scale) plus the special
## surface flags the solver reads from contacts (water, out-of-bounds).

@export var friction: float = 0.3
@export var restitution: float = 0.4
@export var vel_scale: float = 1.0

## Water surfaces apply a current force instead of an impulse.
@export var is_water: bool = false
## Direction (world space) the water pushes the ball, used when is_water.
@export var water_dir: Vector3 = Vector3.ZERO

## Out-of-bounds surfaces reset the ball to its last start position.
@export var is_out_of_bounds: bool = false
