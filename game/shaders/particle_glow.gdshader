// Additive, camera-facing glow for lantern halos (and, later, embers and
// sparks). The instance or particle colour (COLOR) sets the hue and the fade;
// energy pushes it bright. toward_camera pulls the quad that many metres
// toward the camera, so a halo centred inside a lantern isn't hidden by the
// lantern's stone.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float energy = 3.0;
uniform float toward_camera = 0.0;

void vertex() {
	// Face the camera, keeping the model's scale.
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX[3].xyz -= normalize(MODELVIEW_MATRIX[3].xyz) * toward_camera;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.35, d);
	float halo = 1.0 - smoothstep(0.2, 1.0, d);
	ALBEDO = COLOR.rgb * energy * (core * 0.7 + halo * 0.3);
	ALPHA = COLOR.a * halo;
}
