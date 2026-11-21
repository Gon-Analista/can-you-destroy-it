extends SceneTree
## Hechizos hasta nivel 11: los elementos completan sus niveles (daño que sube), las mejoras de
## Potencia llegan a 11 (la Ascensión espera al cristal casi roto) y los círculos mágicos salen
## según el nivel (uno por nivel desde el 6 al cargar; 1/2/3 de toque).
## godot --headless --path game --script res://tests/smoke/spell_levels_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	for path: String in [
		"res://data/elements/spark.tres",
		"res://data/elements/frost.tres",
		"res://data/elements/wind.tres"
	]:
		var el: Resource = load(path)
		el.call(&"ensure_levels")
		var tiers: Array = el.get(&"tiers")
		_check(tiers.size() == 11, "%s llega a nivel 11" % path.get_file())
		var ok_up: bool = true
		for i: int in range(1, tiers.size()):
			var tier: Resource = tiers[i]
			var below: Resource = tiers[i - 1]
			ok_up = (
				ok_up
				and (
					VariantCast.to_int(tier.get(&"damage"))
					> VariantCast.to_int(below.get(&"damage"))
				)
			)
		_check(ok_up, "%s: el daño sube en cada nivel" % path.get_file())
	for id: String in [
		"spark_power", "frost_power", "fireball_power", "thermal_power", "wind_power"
	]:
		var node: Resource = load("res://data/upgrades/%s.tres" % id)
		_check(
			VariantCast.to_int(node.call(&"get_max_level")) == 10, "%s: 10 compras (nivel 11)" % id
		)
		_check(
			VariantCast.to_float(node.get(&"apex_destroyed_ratio")) > 0.0,
			"%s: la Ascensión espera" % id
		)
	var circles_script: GDScript = load("res://spells/vfx/magic_circles.gd")
	var circles: Node3D = circles_script.new()
	root.add_child(circles)
	await process_frame
	circles.call(&"charging", 1.0, 5, Vector3.ZERO, Vector3(0, 0, -40), Color.ORANGE, Color.WHITE)
	_check(_visible(circles) == 5, "nivel 10 cargado: 5 círculos (%d)" % _visible(circles))
	circles.call(&"charging", 0.3, 5, Vector3.ZERO, Vector3(0, 0, -40), Color.ORANGE, Color.WHITE)
	_check(_visible(circles) == 2, "a media carga aparecen los primeros (%d)" % _visible(circles))
	circles.call(&"release")
	await create_timer(0.7).timeout
	_check(_visible(circles) == 0, "al lanzar destellan y se apagan")
	circles.call(&"muzzle", Vector3.ZERO, Vector3(0, 0, -40), 3, Color.ORANGE, Color.WHITE)
	await create_timer(0.15).timeout
	_check(_visible(circles) >= 2, "toque a nivel 10: círculos en la mano")
	print("spell_levels_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


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
