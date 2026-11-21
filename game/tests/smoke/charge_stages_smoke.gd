extends SceneTree
## Carga por etapas de los combinados (ChargeStages): etapas por nivel, cada etapa se anuncia
## una sola vez (también manteniendo mucho rato o con un fotograma largo), el daño sube con cada
## etapa sobre la curva de siempre (la carga completa vale lo mismo que antes), los círculos
## encajan uno por etapa, y en el juego: soltar antes de tiempo, mantener, cambiar de elemento a
## media carga y abrir el menú (pausa) a media carga.
## godot --headless --path game --script res://tests/smoke/charge_stages_smoke.gd

const FIREBALL: SpellRecipe = preload("res://data/spells/recipe_fireball.tres")

var _ok: bool = true


func _initialize() -> void:
	_run()


func _run() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var balance: BalanceConfig = load("res://data/balance/default_balance.tres")
	var table: PackedInt32Array = balance.charge_stages_by_level
	_check_levels(table)
	_check_transitions()
	_check_damage(table)
	_check_rhythm(balance)
	await _check_circles()
	await _check_game()
	print("charge_stages_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check_levels(table: PackedInt32Array) -> void:
	_check(table.size() == 10, "una entrada por nivel (1..10)")
	_check(ChargeStages.count_for_level(1, table) == 0, "nivel 1: carga continua")
	_check(ChargeStages.count_for_level(2, table) == 1, "nivel 2 (1.ª Potencia): una etapa")
	_check(ChargeStages.count_for_level(5, table) == 2, "nivel 5: dos etapas")
	_check(ChargeStages.count_for_level(10, table) == 5, "nivel 10: cinco etapas")
	var up: bool = true
	for lvl: int in range(2, 11):
		up = (
			up
			and (
				ChargeStages.count_for_level(lvl, table)
				>= ChargeStages.count_for_level(lvl - 1, table)
			)
		)
	_check(up, "las etapas nunca bajan al subir de nivel")
	_check(ChargeStages.count_for_level(99, table) == 5, "un nivel fuera de tabla usa el último")


func _check_transitions() -> void:
	var st := ChargeStages.new()
	st.reset(5)
	var fired: Array[int] = []
	# Se mantiene el triple de la carga: tras la última no vuelve a sonar nada.
	for f: int in 300:
		var k: float = clampf(float(f) / 100.0, 0.0, 1.0)
		var s: int = st.advance(k)
		if s > 0:
			fired.append(s)
	_check(fired == [1, 2, 3, 4, 5], "cada etapa se anuncia una vez y en orden (%s)" % [fired])
	_check(st.is_full(), "con la carga completa, potencia completa")
	st.reset(5)
	_check(st.advance(0.65) == 3, "un fotograma largo salta a la etapa 3 con un solo golpe")
	_check(st.advance(0.66) == 0, "y no la repite")
	st.reset(0)
	_check(st.advance(1.0) == 0 and not st.is_staged(), "sin etapas no se anuncia nada")
	_check(is_equal_approx(st.power_charge(0.37), 0.37), "sin etapas la carga es continua")
	_check(ChargeStages.stage_of_circle(0, 9, 5) == 1, "9 círculos en 5 etapas: el 1.º en la 1.ª")
	_check(ChargeStages.stage_of_circle(8, 9, 5) == 5, "y el último con la última")


## Cada etapa dura al menos `charge_stage_min_sec`; lo que se alarga la carga sale de la recarga,
## así que carga + recarga es el ciclo de siempre para cualquier carga (balance intacto).
func _check_rhythm(balance: BalanceConfig) -> void:
	var min_sec: float = balance.charge_stage_min_sec
	var cs: float = FIREBALL.charge_sec
	var cd: float = FIREBALL.cooldown_sec
	var st := ChargeStages.new()
	for n: int in [0, 1, 2, 3, 4, 5]:
		st.reset(n, cs, min_sec)
		_check(st.duration >= cs - 0.0001, "%d etapas: la carga nunca es más corta" % n)
		if n > 0:
			_check(
				st.duration / float(n) >= min_sec - 0.0001,
				"%d etapas: cada una dura al menos %.2f s" % [n, min_sec]
			)
		for k: float in [0.2, 0.6, 1.0]:
			var cycle: float = k * st.duration + st.cooldown_after(cd, k, 0.25)
			_check(
				is_equal_approx(cycle, k * cs + cd),
				"%d etapas, carga %.1f: el ciclo es el de siempre (%.3f)" % [n, k, cycle]
			)
	st.reset(5, cs, min_sec)
	_check(st.duration > cs, "nivel 10: la Bola de Fuego carga algo más despacio")
	_check(is_equal_approx(st.charge_at(st.duration * 0.5), 0.5), "la carga sube lineal")
	_check(st.cooldown_after(0.3, 1.0, 0.25) >= 0.25, "la recarga nunca baja del mínimo")


func _check_damage(table: PackedInt32Array) -> void:
	var fireball: SpellRecipe = FIREBALL
	var meteor: SpellRecipe = load("res://data/spells/recipe_meteor.tres")
	for r: SpellRecipe in [fireball, meteor]:
		for lvl: int in [2, 5, 10]:
			var n: int = ChargeStages.count_for_level(lvl, table)
			var last: int = -1
			var rising: bool = true
			var on_curve: bool = true
			for s: int in range(0, n + 1):
				var k: float = float(s) / float(n)
				var d: int = r.damage_for(400, 400, ChargeStages.quantize(k, n))
				rising = rising and d > last
				on_curve = on_curve and d == r.damage_for(400, 400, k)
				last = d
			_check(rising, "%s nivel %d: el daño sube con cada etapa" % [r.id, lvl])
			_check(on_curve, "%s nivel %d: cada etapa vale la curva de siempre" % [r.id, lvl])
			_check(
				last == r.damage_for(400, 400, 1.0),
				"%s nivel %d: la carga completa vale lo mismo que antes" % [r.id, lvl]
			)
			# Entre etapas vale la anterior (soltar antes de tiempo).
			var mid: int = r.damage_for(400, 400, ChargeStages.quantize(0.99 / float(n), n))
			_check(
				mid == r.damage_for(400, 400, 0.0), "%s: antes de la 1.ª etapa, lo mínimo" % r.id
			)


func _check_circles() -> void:
	var circles_script: GDScript = load("res://spells/vfx/magic_circles.gd")
	var circles: Node3D = circles_script.new()
	root.add_child(circles)
	await process_frame
	var from := Vector3.ZERO
	var to := Vector3(0, 0, -40)
	circles.call(&"charging", 0.19, 5, from, to, Color.ORANGE, Color.WHITE, 5)
	_check(_visible(circles) == 0, "antes de la 1.ª etapa no hay círculo (%d)" % _visible(circles))
	circles.call(&"charging", 0.2, 5, from, to, Color.ORANGE, Color.WHITE, 5)
	_check(_visible(circles) == 1, "1.ª etapa: un círculo (%d)" % _visible(circles))
	circles.call(&"charging", 0.61, 5, from, to, Color.ORANGE, Color.WHITE, 5)
	_check(_visible(circles) == 3, "3.ª etapa: tres círculos (%d)" % _visible(circles))
	circles.call(&"charging", 1.0, 5, from, to, Color.ORANGE, Color.WHITE, 5)
	await process_frame
	circles.call(&"charging", 1.0, 5, from, to, Color.ORANGE, Color.WHITE, 5)
	_check(
		_visible(circles) == 6, "potencia completa: 5 círculos y su onda (%d)" % _visible(circles)
	)
	circles.call(&"cancel")
	await create_timer(0.5).timeout
	_check(_visible(circles) == 0, "al cancelar se apagan")
	var sky := to + Vector3(0, 40, 10)
	circles.call(&"charging_sky", 0.05, 4, to, Vector3.BACK, sky, Color.RED, Color.WHITE, 2)
	_check(
		_visible(circles) == 1,
		"cielo: el círculo del blanco marca dónde caerá desde el principio (%d)" % _visible(circles)
	)
	circles.call(&"charging_sky", 0.5, 4, to, Vector3.BACK, sky, Color.RED, Color.WHITE, 2)
	_check(
		_visible(circles) == 2,
		"cielo, 4 círculos en 2 etapas: la 1.ª abre el primero del camino (%d)" % _visible(circles)
	)
	circles.call(&"charging_sky", 1.0, 4, to, Vector3.BACK, sky, Color.RED, Color.WHITE, 2)
	_check(_visible(circles) == 4, "cielo: con la última, todos (%d)" % _visible(circles))
	circles.call(&"release")
	await create_timer(0.7).timeout
	_check(_visible(circles) == 0, "al lanzar destellan y se apagan")
	circles.queue_free()


func _check_game() -> void:
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var caster: Node = main.get_node(^"WorldView/WorldViewport/Player").call(&"get_caster")
	caster.set_process_unhandled_input(false)
	var events: Node = root.get_node(^"Events")
	var stages: Array[int] = []
	events.connect(&"spell_charge_stage", func(s: int, _t: int) -> void: stages.append(s))
	for i: int in 30:
		await process_frame
	var recipe: SpellRecipe = FIREBALL
	caster.call(&"set_debug_level", 10)

	# Mantener mucho rato: cada etapa una vez, y luego nada más.
	_check(VariantCast.to_bool(caster.call(&"try_begin_combine")), "nivel 10: se juntan las manos")
	var held: ChargeStages = caster.call(&"charge_stages")
	var dur: float = held.duration
	await create_timer(dur * 3.0 + 0.5).timeout
	_check(stages == [0, 1, 2, 3, 4, 5], "mantener: 5 etapas, una vez cada una (%s)" % [stages])
	var st: ChargeStages = caster.call(&"charge_stages")
	_check(st.is_full(), "mantener: potencia completa")
	caster.call(&"try_release_combine")
	_check(VariantCast.to_bool(stages.back() == -1), "al soltar termina la carga")
	_check(not VariantCast.to_bool(caster.call(&"is_combining")), "al soltar se lanza")

	# Soltar antes de tiempo: se queda en la etapa a la que llegó.
	await create_timer(recipe.cooldown_sec + 0.2).timeout
	stages.clear()
	_check(VariantCast.to_bool(caster.call(&"try_begin_combine")), "otra vez a juntar")
	await create_timer(dur * 0.5).timeout
	var halfway: ChargeStages = caster.call(&"charge_stages")
	var early: int = halfway.reached
	_check(early >= 1 and early <= 3, "a media carga, etapas a medias (%d)" % early)
	# Cambiar de elemento a media carga no hace nada (las manos están juntas).
	var hand: Array = caster.get(&"hand_element")
	var before: int = VariantCast.to_int(hand[0])
	caster.call(&"cycle_element", 0)
	hand = caster.get(&"hand_element")
	_check(VariantCast.to_int(hand[0]) == before, "a media carga, Q no cambia el elemento")
	_check(VariantCast.to_bool(caster.call(&"is_combining")), "y la carga sigue")
	caster.call(&"try_release_combine")
	_check(stages.count(early) == 1, "soltar antes: cada etapa sonó una vez")

	# Pausa (menú) a media carga: se deshace sin gastar la recarga.
	await create_timer(recipe.cooldown_sec + 0.2).timeout
	stages.clear()
	_check(VariantCast.to_bool(caster.call(&"try_begin_combine")), "y otra vez")
	await create_timer(dur * 0.3).timeout
	events.emit_signal(&"menu_opened")
	_check(
		not VariantCast.to_bool(caster.call(&"is_combining")),
		"al abrir el menú la carga se deshace"
	)
	_check(VariantCast.to_bool(stages.back() == -1), "y termina")
	_check(
		VariantCast.to_float(caster.call(&"charge_ratio", 0)) >= 1.0,
		"cancelar no gasta la recarga de las manos"
	)
	var n_before: int = stages.size()
	await create_timer(dur).timeout
	_check(stages.size() == n_before, "cancelada, no suena ninguna etapa más")


func _visible(n: Node) -> int:
	var c: int = 0
	for q: Node in n.get_children():
		if (q as Node3D).visible:
			c += 1
	return c


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
