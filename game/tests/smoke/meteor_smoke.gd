extends SceneTree
## El Meteoro cae del cielo a plomo: su origen está justo encima del blanco, alto (no de lado ni
## "desde abajo"), y si encima del blanco hay algo, aterriza en lo primero que toca. La roca se
## monta, cae, estalla y vuelve al pool. Y el fuego HD no se sale de su quad (la máscara del
## borde está en el shader).
## godot --headless --path game --script res://tests/smoke/meteor_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	var sky_path: GDScript = load("res://spells/sky_path.gd")
	var target := Vector3(0, 8, 30)
	var o: Vector3 = sky_path.call(&"origin", target, 70.0)
	_check(is_equal_approx(o.y - target.y, 70.0), "nace 70 m por encima del blanco")
	_check(
		is_zero_approx(Vector2(o.x - target.x, o.z - target.z).length()),
		"a plomo: justo encima, no de lado"
	)
	var land: Dictionary = sky_path.call(&"landing", null, target, Vector3.BACK, 70.0)
	_check(land["position"] == target, "sin mundo, aterriza en el blanco")
	var meteor_def: Resource = load("res://data/spells/vfx_meteor.tres")
	_check(VariantCast.to_bool(meteor_def.get(&"meteor")), "vfx_meteor lleva el aspecto de meteoro")
	_check(
		not VariantCast.to_bool(load("res://data/spells/vfx_fireball.tres").get(&"meteor")),
		"y la Bola no"
	)
	var shader: Shader = load("res://fx/hd/hd_fire.gdshader")
	_check(shader.code.contains("border_mask"), "el fuego se funde antes del borde del quad")
	var cam3d := Camera3D.new()
	root.add_child(cam3d)
	var rock_script: GDScript = load("res://spells/vfx/meteor_rock.gd")
	var rock: Node3D = rock_script.new()
	root.add_child(rock)
	await process_frame
	rock.call(&"launch", Vector3(0, 70, 20), Vector3(0, 0, 0), 1.0, true)
	_check(rock.visible and (rock.get_node(^"Rock") as Node3D).visible, "la roca aparece")
	var mesh: Mesh = (rock.get_node(^"Rock") as MeshInstance3D).mesh
	_check(mesh != null and mesh.get_faces().size() >= 320 * 3, "roca de 320 caras")
	await create_timer(0.2).timeout
	rock.call(&"impact", Vector3.ZERO, Vector3.UP, true)
	_check(not (rock.get_node(^"Rock") as Node3D).visible, "al llegar la roca desaparece")
	_check((rock.get_node(^"Impact") as Node3D).visible, "y estalla")
	await create_timer(3.4).timeout
	_check(not (rock.get_node(^"Impact") as Node3D).visible, "el impacto se apaga solo")
	rock.call(&"stop")
	_check(not rock.visible, "vuelve al pool")
	print("meteor_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
