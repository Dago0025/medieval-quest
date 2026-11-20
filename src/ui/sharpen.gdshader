shader_type canvas_item;
// Nitidezza adattiva (sul modello del Contrast Adaptive Sharpening) per le immagini piccole dell'originale mostrate piu'
// grandi con il filtro lineare: alza il contrasto locale senza aloni dove il contrasto e' gia' alto. Fase 8, UiTheme.picture.

uniform float strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	vec3 n = texture(TEXTURE, UV + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(TEXTURE, UV + vec2(0.0, px.y)).rgb;
	vec3 e = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(TEXTURE, UV + vec2(-px.x, 0.0)).rgb;
	vec3 mn = min(c.rgb, min(min(n, s), min(e, w)));
	vec3 mx = max(c.rgb, max(max(n, s), max(e, w)));
	// piu' il contrasto locale e' basso, piu' si affila
	vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
	float peak = -1.0 / mix(8.0, 5.0, strength);
	vec3 wgt = amp * peak;
	vec3 outc = (c.rgb + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt);
	COLOR = vec4(clamp(outc, 0.0, 1.0), c.a) * COLOR;
}
