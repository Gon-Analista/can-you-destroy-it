extends SceneTree
## Rangos del mago y Espejo del Archimago:
## - reglas (WizardRanks): cada rango por su desbloqueo clave y su Pilón, o por el Pilón solo; la
##   Leyenda al final; nunca se salta un rango ni se baja;
## - en la partida: la subida se emite una sola vez, lanza la ceremonia, la música suma su capa y
##   las manos cambian; las cifras del Espejo se cuentan, se guardan y se cargan (con el rango y
##   sin repetir la ceremonia); el espejo del Santuario abre sus estadísticas (con los bichos
##   reventados) y la guía de objetivos no lleva a él ni lo cuenta como ver el Grimorio.
## No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/ranks_smoke.gd

const HUD: NodePath = ^"HUDLayer/Hud"
const PLAYER_PATH: NodePath = ^"WorldView/WorldViewport/Player"

var _ok: bool = true
var _rank_events: Array[Vector2i] = []


func _initialize() -> void:
	_rules()
	await _in_game()
	print("ranks_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _rules() -> void:
	var total: int = 1_000_000
	var p := Progression.new(total)
	_check(WizardRanks.RANKS.size() == 6, "seis rangos (Aprendiz ... Leyenda)")
	_check(WizardRanks.earned(p) == 0, "se empieza en Aprendiz")
	p.upgrade_levels[&"awaken_frost"] = 1
	_check(WizardRanks.earned(p) == 1, "Escarcha despierta -> Iniciado")
	p.upgrade_levels[&"awaken_bolt"] = 1
	_check(WizardRanks.earned(p) == 2, "Rayo despierto -> Hechicero")
	p.upgrade_levels[&"awaken_earth"] = 1
	_check(WizardRanks.earned(p) == 2, "la Tierra sola no basta para Magus (pide Pilón)")
	var magus: RankDef = WizardRanks.RANKS[3]
	p.pylon_progress = ceili(magus.key_pylon * total)
	_check(WizardRanks.earned(p) == 3, "Tierra + Pilón -> Magus")
	p.upgrade_levels[&"awaken_arcane"] = 1
	var archmage: RankDef = WizardRanks.RANKS[4]
	p.pylon_progress = ceili(archmage.key_pylon * total)
	_check(WizardRanks.earned(p) == 4, "Arcano + Pilón -> Archimago")
	_check(WizardRanks.earned(p, 5) == 5, "nunca baja del rango que ya se tiene")
	p.pylon_progress = total
	_check(WizardRanks.earned(p) == 4, "Pilón lleno sin cristal abierto: aún no es Leyenda")
	p.essence = roundi(total * 0.02)
	_check(WizardRanks.earned(p) == 5, "Pilón lleno y cristal hasta el Núcleo -> Leyenda")
	# Sin desbloqueos: el Pilón solo también da los rangos (red de seguridad).
	var q := Progression.new(total)
	q.pylon_progress = ceili(WizardRanks.RANKS[2].pylon_alone * total)
	_check(
		WizardRanks.earned(q) == 2,
		"Pilón al %s sin despertar nada -> Hechicero" % [WizardRanks.RANKS[2].pylon_alone]
	)
	var last: float = -1.0
	for k: int in 11:
		q.pylon_progress = roundi(WizardRanks.RANKS[3].pylon_alone * total * k / 10.0)
		var pr: float = WizardRanks.progress_to(2, q)
		_check(pr >= last and pr >= 0.0 and pr <= 1.0, "barra hacia Magus (%.2f)" % pr)
		last = pr
	# Terminar la partida da la Leyenda.
	var f := Progression.new(total)
	f.essence = 0
	_check(WizardRanks.earned(f) == 5, "cristal sin esencia -> Leyenda")
	# Guardar y cargar: rango y cifras; una partida vieja (sin rango) recibe el suyo sin ceremonia.
	p.rank = 4
	p.stats.count(&"spells_cast", 7)
	p.stats.record_best(&"best_streak", 31)
	p.stats.record_best(&"best_streak", 12)
	p.stats.play_time = 125.5
	var data: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var r := Progression.new(total)
	r.load_dict(data)
	_check(r.rank == 4, "al cargar, el rango guardado (%d)" % r.rank)
	_check(r.stats.tally(&"spells_cast") == 7, "hechizos guardados")
	_check(r.stats.tally(&"best_streak") == 31, "mejor racha guardada (la más alta)")
	_check(absf(r.stats.play_time - 125.5) < 0.01, "tiempo jugado guardado")
	data.erase("rank")
	data["essence"] = total
	data["pylon_progress"] = 0
	var old := Progression.new(total)
	old.load_dict(data)
	_check(old.rank == 2, "partida vieja sin rango: el que le toca (%d)" % old.rank)


func _in_game() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	var events: Node = root.get_node(^"Events")
	var audio: Node = root.get_node(^"AudioDirector")
	gs.call(&"reset")
	events.connect(
		&"rank_changed", func(r: int, p: int) -> void: _rank_events.append(Vector2i(r, p))
	)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var game_menu: Node = current_scene.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(game_menu.call(&"is_open")):
		game_menu.call(&"_close")
	await process_frame
	var prog: Progression = gs.get(&"progression")
	_check(prog.rank == 0, "partida nueva en Aprendiz")
	_check(int(audio.call(&"get_music_layers")) == 1, "una capa de música con Aprendiz")
	# Se despierta la Escarcha de verdad (comprada en el Grimorio).
	var frost: UpgradeNode = load("res://data/upgrades/awaken_frost.tres")
	prog.mana = frost.cost_for_level(0) + 100
	_check(bool(gs.call(&"buy_upgrade", frost)), "se compra la Escarcha")
	await process_frame
	_check(prog.rank == 1, "sube a Iniciado (%d)" % prog.rank)
	_check(
		_rank_events.size() == 1 and _rank_events[0] == Vector2i(1, 0), "la subida se emite una vez"
	)
	var ceremony: Node = current_scene.get_node(HUD).get(&"rank_ceremony")
	_check(bool(ceremony.call(&"is_playing")), "ceremonia en marcha")
	_check(int(audio.call(&"get_music_layers")) == 2, "la música suma su capa (2)")
	var style: Node = current_scene.get_node(PLAYER_PATH).find_child("RankStyle", true, false)
	var mat: ShaderMaterial = style.get(&"_mat")
	_check(
		(mat.get_shader_parameter("gem_color") as Color).is_equal_approx(
			WizardRanks.RANKS[1].hand_gem
		),
		"la gema de las manos cambia"
	)
	var badge: Node = current_scene.get_node(HUD).find_child("RankBadge", true, false)
	_check(int(badge.get(&"_rank")) == 0, "el escudo del HUD espera a que se cierre la franja")
	for i: int in 900:
		await process_frame
		if not bool(ceremony.call(&"is_playing")):
			break
	_check(not bool(ceremony.call(&"is_playing")), "la ceremonia termina")
	_check(int(badge.get(&"_rank")) == 1, "el HUD enseña el rango")
	# Más comprobaciones y entregas sin pasar el siguiente: no se repite.
	for i: int in 5:
		gs.call(&"check_rank")
		gs.call(&"deliver", 10)
	_check(_rank_events.size() == 1, "no se repite la ceremonia")
	# El Pilón al punto del Hechicero.
	var need: int = (
		ceili(WizardRanks.RANKS[2].pylon_alone * prog.total_essence) - prog.pylon_progress
	)
	gs.call(&"deliver", need)
	await process_frame
	_check(prog.rank == 2 and _rank_events.size() == 2, "Pilón -> Hechicero, una vez")
	_check(int(audio.call(&"get_music_layers")) == 3, "tres capas con Hechicero")
	# Cifras del Espejo.
	var spells0: int = prog.stats.tally(&"spells_cast")
	events.emit_signal(&"spell_cast", null, 0)
	_check(prog.stats.tally(&"spells_cast") == spells0 + 1, "cuenta hechizos")
	events.emit_signal(&"streak_changed", 14)
	events.emit_signal(&"streak_changed", 3)
	_check(prog.stats.tally(&"best_streak") == 14, "mejor racha")
	events.emit_signal(&"geode_broken", Vector3.ZERO)
	_check(prog.stats.tally(&"geodes_broken") == 1, "geodas rotas")
	var shards0: int = prog.stats.tally(&"shards_collected")
	var splinter: ShardType = load("res://data/shards/splinter.tres")
	gs.call(&"collect_shard", splinter, Vector3.ZERO)
	_check(prog.stats.tally(&"shards_collected") == shards0 + 1, "fragmentos recogidos")
	_check(prog.stats.tally(&"mana_earned") >= need + 50, "maná ganado")
	var t0: float = prog.stats.play_time
	for i: int in 10:
		await process_frame
	_check(prog.stats.play_time > t0, "corre el tiempo jugado")
	# Cargar la partida: el rango vuelve sin ceremonia.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(prog.to_dict()))
	gs.call(&"reset")
	var fresh: Progression = gs.get(&"progression")
	fresh.load_dict(saved)
	gs.call(&"emit_all")
	gs.call(&"check_rank")
	await process_frame
	_check(fresh.rank == 2, "al cargar vuelve el Hechicero")
	_check(_rank_events.size() == 2, "cargar no repite la ceremonia")
	_check(fresh.stats.tally(&"best_streak") == 14, "al cargar vuelven las cifras")
	# El espejo del Santuario: al lado, F abre las estadísticas.
	var mirror: Node3D = get_first_node_in_group(&"archmage_mirror")
	_check(mirror != null, "hay Espejo del Archimago")
	var player: Node3D = current_scene.get_node(PLAYER_PATH)
	var sanctum: Node3D = get_first_node_in_group(&"sanctum")
	var lectern_gap: float = (
		Vector2(
			mirror.global_position.x - sanctum.global_position.x,
			mirror.global_position.z - sanctum.global_position.z
		)
		. length()
	)
	_check(lectern_gap > 6.5, "lejos del atril: las dos F no se pisan (%.1f m)" % lectern_gap)
	player.global_position = mirror.global_position + mirror.global_basis.z * 2.0 + Vector3.UP * 0.2
	await physics_frame
	await process_frame
	_check(bool(mirror.call(&"player_in_range")), "el jugador está junto al espejo")
	_check(String(mirror.call(&"prompt")) != "", "aviso [F] junto al espejo")
	# La guía no lleva al espejo: con una mejora sin ver, junto al espejo, apunta al Santuario.
	fresh.critters_popped = 9
	fresh.mana = 1_000_000
	fresh.seen_upgrades.clear()
	var hud: Node = current_scene.get_node(HUD)
	hud.call(&"set_intro", false)
	(hud.get(&"tutorial") as Node).call(&"skip")
	gs.call(&"emit_all")
	var guide: Node = current_scene.get_node(HUD).find_child("Guide", true, false)
	for i: int in 30:
		await process_frame
	var aim: Vector3 = guide.get(&"target")
	_check(
		int(guide.get(&"kind")) == Guidance.Kind.SANCTUM,
		"con mejoras sin ver, la guía lleva al Santuario (%d)" % int(guide.get(&"kind"))
	)
	_check(
		not aim.is_finite() or aim.distance_to(mirror.global_position) > 4.0,
		"la guía no apunta al espejo"
	)
	var screen: Node = current_scene.get_node(HUD).get(&"mirror_screen")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	root.push_input(ev)
	await process_frame
	if not bool(screen.get(&"is_open")):
		# Sin ventana (headless) el ratón no se captura: se abre como lo haría F.
		events.emit_signal(&"mirror_requested")
	await process_frame
	_check(bool(screen.get(&"is_open")), "F abre las estadísticas del espejo")
	for i: int in 50:
		await process_frame
	var vals: Array = screen.get(&"_vals")
	_check(String((vals[6] as Label).text) == "x14", "el espejo enseña la mejor racha")
	_check(String((vals[1] as Label).text).ends_with("/ 17"), "combinaciones x / total")
	_check(String((vals[10] as Label).text) == "9", "el espejo enseña los bichos reventados")
	_check(String((vals[0] as Label).text).contains("min"), "tiempo jugado en el espejo")
	# Con el espejo abierto, B no abre el Libro de Hechizos encima y Esc lo cierra (no la pausa).
	var book: Node = current_scene.get_node(HUD).get_node(^"SpellBook")
	_push_action(&"open_spellbook")
	await process_frame
	_check(not bool(book.get(&"is_open")), "el Libro de Hechizos no se abre encima del espejo")
	_push_action(&"ui_cancel")
	await process_frame
	_check(not bool(game_menu.call(&"is_open")), "Esc cierra el espejo y no abre la pausa")
	_check(bool(screen.get(&"_closing")), "Esc cierra el espejo")
	screen.call(&"close")
	for i: int in 600:
		await process_frame
		if not bool(screen.get(&"is_open")):
			break
	_check(not bool(screen.get(&"is_open")), "se cierra")
	_check(fresh.seen_upgrades.is_empty(), "mirar el espejo no da las mejoras por vistas")


## Pulsa y suelta la acción `action` por el camino real de la entrada.
func _push_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		root.push_input(ev)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
