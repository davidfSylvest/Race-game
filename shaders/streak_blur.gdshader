shader_type canvas_item;

// Directional streak blur + a touch of chromatic aberration, both scaling
// with `intensity` (driven by CameraRig.gd from the player's current speed).
// Reads the already-rendered world+background through SCREEN_TEXTURE, so
// this must sit on a CanvasItem drawn AFTER gameplay but BEFORE the HUD -
// see CameraRig.gd for how the overlay's CanvasLayer is layered to
// guarantee that order regardless of scene tree ordering.
//
// At intensity 0 (low speed) every sample collapses to the same UV, so this
// is a no-op copy of the screen - the effect only exists at real speed,
// never during routine slow movement.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 blur_direction = vec2(1.0, 0.0); // world/screen-space travel direction, unit length
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float max_offset = 0.018; // UV units (0..1 of screen size) the blur reaches at intensity 1.0
uniform float chromatic_amount = 0.0035; // UV units of per-channel separation at intensity 1.0

const int SAMPLES = 6;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 step = blur_direction * intensity * max_offset;
	vec2 chroma = blur_direction * intensity * chromatic_amount;

	vec3 color_sum = vec3(0.0);
	float weight_sum = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1); // 0 (current frame) .. 1 (furthest back along travel)
		float weight = 1.0 - t;
		vec2 offset = step * t;
		color_sum.r += texture(screen_texture, uv - offset - chroma).r * weight;
		color_sum.g += texture(screen_texture, uv - offset).g * weight;
		color_sum.b += texture(screen_texture, uv - offset + chroma).b * weight;
		weight_sum += weight;
	}

	COLOR = vec4(color_sum / weight_sum, 1.0);
}
