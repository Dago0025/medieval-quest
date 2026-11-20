extends RefCounted
## Parametri dell'IA (fase 7a): data/regole/ia.cfg e valori predefiniti identici, profili, difficolta', profilo effettivo
## dell'anno. I numeri sono PROVVISORI: i test controllano la coerenza, non i valori scelti.

const W := preload("res://tests/unit/ai_world.gd")


func test_il_file_e_i_valori_predefiniti_coincidono(t: TestContext) -> void:
	var from_file := AiRules.load_file(AiRules.DEFAULT_PATH)
	t.assert_eq(from_file.errors, PackedStringArray(), "errori di lettura di ia.cfg")
	var defaults := AiRules.new()
	t.assert_eq(str(from_file.to_dict()), str(defaults.to_dict()), "ia.cfg = valori predefiniti del codice")


func test_file_mancante_usa_i_predefiniti(t: TestContext) -> void:
	var r := AiRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(r.errors.size(), 1, "un errore segnalato")
	t.assert_eq(r.profiles.size(), 20, "profili predefiniti")


func test_venti_profili_con_tutte_le_chiavi(t: TestContext) -> void:
	var r := AiRules.default_rules()
	t.assert_eq(r.profiles.size(), 20, "17 comportamenti e 3 profili di stato")
	for name in r.profiles:
		var row: Dictionary = r.profiles[name]
		for key in AiRules.PROFILE_KEYS:
			t.assert_true(row.has(key), "%s ha %s" % [name, key])
		t.assert_true(AiRules.TARGET_MODES.has(str(row["bersagli"])), "bersagli di %s" % name)
		t.assert_true(int(row["tassa_max"]) >= 0 and int(row["tassa_max"]) <= 4, "tassa massima di %s" % name)
	for name in ["POVERTY_STRICKEN", "DESPERATE_DEFENCE", "CLOSE_TO_SUPPORT_LIMIT", "POPE", "REBELS", "BARBARIAN_RAIDER"]:
		t.assert_true(r.has_profile(name), name)


func test_livelli_dei_bersagli(t: TestContext) -> void:
	var r := AiRules.default_rules()
	t.assert_eq(r.target_level("POPE"), 0, "il Papato non attacca")
	t.assert_eq(r.target_level("REBELS"), 0, "i ribelli non ricevono ordini")
	t.assert_eq(r.target_level("BARBARIAN_RAIDER"), 3, "i predoni attaccano anche i neutrali")
	t.assert_true(r.target_level("CATHOLIC_EXPANSIONIST") >= r.target_level("CATHOLIC_DEFENSIVE"))
	t.assert_eq(r.target_level("NON_ESISTE"), r.target_level(r.default_profile), "profilo sconosciuto: quello predefinito")


func test_difficolta(t: TestContext) -> void:
	var r := AiRules.default_rules()
	for name in AiRules.DIFFICULTIES:
		var d := r.difficulty_params(name)
		for key in ["aggressivita", "budget", "soglia"]:
			t.assert_true(d.has(key), "%s ha %s" % [name, key])
	var easy := r.difficulty_params("facile")
	var hard := r.difficulty_params("molto_difficile")
	t.assert_true(float(hard["aggressivita"]) > float(easy["aggressivita"]), "piu' aggressiva")
	t.assert_true(float(hard["budget"]) > float(easy["budget"]), "piu' budget")
	t.assert_true(float(hard["soglia"]) < float(easy["soglia"]), "soglia d'attacco piu' bassa")
	t.assert_eq(r.difficulty_params("boh"), r.difficulty_params("normale"), "difficolta' sconosciuta: normale")


func test_profilo_di_base_dallo_startpos(t: TestContext) -> void:
	var s := W.world()
	var ctx := W.context(s)
	t.assert_eq(AiProfiles.base(ctx, W.A), "CATHOLIC_EXPANSIONIST")
	t.assert_eq(AiProfiles.base(ctx, W.G), "BARBARIAN_RAIDER")
	t.assert_eq(AiProfiles.base(ctx, W.P), "POPE")


func test_profilo_effettivo_poverta(t: TestContext) -> void:
	var s := W.world()
	W.set_treasury(s, W.B, -100)
	var ctx := W.context(s)
	t.assert_eq(AiProfiles.effective(ctx, W.B), AiProfiles.POVERTY, "tesoro in rosso")
	W.set_treasury(s, W.B, 20000)
	t.assert_eq(AiProfiles.effective(W.context(s), W.B), "CATHOLIC_DEFENSIVE", "tesoro pieno: il profilo di base")


func test_profilo_effettivo_difesa_disperata(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	W.set_treasury(s, W.B, 20000)
	s.declare_war(W.B, W.A)
	W.put(s, W.B, W.B1, 10)
	W.put(s, W.A, W.A3, 500)   # accanto a B1, molto piu' forte
	t.assert_eq(AiProfiles.effective(W.context(s), W.B), AiProfiles.DESPERATE)


func test_profilo_effettivo_limite_di_mantenimento(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	W.set_treasury(s, W.B, 1000000)
	for i in 80:
		W.put(s, W.B, W.B1, 100)   # mantenimento enorme rispetto al reddito
	var profile := AiProfiles.effective(W.context(s), W.B)
	t.assert_eq(profile, AiProfiles.SUPPORT_LIMIT)


func test_papa_predoni_e_ribelli_non_cambiano_profilo(t: TestContext) -> void:
	var s := W.world()
	W.set_treasury(s, W.P, 0)
	W.set_treasury(s, W.G, 0)
	var ctx := W.context(s)
	t.assert_eq(AiProfiles.effective(ctx, W.P), "POPE")
	t.assert_eq(AiProfiles.effective(ctx, W.G), "BARBARIAN_RAIDER")
