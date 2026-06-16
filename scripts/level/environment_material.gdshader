shader_type spatial;
// Faithful port of Open-Golf's environment_material.glsl: fully baked lighting
// (unshaded), final color = lightmap(UV2) * albedo(uv_scale * UV) * tint.
// Plus a hole "punch": Open-Golf keeps the ground solid and uses a stencil pass
// (hole-cover.obj -> hole.obj) to reveal the recessed cup. We replicate the same
// visual by discarding ground fragments inside the hole circle, so the sunken
// cup mesh shows through a pixel-perfect circular cutout that lines up exactly
// with the physics hole radius. Only the ground material sets hole_radius > 0.
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// Lightmap is a linear GI intensity (single channel), NOT an sRGB color.
uniform sampler2D lightmap_tex : filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float uv_scale = 1.0;
// World-space hole center + radius. hole_radius <= 0 disables the cutout.
uniform vec3 hole_center = vec3(0.0, -99999.0, 0.0);
uniform float hole_radius = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (hole_radius > 0.0) {
		vec2 d = v_world.xz - hole_center.xz;
		if (dot(d, d) < hole_radius * hole_radius) {
			discard;
		}
	}
	float gi = texture(lightmap_tex, UV2).x;
	vec3 color = texture(albedo_tex, uv_scale * UV).rgb * tint.rgb;
	ALBEDO = gi * color;
}
