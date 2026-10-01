shader_type spatial;
// Katana blade: darker steel body with a wavy, polished temper line (hamon)
// along the edge. The blade mesh's UV.x runs from 0 at the edge to 1 at the
// back, UV.y from 0 at the guard to 1 at the tip.

uniform vec3 steel : source_color = vec3(0.46, 0.49, 0.53);
uniform vec3 hamon : source_color = vec3(0.86, 0.88, 0.9);

void fragment() {
	float wave = 0.27 + 0.035 * sin(UV.y * 72.0) + 0.02 * sin(UV.y * 23.0 + 1.3);
	float h = smoothstep(wave + 0.025, wave - 0.025, UV.x);
	ALBEDO = mix(steel, hamon, h);
	METALLIC = 0.6;
	ROUGHNESS = mix(0.34, 0.2, h);
}
