extends SceneTree
## Test rápido sin addons de las reglas de Progression. Sustituir por gdUnit4 cuando se integre.
## godot --headless --path game --script res://tests/smoke/progression_smoke.gd

var _failures: int = 0


func _init() -> void:
	var p := Progression.new(1000)
	_check(p.damage_crystal(5) == 5, "daño normal")
	_check(p.essence == 995, "esencia baja")
	_check(p.damage_crystal(5000) == 995, "el daño no pasa de la esencia restante")
	_check(p.is_crystal_destroyed(), "cristal destruido")

	p = Progression.new(1000)
	p.deliver(10)
	_check(p.pylon_progress == 10 and p.mana == 10, "entregar suma a Pilón y maná")
	_check(p.spend(4) and p.mana == 6 and p.pylon_progress == 10, "gastar no baja el Pilón")
	_check(not p.spend(100), "no se gasta lo que no hay")
	p.deliver(5000)
	_check(p.pylon_progress == 1000, "el Pilón no pasa del total")

	var node := UpgradeNode.new()
	node.id = &"spark_power"
	node.base_cost = 5
	node.max_level = 2
	p = Progression.new(1000)
	p.deliver(5)
	_check(p.buy_upgrade(node) and p.get_level(&"spark_power") == 1, "comprar mejora")
	_check(not p.buy_upgrade(node), "sin maná no se compra")

	var restored := Progression.new(1000)
	restored.load_dict(p.to_dict())
	_check(restored.to_dict() == p.to_dict(), "guardar y cargar conserva el estado")

	print("progression_smoke: %s" % ("OK" if _failures == 0 else "%d fallos" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: " + label)
