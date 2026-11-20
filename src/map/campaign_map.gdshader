shader_type canvas_item;
// Mappa della campagna: tinta dei proprietari, confini e provincia selezionata.
//
// Il nodo (Sprite2D) mostra MapTex come TEXTURE. Le coordinate dell'immagine
// coincidono con i pixel della bitmap degli indici (index_tex, formato R8).
// table_tex (256x2, vedi RegionMap.build_table) per ogni indice di palette dà:
//   riga 0: colore del proprietario (alfa 0 = nessuna tinta);
//   riga 1: R = provincia selezionata, G = gruppo della regione, B = tipo
//           (0 nessuna, 128 mare, 255 terra).
// Gli indici 2k+2 e 2k+3 hanno lo stesso gruppo: non generano confini.
// Con draw_borders = false lo shader non disegna i confini (né il bordo della provincia
// selezionata): li disegna il livello vettoriale (BorderLayer in scenes/campaign_map.gd).

uniform sampler2D index_tex : filter_nearest, repeat_disable;
uniform sampler2D table_tex : filter_nearest, repeat_disable;
// Mappa del mondo (ADR-077): index_tex e' RG8 (indice = R + 256 G), una voce per regione: il gruppo e' l'indice stesso.
uniform bool index_groups = false;
uniform bool draw_borders = true;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.45;
uniform float border_width_px = 1.5;
uniform vec4 border_color : source_color = vec4(0.07, 0.04, 0.02, 0.85);
uniform float sea_border_alpha : hint_range(0.0, 1.0) = 0.25;
uniform vec4 highlight_color : source_color = vec4(1.0, 0.88, 0.25, 1.0);
uniform float highlight_fill : hint_range(0.0, 1.0) = 0.22;
// Provincia d'arrivo di una pedina trascinata (fase 8): gruppo della regione, -1 = nessuna.
uniform int target_group = -1;
// Stile dell'originale (2026-11-09): nessun riempimento del proprietario; fascia del colore del proprietario lungo i confini
// con le province di altri proprietari; provincia scelta schiarita.
uniform bool original_style = false;
uniform float owner_band_px = 11.0;
uniform float owner_band_alpha : hint_range(0.0, 1.0) = 0.72;
uniform float selected_whiten : hint_range(0.0, 1.0) = 0.42;
uniform vec4 target_color : source_color = vec4(0.55, 0.85, 0.4, 1.0);
uniform float target_fill : hint_range(0.0, 1.0) = 0.38;
// Regioni raggiungibili dalla pedina trascinata (movimento fluido, 2026-11-10): reach_tex 256x1, R = codice x 50 per
// indice di palette (CampaignUiMoves: 1 movimento, 2 via mare, 3 attacco, 4 partenza); il resto della mappa si scurisce.
uniform sampler2D reach_tex : filter_nearest, repeat_disable;
uniform bool reach_on = false;
uniform vec4 reach_move_color : source_color = vec4(0.62, 0.86, 0.42, 1.0);
uniform vec4 reach_sea_color : source_color = vec4(0.45, 0.78, 0.95, 1.0);
uniform vec4 reach_attack_color : source_color = vec4(0.92, 0.32, 0.22, 1.0);
uniform float reach_fill : hint_range(0.0, 1.0) = 0.3;
uniform float reach_dim : hint_range(0.0, 1.0) = 0.3;

int index_at(ivec2 p) {
	ivec2 s = textureSize(index_tex, 0);
	p = clamp(p, ivec2(0), s - ivec2(1));
	vec4 t = texelFetch(index_tex, p, 0);
	return int(t.r * 255.0 + 0.5) + int(t.g * 255.0 + 0.5) * 256;
}

vec4 info_of(int palette_index) {
	return texelFetch(table_tex, ivec2(palette_index, 1), 0);
}

int group_of(vec4 info) {
	return int(info.g * 255.0 + 0.5);
}

int group_at(int palette_index, vec4 info) {
	return index_groups ? palette_index : group_of(info);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	ivec2 size = textureSize(index_tex, 0);
	vec2 p = UV * vec2(size);
	// Texel della bitmap per pixel dello schermo: rende il confine di spessore costante a ogni zoom.
	vec2 per_px = fwidth(p);
	float texels_per_px = max(max(per_px.x, per_px.y), 0.0001);
	float radius = 0.5 * border_width_px * texels_per_px;

	ivec2 cell = ivec2(floor(p));
	int center_index = index_at(cell);
	vec4 center_info = info_of(center_index);
	int center_group = group_at(center_index, center_info);
	vec4 owner = texelFetch(table_tex, ivec2(center_index, 0), 0);
	bool center_selected = center_info.r > 0.5;

	vec3 col = base.rgb;
	if (original_style) {
		if (center_selected) {
			col = mix(col, vec3(0.93, 0.92, 0.96), selected_whiten);
		}
		if (owner.a > 0.0 && center_info.b > 0.9) {
			// fascia del proprietario: c'e' una regione di un altro proprietario (o il mare) entro owner_band_px
			float band = 0.5 * owner_band_px * texels_per_px;
			float hit = 0.0;
			for (int j = 0; j < 8; j++) {
				float a2 = float(j) * 0.7853982;
				ivec2 oc = ivec2(floor(p + vec2(cos(a2), sin(a2)) * band));
				int oi = index_at(oc);
				vec4 other_owner = texelFetch(table_tex, ivec2(oi, 0), 0);
				vec4 other_info2 = info_of(oi);
				bool different = other_info2.b > 0.9 && distance(other_owner.rgb, owner.rgb) > 0.02;
				if (different) {
					hit = 1.0;
				}
			}
			col = mix(col, owner.rgb, hit * owner_band_alpha);
		}
	} else {
		col = mix(base.rgb, owner.rgb, owner.a * tint_strength);
		col = mix(col, highlight_color.rgb, center_info.r * highlight_fill);
	}
	if (reach_on && center_info.b > 0.1) {
		int code = int(texelFetch(reach_tex, ivec2(center_index, 0), 0).r * 255.0 / 50.0 + 0.5);
		if (code == 1) {
			col = mix(col, reach_move_color.rgb, reach_fill);
		} else if (code == 2) {
			col = mix(col, reach_sea_color.rgb, reach_fill);
		} else if (code == 3) {
			col = mix(col, reach_attack_color.rgb, reach_fill);
		} else if (code != 4) {
			col *= 1.0 - reach_dim;
		}
	}
	bool center_target = target_group >= 0 && center_group == target_group;
	if (center_target) {
		col = mix(col, target_color.rgb, target_fill);
	}

	if (draw_borders) {
		// Confine: c'è un texel di un'altra regione entro "radius" (raddoppiato dentro la provincia selezionata).
		float reach = center_selected ? radius * 2.0 : radius;
		float line = 0.0;
		bool on_highlight = false;
		bool on_target = false;
		for (int i = 0; i < 8; i++) {
			float angle = float(i) * 0.7853982;
			vec2 offset = vec2(cos(angle), sin(angle)) * reach;
			ivec2 other_cell = ivec2(floor(p + offset));
			if (other_cell.x == cell.x && other_cell.y == cell.y) {
				continue;
			}
			int other_index = index_at(other_cell);
			vec4 other_info = info_of(other_index);
			int other_group = group_at(other_index, other_info);
			if (other_group != center_group) {
				bool land_involved = center_info.b > 0.9 || other_info.b > 0.9;
				line = max(line, land_involved ? 1.0 : sea_border_alpha);
				if (center_selected || other_info.r > 0.5) {
					on_highlight = true;
				}
				if (center_target || (target_group >= 0 && other_group == target_group)) {
					on_target = true;
				}
			}
		}
		if (on_target) {
			col = mix(col, target_color.rgb, line);
		} else if (on_highlight) {
			col = mix(col, highlight_color.rgb, line * highlight_color.a);
		} else {
			col = mix(col, border_color.rgb, line * border_color.a);
		}
	}
	COLOR = vec4(col, base.a);
}
