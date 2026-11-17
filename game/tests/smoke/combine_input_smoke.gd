extends SceneTree
## Combinar con las dos manos (GDD 5.2): dos clics casi a la vez juntan las manos y cargan la
## Bola de Fuego, que sale al soltar; un clic suelto lanza sólo esa mano.
## godot --headless --path game --script res://tests/smoke/combine_input_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	# Sin tipos de escena (SpellCaster, Player): sus scripts usan autoloads, que no existen al
	# compilar un script de --script. Se llaman por nombre.
	var caster: Node = main.get_node(^"Player").call(&"get_caster")
	var recipe: SpellRecipe = load("res://data/spells/recipe_fireball.tres")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Sin ventana no se puede capturar el ratón: se prueba la lógica directamente.
		caster.set_process_unhandled_input(false)
	# Los autoloads no existen al compilar un script de --script: se buscan en el árbol.
	var events: Node = root.get_node(^"Events")
	var progression: Progression = root.get_node(^"GameState").get(&"progression")
	var balance: BalanceConfig = load("res://data/balance/default_balance.tres")
	var casts: Array[int] = []
	events.connect(&"spell_cast", func(_t: SpellTier, side: int) -> void: casts.append(side))
	var discovered: Array[StringName] = []
	events.connect(&"recipe_discovered", func(r: SpellRecipe) -> void: discovered.append(r.id))
	# El descubrimiento se guarda en user://: se restaura al final para no ensuciar la partida.
	var state_before: Dictionary = progression.to_dict()
	progression.discovered_recipes.clear()

	# Los primeros fotogramas (compilar shaders) duran mucho: se deja que el juego se asiente.
	for i: int in 30:
		await process_frame

	# Dos clics en fotogramas seguidos: combinación.
	caster.call(&"_on_press", 0)
	await process_frame
	caster.call(&"_on_press", 1)
	_check(caster.call(&"is_combining"), "dos clics a la vez juntan las manos")
	_check(casts.is_empty(), "al juntar no sale nada todavía")
	await _wait(0.4)
	_check(caster.call(&"combine_charge") > 0.3, "la carga sube mientras se mantiene")
	caster.call(&"_on_release", 0)
	_check(not caster.call(&"is_combining"), "al soltar se lanza")
	_check(casts == [2], "sale un único hechizo combinado")
	_check(discovered == [&"fireball"], "la primera Bola de Fuego se descubre")
	_check(
		caster.call(&"charge_ratio", 0) < 0.1 and caster.call(&"charge_ratio", 1) < 0.1,
		"las dos manos recargan"
	)

	# Esperar a que las dos manos estén listas y probar un clic suelto.
	await _wait(recipe.cooldown_sec + 0.1)
	casts.clear()
	caster.call(&"_on_press", 1)
	_check(casts.is_empty(), "con las dos manos listas el clic espera por la combinación")
	await _wait(balance.combine_window_sec + 0.05)
	_check(casts == [1], "sin segundo clic sale sólo la mano derecha")
	caster.call(&"_on_release", 1)
	_check(casts == [1], "soltar después no lanza otra vez")

	# Clic corto: sale al soltar, sin esperar a la ventana.
	await _wait(0.05)
	casts.clear()
	caster.call(&"_on_press", 0)
	caster.call(&"_on_release", 0)
	_check(casts == [0], "un clic corto sale en el acto")
	_check(not caster.call(&"is_combining"), "un clic corto no combina")

	# Con una mano recargando no hay combinación: la otra sale ya.
	await _wait(0.05)
	casts.clear()
	caster.call(&"_on_press", 1)
	_check(casts.is_empty(), "la mano derecha sigue recargando: se guarda o se ignora")
	_check(not caster.call(&"is_combining"), "sin las dos manos listas no se combina")
	_check(
		discovered == [&"fireball"],
		"la segunda Bola de Fuego no vuelve a anunciarse (sigue descubierta)"
	)

	progression.load_dict(state_before)
	root.get_node(^"SaveSystem").call(&"save_game")
	print("combine_input_smoke: %s" % ("OK" if _failures == 0 else "%d fallos" % _failures))
	quit(1 if _failures > 0 else 0)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: " + label)
