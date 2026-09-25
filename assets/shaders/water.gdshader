shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, depth_draw_opaque;

// 허접하지만 예쁜 바다: 얕은 곳은 에메랄드, 깊은 곳은 파랑, 물가엔 거품

uniform vec4 deep_color : source_color = vec4(0.04, 0.3, 0.55, 0.92);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.78, 0.78, 0.5);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float wave_amp = 0.07;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.55 + TIME * 1.2) * 0.5 + sin(wpos.z * 0.75 + TIME * 0.9) * 0.35 + sin((wpos.x + wpos.z) * 1.3 + TIME * 2.1) * 0.15;
	VERTEX.y += w * wave_amp;
	float dx = cos(wpos.x * 0.55 + TIME * 1.2) * 0.55 * 0.5 + cos((wpos.x + wpos.z) * 1.3 + TIME * 2.1) * 1.3 * 0.15;
	float dz = cos(wpos.z * 0.75 + TIME * 0.9) * 0.75 * 0.35 + cos((wpos.x + wpos.z) * 1.3 + TIME * 2.1) * 1.3 * 0.15;
	NORMAL = normalize(vec3(-dx * wave_amp * 3.0, 1.0, -dz * wave_amp * 3.0));
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// 호환 렌더러(웹·구형 PC)는 깊이가 -1..1 범위
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
#else
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	vec3 pixel_pos = upos.xyz / upos.w;
	float water_depth = clamp(VERTEX.z - pixel_pos.z, 0.0, 50.0);
	if (!FRONT_FACING) {
		water_depth = 3.0;
	}
	float t = clamp(water_depth / 2.2, 0.0, 1.0);
	vec4 col = mix(shallow_color, deep_color, t);
	float wobble = 0.08 * sin(TIME * 2.2 + wpos.x * 1.7 + wpos.z * 1.3);
	float foam = 1.0 - smoothstep(0.0, 0.28 + wobble, water_depth);
	// 반짝이 무늬
	vec2 cell = floor(wpos.xz * 1.3);
	float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec2 f = fract(wpos.xz * 1.3) - 0.5;
	float twinkle = smoothstep(0.75, 1.0, sin(TIME * 2.3 + h * 50.0));
	float sparkle = step(0.93, h) * twinkle * (1.0 - smoothstep(0.05, 0.12, length(f)));
	col.rgb = mix(col.rgb, foam_color.rgb, clamp(foam * 0.9 + sparkle * 0.35, 0.0, 1.0));
	ALBEDO = col.rgb;
	ALPHA = clamp(mix(col.a, 1.0, foam * 0.8), 0.0, 1.0);
	ROUGHNESS = 0.12;
	SPECULAR = 0.55;
}
