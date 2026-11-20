shader_type canvas_item;
// Proietta la vista piatta della plancia (SubViewport) sullo schermo come se fosse vista da
// una camera inclinata. Stessa formula di MapProjection (src/map/map_projection.gd):
//   d = 1 + (k - 1) * sy;  u = 0.5 + (sx - 0.5) / d;  v = k * sy / d
// In alto la mappa è rimpicciolita fino a k*k volte: quattro campioni per pixel evitano lo
// sfarfallio dei confini sottili. Dove la vista piatta è trasparente (fuori dalla mappa)
// compare il colore del tavolo; una leggera foschia in alto suggerisce la distanza.

uniform sampler2D world_tex : filter_linear, repeat_disable;
uniform float tilt = 1.0;
uniform vec4 table_color : source_color = vec4(0.10, 0.08, 0.06, 1.0);
uniform vec4 haze_color : source_color = vec4(0.62, 0.68, 0.74, 1.0);
uniform float haze = 0.18;

vec2 to_flat(vec2 s) {
	float d = 1.0 + (tilt - 1.0) * s.y;
	return vec2(0.5 + (s.x - 0.5) / d, tilt * s.y / d);
}

vec4 sample_world(vec2 f) {
	if (f.x < 0.0 || f.x > 1.0 || f.y < 0.0 || f.y > 1.0) {
		return vec4(0.0);
	}
	return texture(world_tex, f);
}

void fragment() {
	vec2 s = UV;
	vec4 c;
	if (tilt <= 1.0001) {
		c = sample_world(s);
	} else {
		vec2 f = to_flat(s);
		vec2 dx = dFdx(f) * 0.25;
		vec2 dy = dFdy(f) * 0.25;
		c = (sample_world(f - dx - dy) + sample_world(f + dx - dy)
			+ sample_world(f - dx + dy) + sample_world(f + dx + dy)) * 0.25;
	}
	vec3 col = mix(table_color.rgb, c.rgb, c.a);
	if (tilt > 1.0001) {
		float far = 1.0 - s.y;
		col = mix(col, haze_color.rgb, haze * far * far * clamp((tilt - 1.0) / 0.6, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
