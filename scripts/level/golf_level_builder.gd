class_name GolfLevelBuilder
extends RefCounted
## Instantiates a parsed GolfLevelData into live Godot nodes under a parent
## Node3D, mirroring how src/golf/game.c turns level entities into the playable
## world (collision via GolfSurface/GolfCollisionWorld, GolfHole, GolfCameraZone,
## decorative models, the camera fly-in target and ball start).
##
## build() returns a Dictionary:
##   { ball_start: Vector3, hole_pos: Vector3, begin_cam_pos: Vector3,
##     holes: Array[GolfHole], movers: Array[Dictionary] }
## `movers` lists animated nodes for the physics/anim layer:
##   { node: Node3D, base_transform: Dictionary, movement: Dictionary, surfaces: Array[GolfSurface] }

const BALL_MESH := preload("res://assets/models/golf_ball.obj")
const HOLE_MESH := preload("res://assets/models/hole.obj")
const ENV_SHADER := preload("res://scripts/level/environment_material.gdshader")

# Fallback material when a model group's material isn't defined in the level
# (mirrors bvh.c: fallback texture material with zeroed physics -> ball stops).
const FALLBACK_FRICTION := 0.0
const FALLBACK_RESTITUTION := 0.0
const FALLBACK_VEL_SCALE := 0.0

var _data: GolfLevelData
var _parent: Node3D
var _golf_mat_cache: Dictionary = {}
var _vis_mat_cache: Dictionary = {}
var _lightmap_tex_cache: Dictionary = {}
var _white_tex: Texture2D
# Ground ShaderMaterials that should get a circular cutout punched where the
# hole is (see environment_material.gdshader). Resolved after the build loop
# once the hole position/radius is known, regardless of entity ordering.
var _ground_punch_mats: Array[ShaderMaterial] = []

static func build(data: GolfLevelData, parent: Node3D) -> Dictionary:
    var b := GolfLevelBuilder.new()
    b._data = data
    b._parent = parent
    return b._build()

func _build() -> Dictionary:
    var result := {
        "ball_start": Vector3.ZERO,
        "hole_pos": Vector3.ZERO,
        "begin_cam_pos": Vector3(6, 5, -4),
        "holes": [] as Array,
        "movers": [] as Array,
    }

    for i in _data.entities.size():
        var e: Dictionary = _data.entities[i]
        var wt := _world_transform(i)
        match e["type"]:
            "geo", "water":
                _build_geo(e, wt, result)
            "hole":
                _build_hole(e, wt, result)
            "ball-start":
                result["ball_start"] = wt["position"]
            "begin_animation":
                result["begin_cam_pos"] = wt["position"]
            "camera_zone":
                _build_camera_zone(e, wt)
            "model":
                _build_model(e, wt, result)
            "group":
                pass  # transform-only; used to parent other entities

    # Punch the hole cutout into the ground material(s) now that we know where
    # the hole is. Open-Golf's solid-ground + stencil-reveal, done via fragment
    # discard so the recessed cup shows through a circle that matches the radius.
    if not result["holes"].is_empty():
        var hole: GolfHole = result["holes"][0]
        for m in _ground_punch_mats:
            m.set_shader_parameter("hole_center", hole.position)
            m.set_shader_parameter("hole_radius", hole.radius)
    return result

# --- World transform (one level of parenting, port of get_world_transform) ----

func _world_transform(idx: int) -> Dictionary:
    var e: Dictionary = _data.entities[idx]
    var local: Dictionary = e["transform"]
    var parent_idx: int = e["parent_idx"]
    var parent := GolfTransformUtil.identity_transform()
    if parent_idx >= 0 and parent_idx < _data.entities.size():
        parent = _data.entities[parent_idx]["transform"]
    return GolfTransformUtil.world_transform(local, parent)

# --- Geo / water --------------------------------------------------------------

func _build_geo(e: Dictionary, wt: Dictionary, result: Dictionary) -> void:
    var is_water: bool = e.get("is_water", false)
    var section: Dictionary = e.get("lightmap_section", {})
    var lmuvs: PackedVector2Array = section.get("uvs", PackedVector2Array())
    var lightmap_name: String = section.get("lightmap_name", "main")
    var has_lm: bool = not lmuvs.is_empty()
    var groups := GolfGeoMesh.build_groups(e["geo"], lmuvs)
    var xform := GolfTransformUtil.to_transform3d(wt)
    var movement: Dictionary = e.get("movement", {"type": GolfTransformUtil.Movement.NONE})
    var is_mover: bool = movement.get("type", GolfTransformUtil.Movement.NONE) != GolfTransformUtil.Movement.NONE
    # Open-Golf marks any surface whose entity is parented (parent_idx >= 0, i.e.
    # part of an environment group) as out-of-bounds (bvh.c ball_test).
    var oob: bool = int(e.get("parent_idx", -1)) >= 0

    var holder: Node3D = null
    if is_mover:
        holder = Node3D.new()
        holder.name = e["name"]
        holder.transform = xform
        _parent.add_child(holder)

    var surfaces: Array[GolfSurface] = []
    for gi in groups.size():
        var group: Dictionary = groups[gi]
        var surf := GolfSurface.new()
        surf.name = "%s_%d" % [e["name"], gi]
        surf.mesh = GolfGeoMesh.group_to_mesh(group, has_lm)
        surf.golf_material = _golf_material(group["material_name"], is_water, group, oob)
        surf.material_override = _visual_material(group["material_name"], lightmap_name if has_lm else "")
        if is_mover:
            holder.add_child(surf)
        else:
            surf.transform = xform
            _parent.add_child(surf)
        surfaces.append(surf)

    if is_mover:
        result["movers"].append({
            "node": holder, "base_transform": wt, "movement": movement, "surfaces": surfaces,
        })

# --- Hole ---------------------------------------------------------------------

func _build_hole(_e: Dictionary, wt: Dictionary, result: Dictionary) -> void:
    var hole := GolfHole.new()
    hole.name = "Hole"
    hole.radius = wt["scale"].x
    hole.position = wt["position"]
    _parent.add_child(hole)

    var cup := MeshInstance3D.new()
    cup.mesh = HOLE_MESH
    cup.scale = wt["scale"]
    # The cup's rim sits exactly at ground level (hole.obj top is at local y=0)
    # and recesses downward. The ground shader discards the matching circle, so
    # the cup is genuinely seen *through* the ground -- not floating on top.
    cup.position = Vector3.ZERO

    # Unshaded near-black interior so the recessed cup reads as a dark hole.
    var hole_mat := StandardMaterial3D.new()
    hole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    hole_mat.albedo_color = Color(0.03, 0.03, 0.03)
    cup.set_surface_override_material(0, hole_mat)

    hole.add_child(cup)
    hole.cup_mesh = cup

    result["holes"].append(hole)
    result["hole_pos"] = wt["position"]

# --- Camera zone --------------------------------------------------------------

func _build_camera_zone(e: Dictionary, wt: Dictionary) -> void:
    var zone := GolfCameraZone.new()
    zone.name = e["name"]
    zone.towards_hole = e.get("towards_hole", false)
    zone.half_extents = wt["scale"]
    zone.transform = Transform3D(Basis(wt["rotation"] as Quaternion), wt["position"] as Vector3)
    _parent.add_child(zone)

# --- Model --------------------------------------------------------------------

func _build_model(e: Dictionary, wt: Dictionary, result: Dictionary) -> void:
    var path: String = e["model_path"]
    var mesh: Mesh = load(path) as Mesh
    if mesh == null:
        return
    var xform := GolfTransformUtil.to_transform3d(wt)
    var movement: Dictionary = e.get("movement", {"type": GolfTransformUtil.Movement.NONE})
    var is_mover: bool = movement.get("type", GolfTransformUtil.Movement.NONE) != GolfTransformUtil.Movement.NONE
    var ignore_physics: bool = e.get("ignore_physics", false)
    # Parented models (trees, surrounding grass platform, etc.) are out-of-bounds.
    var oob: bool = int(e.get("parent_idx", -1)) >= 0

    # Visual node. Open-Golf renders everything with baked/unshaded lighting, so
    # force model surfaces unshaded (true albedo) instead of letting the scene's
    # realtime lights tint them.
    var mi := MeshInstance3D.new()
    mi.name = e["name"]
    mi.mesh = mesh
    mi.transform = xform
    # Open-Golf renders model surfaces using the LEVEL material matched by the
    # obj group name (e.g. "leafsDark", "grass", "woodBarkDark"), NOT the obj's
    # placeholder Kenney-palette Kd colors. Use the env shader with that texture.
    var uv_scale: float = e.get("uv_scale", 1.0)
    for si in mesh.get_surface_count():
        var mat_name := _surface_material_name(mesh, si)
        
        # SPECIAL CASE: flag_red.obj often lacks names if .mtl was missing during import.
        # Kenney's flag_red.obj surfaces are: 0=metal (pole), 1=border (flag).
        if mat_name == "" and ("flag_red.obj" in path):
            mat_name = "metal" if si == 0 else "border"
            
        if _data.materials.has(mat_name):
            mi.set_surface_override_material(si, _visual_material(mat_name, "", uv_scale))
        else:
            var src := mesh.surface_get_material(si)
            if src is StandardMaterial3D:
                var um: StandardMaterial3D = src.duplicate()
                um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
                mi.set_surface_override_material(si, um)
            elif mat_name != "":
                # Fallback for named materials without level-defined textures
                var fm := StandardMaterial3D.new()
                fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
                if mat_name == "metal": fm.albedo_color = Color(0.7, 0.7, 0.7)
                elif mat_name == "border": fm.albedo_color = Color.RED
                mi.set_surface_override_material(si, fm)
    _parent.add_child(mi)

    var surfaces: Array[GolfSurface] = []
    # Collision: non-ignore_physics models contribute triangles. One GolfSurface
    # per mesh surface so each obj material group keeps its own physics material.
    if not ignore_physics:
        for si in mesh.get_surface_count():
            var mat_name := _surface_material_name(mesh, si)
            var surf := GolfSurface.new()
            surf.name = "%s_col_%d" % [e["name"], si]
            var sub := ArrayMesh.new()
            sub.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(si))
            surf.mesh = sub
            surf.golf_material = _golf_material_for_model(mat_name, oob)
            surf.visible = false  # collision only; visuals come from `mi`
            if is_mover:
                surf.transform = Transform3D.IDENTITY
                mi.add_child(surf)
            else:
                surf.transform = xform
                _parent.add_child(surf)
            surfaces.append(surf)

    if is_mover:
        result["movers"].append({
            "node": mi, "base_transform": wt, "movement": movement, "surfaces": surfaces,
        })

func _surface_material_name(mesh: Mesh, si: int) -> String:
    var m := mesh.surface_get_material(si)
    if m != null and not m.resource_name.is_empty():
        return m.resource_name
    return ""

# --- Material helpers ---------------------------------------------------------

func _golf_material(mat_name: String, is_water: bool, group: Dictionary, oob: bool = false) -> GolfMaterial:
    var key := "%s|%s|%s" % [mat_name, is_water, oob]
    if _golf_mat_cache.has(key):
        return _golf_mat_cache[key]
    var gm := GolfMaterial.new()
    var md: Dictionary = _data.materials.get(mat_name, {})
    gm.friction = md.get("friction", 0.3)
    gm.restitution = md.get("restitution", 0.4)
    gm.vel_scale = md.get("vel_scale", 1.0)
    gm.is_out_of_bounds = oob
    if is_water:
        gm.is_water = true
        var wd: Array = group.get("water_dirs", [])
        gm.water_dir = wd[0] if wd.size() > 0 else Vector3.ZERO
    _golf_mat_cache[key] = gm
    return gm

func _golf_material_for_model(mat_name: String, oob: bool = false) -> GolfMaterial:
    var key := "model:%s|%s" % [mat_name, oob]
    if _golf_mat_cache.has(key):
        return _golf_mat_cache[key]
    var gm := GolfMaterial.new()
    var md: Dictionary = _data.materials.get(mat_name, {})
    if md.is_empty():
        gm.friction = FALLBACK_FRICTION
        gm.restitution = FALLBACK_RESTITUTION
        gm.vel_scale = FALLBACK_VEL_SCALE
    else:
        gm.friction = md.get("friction", 0.3)
        gm.restitution = md.get("restitution", 0.4)
        gm.vel_scale = md.get("vel_scale", 1.0)
    gm.is_out_of_bounds = oob
    _golf_mat_cache[key] = gm
    return gm

## Build a ShaderMaterial that reproduces Open-Golf's environment_material:
## fully-baked lighting (unshaded), color = lightmap(UV2) * albedo(UV) * tint.
## `lightmap_name` selects the level's baked lightmap image; empty => flat white.
func _visual_material(mat_name: String, lightmap_name: String, uv_scale: float = 1.0) -> ShaderMaterial:
    var key := "%s|%s|%s" % [mat_name, lightmap_name, uv_scale]
    if _vis_mat_cache.has(key):
        return _vis_mat_cache[key]
    var sm := ShaderMaterial.new()
    sm.shader = ENV_SHADER
    var md: Dictionary = _data.materials.get(mat_name, {})
    var tex_path: String = md.get("texture_path", "")
    if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
        sm.set_shader_parameter("albedo_tex", load(tex_path))
        sm.set_shader_parameter("tint", Color.WHITE)
    else:
        var col = md.get("color", Color(0.6, 0.6, 0.6))
        sm.set_shader_parameter("albedo_tex", _get_white_texture())
        sm.set_shader_parameter("tint", col)
    sm.set_shader_parameter("lightmap_tex", _lightmap_texture(lightmap_name))
    sm.set_shader_parameter("uv_scale", uv_scale)
    # The playable green ("ground"/"default") gets the hole cutout punched into
    # it after the build loop. Other surfaces keep hole_radius at 0 (no discard).
    if mat_name == "ground" or mat_name == "default":
        _ground_punch_mats.append(sm)
    _vis_mat_cache[key] = sm
    return sm

func _lightmap_texture(lightmap_name: String) -> Texture2D:
    if lightmap_name.is_empty():
        return _get_white_texture()
    if _lightmap_tex_cache.has(lightmap_name):
        return _lightmap_tex_cache[lightmap_name]
    var lm: Dictionary = _data.lightmaps.get(lightmap_name, {})
    var images: Array = lm.get("images", [])
    var tex: Texture2D
    if images.size() > 0 and images[0] != null:
        tex = ImageTexture.create_from_image(images[0])
    else:
        tex = _get_white_texture()
    _lightmap_tex_cache[lightmap_name] = tex
    return tex

func _get_white_texture() -> Texture2D:
    if _white_tex == null:
        var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
        img.fill(Color.WHITE)
        _white_tex = ImageTexture.create_from_image(img)
    return _white_tex
