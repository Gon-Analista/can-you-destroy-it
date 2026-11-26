extends SceneTree
## Tutorial del principio: se sale de la casucha y se llega al cristal; la chispita de cada mano no
## hace nada ("clink"), juntar las manos hace 1 de daño y suelta un pedacito, se recoge, se tritura,
## con 5 de maná se compra la primera mejora y entonces la magia hace daño de verdad (2 con las
## manos juntas). Además: ningún paso repite cómo se pulsa F (lo enseña el aviso de la mira, que se
## retira cuando ya se sabe) y la guía de objetivos apunta adonde toca en cada paso.
## godot --headless --path game --script res://tests/smoke/tutorial_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	_check_rules()
	var gs: Node = root.get_node(^"GameState")
	var ev: Node = root.get_node(^"Events")
	gs.call(&"reset")
	var prog: RefCounted = gs.get(&"progression")
	prog.set(&"tutorial_step", 0)
	prog.set(&"hut_door_open", false)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var hud: Node = main.get_node(^"HUDLayer/Hud")
	var tut: Node = main.get_node(^"HUDLayer/Hud/Tutorial")
	var guide: Node = main.get_node(^"HUDLayer/Hud/Loop/Guide")
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var caster: Node = player.call(&"get_caster")
	_check(VariantCast.to_int(tut.get(&"step")) == 0, "empieza esperando la puerta")
	_check(
		VariantCast.to_int(guide.get(&"wanted")) == Guidance.Kind.NONE,
		"dentro de la casucha no hay guía"
	)
	var hut: Node = root.find_child("ApprenticeHut", true, false)
	hut.call(&"open_door")
	await create_timer(2.2).timeout
	_check(
		VariantCast.to_int(tut.get(&"step")) == 1,
		"al abrir la puerta: acércate (%d)" % VariantCast.to_int(tut.get(&"step"))
	)
	_check(
		VariantCast.to_int(guide.get(&"wanted")) == Guidance.Kind.CRYSTAL,
		"la guía señala el cristal"
	)
	player.global_position = Vector3(0.0, 0.3, 62.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(6.0)
	await physics_frame
	await create_timer(0.3).timeout
	_check(
		VariantCast.to_int(tut.get(&"step")) == 2,
		"junto al cristal: primer clic (%d)" % VariantCast.to_int(tut.get(&"step"))
	)
	var e0: int = VariantCast.to_int(prog.get(&"essence"))
	# Vale empezar por cualquier mano: el segundo paso pide la otra.
	caster.call(&"_cast_single", 1)
	await create_timer(2.5).timeout
	_check(VariantCast.to_int(tut.get(&"step")) == 3, "primer clic hecho (con la derecha)")
	_check(VariantCast.to_int(prog.get(&"essence")) == e0, "la chispita no hace daño")
	_check(
		_text(tut, &"_title") == tut.tr("CLIC IZQUIERDO: TU OTRA MANO"),
		"pide la otra mano (la izquierda)"
	)
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	caster.call(&"_cast_single", 1)
	await create_timer(0.6).timeout
	_check(VariantCast.to_int(tut.get(&"step")) == 3, "la misma mano otra vez no cuenta")
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	caster.call(&"_cast_single", 0)
	await create_timer(2.5).timeout
	_check(VariantCast.to_int(tut.get(&"step")) == 4, "la otra mano hecha")
	_check(VariantCast.to_int(prog.get(&"essence")) == e0, "la otra tampoco")
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	caster.call(&"try_begin_combine")
	await create_timer(0.8).timeout
	caster.call(&"try_release_combine")
	await create_timer(3.0).timeout
	_check(
		VariantCast.to_int(tut.get(&"step")) == 5,
		"juntar las manos (%d)" % VariantCast.to_int(tut.get(&"step"))
	)
	_check(
		VariantCast.to_int(prog.get(&"essence")) == e0 - 1,
		"juntas hacen 1 de daño (%d)" % (e0 - VariantCast.to_int(prog.get(&"essence")))
	)
	_check_no_f(tut, "recoger")
	await create_timer(0.5).timeout
	_check(
		VariantCast.to_int(guide.get(&"wanted")) == Guidance.Kind.SHARD, "la guía lleva al pedacito"
	)
	# El aviso de la mira: entero la primera vez, luego la tecla sola y al final nada.
	var pool: Node = root.find_child("Shards", true, false)
	var idx: int = VariantCast.to_int(pool.call(&"nearest", player.global_position, 80.0))
	_check(idx >= 0, "cayó un pedacito")
	var stype: Resource = pool.call(&"type_of", maxi(idx, 0))
	var label: Label = hud.get(&"_pickup_prompt")
	var key: Control = hud.get(&"_pickup_key")
	ev.emit_signal(&"shard_targeted", stype)
	_check(label.visible and label.text.contains("[F]"), "primera vez: [F] RECOGER entero")
	var learned: Dictionary = prog.get(&"learned")
	learned[&"pickup"] = 5
	ev.emit_signal(&"shard_targeted", stype)
	_check(
		not label.visible and VariantCast.to_bool(key.get(&"shown")),
		"ya sabido: sólo la tecla pequeña"
	)
	learned[&"pickup"] = 40
	ev.emit_signal(&"shard_targeted", stype)
	_check(
		not label.visible and not VariantCast.to_bool(key.get(&"shown")), "costumbre: ningún aviso"
	)
	learned[&"pickup"] = 0
	ev.emit_signal(&"shard_targeted", null)
	# Recoger el pedacito.
	if idx >= 0:
		player.call(&"_collect", idx)
	await process_frame
	_check(VariantCast.to_int(tut.get(&"step")) == 6, "recogido: a la trituradora")
	_check_no_f(tut, "trituradora")
	await create_timer(0.5).timeout
	_check(
		VariantCast.to_int(guide.get(&"wanted")) == Guidance.Kind.CRUSHER,
		"la guía lleva a la trituradora"
	)
	# Triturar (equivale a entregar).
	while VariantCast.to_int(prog.call(&"bag_count")) > 0:
		gs.call(&"take_for_delivery")
	gs.call(&"deliver", 1)
	await process_frame
	_check(VariantCast.to_int(tut.get(&"step")) == 7, "triturado: juntar maná")
	gs.call(&"deliver", 2)
	await process_frame
	_check(VariantCast.to_int(tut.get(&"step")) == 8, "con 3 de maná: al Santuario")
	_check_no_f(tut, "santuario")
	await create_timer(0.5).timeout
	_check(
		VariantCast.to_int(guide.get(&"wanted")) == Guidance.Kind.SANCTUM,
		"la guía lleva al Santuario"
	)
	var power: Resource = load("res://data/upgrades/spark_power.tres")
	_check(VariantCast.to_int(power.call(&"cost_for_level", 0)) == 3, "la primera mejora cuesta 3")
	_check(VariantCast.to_bool(gs.call(&"buy_upgrade", power)), "se compra")
	await process_frame
	_check(VariantCast.to_int(tut.get(&"step")) == 9, "tutorial terminado")
	var tier: Resource = caster.call(&"tier_for", 0)
	_check(VariantCast.to_int(tier.get(&"damage")) == 2, "ahora la chispa hace 2")
	var recipe: Resource = caster.call(&"recipe_for_hands")
	_check(
		VariantCast.to_int(recipe.call(&"damage_for", 2, 2, 1.0)) > 4,
		"y juntas, mucho más que por separado"
	)
	# Mejora nueva: guía al Santuario hasta que se ve en el Grimorio; luego deja de insistir.
	gs.call(&"deliver", 400)
	await create_timer(0.3).timeout
	_check(VariantCast.to_bool(guide.call(&"has_new_upgrade")), "hay una mejora nueva que pagar")
	_check(
		VariantCast.to_int(guide.get(&"wanted")) == Guidance.Kind.SANCTUM,
		"y la guía lleva al Santuario"
	)
	# Se abre el Grimorio de verdad (el Libro de Hechizos y el Espejo emiten la misma señal y no
	# cuentan como verlo).
	var grimoire: Node = hud.get_node(^"Grimoire")
	ev.emit_signal(&"grimoire_requested", true)
	await process_frame
	grimoire.call(&"close")
	await create_timer(0.6).timeout
	_check(
		not VariantCast.to_bool(guide.call(&"has_new_upgrade")),
		"vista en el Grimorio: ya no es nueva"
	)
	_check(
		VariantCast.to_int(guide.get(&"wanted")) != Guidance.Kind.SANCTUM,
		"y la guía deja de insistir"
	)
	# Lo visto se guarda: tras guardar y cargar no vuelve a insistir.
	var saved: Dictionary = prog.call(&"to_dict")
	prog.call(&"load_dict", saved)
	ev.emit_signal(&"mana_changed", VariantCast.to_int(prog.get(&"mana")))
	_check(
		not VariantCast.to_bool(guide.call(&"has_new_upgrade")), "lo visto en el Grimorio se guarda"
	)
	print("tutorial_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Reglas puras de la guía (`Guidance`, sin autoloads).
func _check_rules() -> void:
	var s := Guidance.Situation.new()
	s.capacity = 5
	s.phase = Guidance.Phase.DOOR
	_check(Guidance.pick(s) == Guidance.Kind.NONE, "regla: en la casucha, nada")
	s.phase = Guidance.Phase.CAST
	_check(Guidance.pick(s) == Guidance.Kind.CRYSTAL, "regla: lanzar -> cristal")
	s.phase = Guidance.Phase.PICKUP
	s.shard_near = true
	_check(Guidance.pick(s) == Guidance.Kind.SHARD, "regla: recoger -> fragmento")
	s.phase = Guidance.Phase.CRUSH
	s.bag = 1
	_check(Guidance.pick(s) == Guidance.Kind.CRUSHER, "regla: triturar -> trituradora")
	s.phase = Guidance.Phase.BUY
	_check(Guidance.pick(s) == Guidance.Kind.SANCTUM, "regla: comprar -> Santuario")
	_check(Guidance.is_urgent(Guidance.Kind.SANCTUM, s), "regla: en el tutorial todo es urgente")
	s.phase = Guidance.Phase.DONE
	s.bag = 5
	_check(Guidance.pick(s) == Guidance.Kind.CRUSHER, "regla: bolsa llena -> trituradora")
	_check(Guidance.is_urgent(Guidance.Kind.CRUSHER, s), "regla: bolsa llena es urgente")
	s.new_upgrade = true
	_check(Guidance.pick(s) == Guidance.Kind.CRUSHER, "regla: la bolsa llena va antes")
	s.bag = 2
	_check(Guidance.pick(s) == Guidance.Kind.SANCTUM, "regla: mejora nueva -> Santuario")
	s.new_upgrade = false
	s.pickup_learned = true
	_check(Guidance.pick(s) == Guidance.Kind.NONE, "regla: con fragmentos cerca, sigue a lo suyo")
	s.pickup_learned = false
	_check(Guidance.pick(s) == Guidance.Kind.SHARD, "regla: si aún no sabe, a los fragmentos")
	s.shard_near = false
	_check(Guidance.pick(s) == Guidance.Kind.CRUSHER, "regla: sin nada cerca, a triturar")
	_check(not Guidance.is_urgent(Guidance.Kind.CRUSHER, s), "regla: y sin prisa (discreto)")
	s.bag = 0
	s.hopper = 3
	_check(Guidance.pick(s) == Guidance.Kind.CRUSHER, "regla: tolva sin palanca -> trituradora")
	_check(Guidance.is_urgent(Guidance.Kind.CRUSHER, s), "regla: la palanca olvidada es urgente")
	s.auto_lever = true
	_check(Guidance.pick(s) == Guidance.Kind.NONE, "regla: con recolectores, la palanca es suya")
	s.auto_lever = false
	s.direct_send = true
	s.shard_near = true
	s.pickup_learned = true
	_check(Guidance.pick(s) == Guidance.Kind.NONE, "regla: envío directo y recogiendo, nada")
	s.shard_near = false
	_check(
		Guidance.pick(s) == Guidance.Kind.CRUSHER, "regla: envío directo sin nada cerca: palanca"
	)
	s.direct_send = false
	s.pickup_learned = false
	s.crushing = true
	_check(Guidance.pick(s) == Guidance.Kind.NONE, "regla: triturando, nada")
	s.crushing = false
	s.hopper = 0
	s.bag = 9
	s.direct_send = true
	s.shard_near = true
	s.pickup_learned = true
	_check(Guidance.pick(s) == Guidance.Kind.NONE, "regla: con envío directo la bolsa no se llena")
	_check(Guidance.prompt_mode(0, 4, 20) == Guidance.Prompt.FULL, "regla: aviso entero al empezar")
	_check(Guidance.prompt_mode(4, 4, 20) == Guidance.Prompt.ICON, "regla: luego sólo la tecla")
	_check(Guidance.prompt_mode(20, 4, 20) == Guidance.Prompt.NONE, "regla: y al final nada")


## Ningún texto del panel del tutorial explica la tecla F (eso lo hace el aviso de la mira).
func _check_no_f(tut: Node, what: String) -> void:
	var t: String = _text(tut, &"_title") + _text(tut, &"_sub")
	_check(not t.contains("[F]") and not t.contains(" F "), "el paso '%s' no repite la F" % what)


func _text(n: Node, prop: StringName) -> String:
	var label: Label = n.get(prop)
	return label.text


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
