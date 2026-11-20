class_name StartposLoader
extends RefCounted
## Costruisce un CampaignData da un file startpos di MTW (per esempio EARLY_XL.TXT).
##
## I comandi non ancora interpretati non sono un errore: vengono contati in
## `CampaignData.ignored_commands`, così si vede cosa resta da coprire.
## Un riferimento a una regione o fazione non dichiarata finisce in `errors`.
##
## Dalla fase 4a si interpretano anche `AddTitle`, `AddOffice` e `SetNameData` (campi
## `titles`, `offices`, `name_data_file` di CampaignData); `SetStartLeader` e `AddHeir` restano
## conservati grezzi in `Faction.start_leader` e `Faction.heirs`, con i metodi
## `leader_counters()` e `heir_entries()` per leggerli. Il formato dedotto di tutti questi comandi
## e' descritto in testa a campaign_data.gd.


static func load_file(path: String) -> CampaignData:
	return load_text(TextIO.read_latin1(path))


static func load_text(text: String) -> CampaignData:
	var data := CampaignData.new()
	for cmd in ScriptTokenizer.parse(text):
		_apply(data, cmd)
	return data


static func _apply(data: CampaignData, cmd: ScriptTokenizer.Command) -> void:
	var a := cmd.args
	if a.is_empty():
		data.errors.append("Riga %d: %s senza argomenti" % [cmd.line, cmd.name])
		return
	match cmd.name:
		"SetStartDate":
			data.start_year = int(a[0])
		"SetPeriod":
			data.period = a[0].to_upper()
		"SetEarlyPeriodStartDate":
			data.period_starts["EARLY"] = int(a[0])
		"SetHighPeriodStartDate":
			data.period_starts["HIGH"] = int(a[0])
		"SetLatePeriodStartDate":
			data.period_starts["LATE"] = int(a[0])
		"Prodfiles":
			for i in range(0, a.size() - 1, 2):
				match a[i].to_upper():
					"UNITPROD":
						data.unit_prod_file = a[i + 1]
					"BUILDINGPROD":
						data.building_prod_file = a[i + 1]
		"DeclareFaction":
			data.add_faction(a[0])
		"DeclareLandRegion":
			data.add_region(a[0], false)
		"DeclareSeaRegion":
			data.add_region(a[0], true)
		"DeclareTradegoods":
			data.trade_goods[a[0].to_upper()] = int(cmd.arg(1, "0"))
		"SetAttributes":
			var r := _region(data, cmd)
			if r != null and a.size() >= 9:
				r.display_name = a[1]
				r.culture = a[3]
				r.climate = a[4]
				r.architecture = a[5]
				r.income = int(a[7])
				r.castle_name = a[8]
		"SetRegionOwner":
			var r := _region(data, cmd)
			var f := _faction(data, cmd, 1)
			if r != null and f != null:
				r.owner = f.id
		"SetRegionRebels":
			var r := _region(data, cmd)
			if r != null:
				r.rebels = int(cmd.arg(1, "0"))
		"SetCastle":
			var r := _region(data, cmd)
			if r != null:
				r.castle_pos = Vector2i(int(cmd.arg(1, "0")), int(cmd.arg(2, "0")))
		"SetPort":
			var r := _region(data, cmd)
			if r != null:
				r.has_port = true
				r.port_pos = Vector2i(int(cmd.arg(1, "0")), int(cmd.arg(2, "0")))
				r.port_dir = int(cmd.arg(3, "0"))
		"SetTradableGoods":
			var r := _region(data, cmd)
			if r != null:
				r.trade_goods.append_array(_upper(a.slice(1)))
		"SetResources":
			var r := _region(data, cmd)
			if r != null:
				r.resources.append_array(_upper(a.slice(1)))
		"MakeBuilding":
			var r := _region(data, cmd)
			if r != null and a.size() >= 2:
				r.buildings.append(a[1])
		"MakeUnit":
			var r := _region(data, cmd)
			if r != null and a.size() >= 3:
				var u := CampaignData.StartUnit.new(r.id, a[1], int(a[2]), cmd.line)
				u.culture = cmd.arg(3)
				data.start_units.append(u)
		"SetNeighbours":
			var r := _region(data, cmd)
			if r != null:
				for n in a.slice(1):
					var other := data.region(n)
					if other == null:
						data.errors.append("Riga %d: vicino non dichiarato %s" % [cmd.line, n])
					else:
						r.neighbours.append(other.id)
		"SetActiveFaction":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.active_type = cmd.arg(1, "FT_MAJOR").to_upper()
		"SetReligion":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.religion = cmd.arg(1).to_upper()
		"SetCulture":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.culture = cmd.arg(1).to_upper()
		"SetBehaviour":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.behaviour = cmd.arg(1).to_upper()
		"SetTreasury":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.treasury.clear()
				for v in a.slice(1):
					f.treasury.append(int(v))
		"SetFactionCol":
			var f := _faction(data, cmd, 0)
			if f != null and a.size() >= 7:
				f.color_primary = Color8(int(a[1]), int(a[2]), int(a[3]))
				f.color_secondary = Color8(int(a[4]), int(a[5]), int(a[6]))
		"SetShieldImage":
			var f := _faction(data, cmd, 0)
			if f != null and a.size() >= 3:
				f.shield_large = str(a[1])
				f.shield_small = str(a[2])
				if a.size() >= 5:
					f.shield_piece = str(a[4])
		"PlaceLeader":
			var r := _region(data, cmd)
			var f := _faction(data, cmd, 1)
			if r != null and f != null:
				f.leader_region = r.id
		"SetStartLeader":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.start_leader = a.slice(1)
		"AddHeir":
			var f := _faction(data, cmd, 0)
			if f != null:
				f.heirs.append(a.slice(1))
		"SetNameData":
			data.name_data_file = a[0]
		"SetRegionUnfloodable":
			# fase 6a: regioni immuni alle inondazioni
			var r := _region(data, cmd)
			if r != null and not data.unfloodable.has(r.id):
				data.unfloodable.append(r.id)
		"SetRegionUnquakeable":
			# fase 6a: regioni immuni ai terremoti
			var r := _region(data, cmd)
			if r != null and not data.unquakeable.has(r.id):
				data.unquakeable.append(r.id)
		"AddTitle":
			var r := _region(data, cmd)
			if r != null and a.size() >= 9:
				var t := CampaignData.TitleDef.new()
				t.region = r.id
				_read_bonus(t, a, 1, cmd.line)
				data.titles.append(t)
			elif r != null:
				data.errors.append("Riga %d: AddTitle con meno di 9 argomenti" % cmd.line)
		"AddOffice":
			var f := _faction(data, cmd, 0)
			if f != null and a.size() >= 10:
				var o := CampaignData.OfficeDef.new()
				o.faction = f.id
				o.building = a[1].strip_edges().to_lower()
				_read_bonus(o, a, 2, cmd.line)
				data.offices.append(o)
			elif f != null:
				data.errors.append("Riga %d: AddOffice con meno di 10 argomenti" % cmd.line)
		_:
			data.ignored_commands[cmd.name] = int(data.ignored_commands.get(cmd.name, 0)) + 1


## Legge nome e sette bonus (lealta', acume, terrore, guerra, pieta', indice vizio, indice virtu')
## a partire dall'argomento `first`; il numero con segno (`+1`) e' un intero.
static func _read_bonus(target: CampaignData.BonusDef, args: PackedStringArray, first: int, line_number: int) -> void:
	target.display_name = args[first]
	target.loyalty = args[first + 1].to_int()
	target.acumen = args[first + 2].to_int()
	target.dread = args[first + 3].to_int()
	target.warcraft = args[first + 4].to_int()
	target.piety = args[first + 5].to_int()
	target.vice_index = args[first + 6].to_int()
	target.virtue_index = args[first + 7].to_int()
	target.line = line_number


static func _region(data: CampaignData, cmd: ScriptTokenizer.Command) -> CampaignData.Region:
	var r := data.region(cmd.arg(0))
	if r == null:
		data.errors.append("Riga %d: %s su regione non dichiarata %s" % [cmd.line, cmd.name, cmd.arg(0)])
	return r


static func _faction(data: CampaignData, cmd: ScriptTokenizer.Command, i: int) -> CampaignData.Faction:
	var f := data.faction(cmd.arg(i))
	if f == null:
		data.errors.append("Riga %d: %s su fazione non dichiarata %s" % [cmd.line, cmd.name, cmd.arg(i)])
	return f


static func _upper(values: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for v in values:
		out.append(v.to_upper())
	return out
