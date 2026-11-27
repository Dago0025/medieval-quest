extends RefCounted
## ADR-144: controllo delle nuove versioni su GitHub. Si provano solo le parti pure (versioni, risposta dell'API,
## scelta di proporre o no); la richiesta HTTP vera non parte nei test.


func test_versione_del_gioco(t: TestContext) -> void:
	var v := UpdateCheck.current_version()
	t.assert_true(UpdateCheck.parse_version(v).size() in [3, 4], "config/version in project.godot nel formato A.B.C o A.B.C.D: %s" % v)


func test_lettura_delle_versioni(t: TestContext) -> void:
	t.assert_eq(UpdateCheck.parse_version("v2026.11.27"), PackedInt32Array([2026, 11, 27]))
	t.assert_eq(UpdateCheck.parse_version("2026.12.3"), PackedInt32Array([2026, 12, 3]))
	t.assert_eq(UpdateCheck.parse_version("V2026.11.27-beta"), PackedInt32Array([2026, 11, 27]), "suffisso ignorato")
	t.assert_true(UpdateCheck.parse_version("ultima").is_empty())
	t.assert_true(UpdateCheck.parse_version("").is_empty())


func test_confronto_delle_versioni(t: TestContext) -> void:
	t.assert_true(UpdateCheck.is_newer("v2026.11.28", "2026.11.27"))
	t.assert_true(UpdateCheck.is_newer("v2026.12.1", "2026.11.27"), "dicembre dopo novembre anche con meno cifre")
	t.assert_true(UpdateCheck.is_newer("2027.1.2", "2026.12.31"))
	t.assert_false(UpdateCheck.is_newer("v2026.11.27", "2026.11.27"), "stessa versione")
	t.assert_false(UpdateCheck.is_newer("v2026.11.20", "2026.11.27"), "release piu' vecchia (es. ritirata)")
	t.assert_true(UpdateCheck.is_newer("2026.11.27.1", "2026.11.27"), "numero in piu'")
	t.assert_false(UpdateCheck.is_newer("bozza", "2026.11.27"))


func test_risposta_dell_api(t: TestContext) -> void:
	var json := {
		"tag_name": "v2026.12.03", "name": "Medieval Quest 2026.12.03", "draft": false, "prerelease": false,
		"html_url": "https://github.com/Dago0025/medieval-quest/releases/tag/v2026.12.03",
		"published_at": "2026-12-03T18:00:00Z",
		"assets": [
			{"name": "note.txt", "browser_download_url": "https://github.com/x/note.txt"},
			{"name": "MedievalQuest-Setup-2026.12.03.exe", "browser_download_url": "https://github.com/x/MedievalQuest-Setup-2026.12.03.exe"},
		],
	}
	var info := UpdateCheck.parse_release(json)
	t.assert_eq(str(info["versione"]), "2026.12.03")
	t.assert_eq(str(info["installer"]), "https://github.com/x/MedievalQuest-Setup-2026.12.03.exe", "il primo allegato .exe")
	t.assert_eq(str(info["data"]), "2026-12-03")
	t.assert_true(str(info["pagina"]).ends_with("/v2026.12.03"))
	json["assets"] = []
	t.assert_eq(str(UpdateCheck.parse_release(json)["installer"]), "", "senza installer si apre la pagina")
	json["draft"] = true
	t.assert_true(UpdateCheck.parse_release(json).is_empty(), "bozza ignorata")
	t.assert_true(UpdateCheck.parse_release({"message": "Not Found"}).is_empty(), "repo privata o inesistente")
	t.assert_true(UpdateCheck.parse_release(null).is_empty(), "JSON non valido")
	t.assert_true(UpdateCheck.parse_release([1, 2]).is_empty())


func test_quando_proporre(t: TestContext) -> void:
	var info := {"versione": "2026.12.03"}
	t.assert_true(UpdateCheck.should_offer(info, "2026.11.27", ""))
	t.assert_false(UpdateCheck.should_offer(info, "2026.11.27", "2026.12.03"), "versione saltata")
	t.assert_true(UpdateCheck.should_offer({"versione": "2026.12.10"}, "2026.11.27", "2026.12.03"), "una piu' nuova si ripropone")
	t.assert_false(UpdateCheck.should_offer(info, "2026.12.03", ""), "gia' aggiornato")
	t.assert_false(UpdateCheck.should_offer({}, "2026.11.27", ""))
