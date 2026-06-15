class_name GolfMath
## Faithful GDScript port of the geometry routines from Open-Golf's
## common/maths.c that the ball physics relies on.

# Contact classification, matching triangle_contact_type_t in maths.h
enum ContactType {
	A,    # vertex a
	B,    # vertex b
	C,    # vertex c
	AB,   # edge a-b
	AC,   # edge a-c
	BC,   # edge b-c
	FACE, # triangle interior
}

## Returns the closest point on triangle (a,b,c) to point p.
## out_type is a single-element array used as an out-parameter that receives
## the ContactType. Direct port of closest_point_point_triangle().
static func closest_point_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3, out_type: Array) -> Vector3:
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ap: Vector3 = p - a
	var d1: float = ab.dot(ap)
	var d2: float = ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		out_type[0] = ContactType.A
		return a

	var bp: Vector3 = p - b
	var d3: float = ab.dot(bp)
	var d4: float = ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		out_type[0] = ContactType.B
		return b

	var vc: float = d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		out_type[0] = ContactType.AB
		var v: float = d1 / (d1 - d3)
		return a + ab * v

	var cp: Vector3 = p - c
	var d5: float = ab.dot(cp)
	var d6: float = ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		out_type[0] = ContactType.C
		return c

	var vb: float = d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		out_type[0] = ContactType.AC
		var w: float = d2 / (d2 - d6)
		return a + ac * w

	var va: float = d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		out_type[0] = ContactType.BC
		var w2: float = (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return b + (c - b) * w2

	out_type[0] = ContactType.FACE
	var denom: float = 1.0 / (va + vb + vc)
	var v3: float = vb * denom
	var w3: float = vc * denom
	return a + ab * v3 + ac * w3

## Port of vec3_line_segments_on_same_line(): true if both segments are colinear.
static func line_segments_on_same_line(ap0: Vector3, ap1: Vector3, bp0: Vector3, bp1: Vector3, eps: float) -> bool:
	var v0: Vector3 = (ap0 - ap1).cross(ap0 - bp0)
	var v1: Vector3 = (ap0 - ap1).cross(ap0 - bp1)
	return v0.length_squared() < eps * eps and v1.length_squared() < eps * eps

## Port of vec3_point_on_line_segment().
static func point_on_line_segment(p: Vector3, a: Vector3, b: Vector3, eps: float) -> bool:
	return distance_squared_point_line_segment(p, a, b) <= eps * eps

## Squared distance from point p to segment [a,b].
static func distance_squared_point_line_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var ap: Vector3 = p - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 < 0.0000001:
		return ap.length_squared()
	var t: float = clampf(ap.dot(ab) / ab_len2, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	return (p - closest).length_squared()

## Port of vec3_reflect_with_restitution(): reflect u about plane normal v,
## scaling the parallel (into-surface) component by restitution e.
static func reflect_with_restitution(u: Vector3, v: Vector3, e: float) -> Vector3:
	var parallel: Vector3 = v * (u.dot(v) / v.dot(v))
	var perpendicular: Vector3 = u - parallel
	return perpendicular - parallel * e
