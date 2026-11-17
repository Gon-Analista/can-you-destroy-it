extends SceneTree
## El Cristal Madre destructible: el volumen horneado carga, reparte 1.000.000 de esencia entre
## sus capas, se excava (y la esencia sale del volumen arrancado), respeta las capas que no
## ceden (Núcleo), se malla por trozos y su estado se guarda y se recupera.
## godot --headless --path game --script res://tests/smoke/crystal_volume_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	var v := CrystalVolume.new()
	_check(v.load_baked(), "carga el volumen horneado")
	_check(v.layer_density.size() == 5, "cinco capas")
	# Esencia total = volumen sólido de cada capa x su densidad.
	var total: float = 0.0
	var vol: float = v.cell * v.cell * v.cell
	for z: int in v.size.z:
		for y: int in v.size.y:
			for x: int in v.size.x:
				var i: int = v.index(x, y, z)
				var f: float = clampf(0.5 - v.sdf[i] / v.cell, 0.0, 1.0)
				if f > 0.0:
					var wp: Vector3 = v.origin + Vector3(x, y, z) * v.cell
					total += f * vol * v.layer_density[v.layer_at(wp)]
	_check(absf(total - 1000000.0) < 25000.0, "la esencia total es ~1.000.000 (%.0f)" % total)
	_check(v.layer_at(v.core_center) == 4, "el centro de la base es el Núcleo")
	_check(v.layer_at(Vector3(0.0, 35.0, 0.0)) == 3, "el eje de la punta es Corazón")
	# Excavar en la superficie del lado del claro.
	var p := Vector3(0.0, 3.0, 60.0)
	while not v.is_solid(p) and p.z > 0.0:
		p.z -= 0.1
	_check(v.is_solid(p), "hay superficie delante")
	_check(v.layer_at(p) == 0, "la superficie es Corteza")
	var r: Dictionary = v.carve(p, 1.0, 0.6, 0b01111)
	_check(float(r["essence"]) > 0.5, "excavar quita esencia (%.2f)" % float(r["essence"]))
	_check(not (r["chunks"] as Array).is_empty(), "y marca trozos para rehacer")
	_check(not v.is_solid(p), "y el cristal ya no está ahí")
	var dry: Dictionary = v.carve(p, 1.0, 0.6, 0b01111, false)
	var before: float = v.sample(v.sdf, p, 0.0)
	v.carve(p, 1.0, 0.6, 0b01111, false)
	_check(is_equal_approx(before, v.sample(v.sdf, p, 0.0)), "la prueba en seco no toca nada")
	_check(float(dry["essence"]) >= 0.0, "la prueba en seco devuelve esencia")
	# El Núcleo no cede.
	var core_r: Dictionary = v.carve(v.core_center, 2.0, 5.0, 0b01111)
	_check(float(core_r["essence"]) == 0.0, "el Núcleo no se excava sin su bit")
	# Malla de un trozo con superficie.
	var arrays: Array = CrystalVolume.mesh_chunk(
		v.sdf, v.depth, v.size, v.cell, v.origin, v.chunk, v.chunk_coords(v.surface_chunks[0])
	)
	_check(not arrays.is_empty(), "un trozo con superficie tiene malla")
	var tris: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check(tris > 0 and tris % 3 == 0, "triángulos completos (%d vértices)" % tris)
	# Guardar y recuperar.
	var bytes: PackedByteArray = v.state_bytes()
	var w := CrystalVolume.new()
	w.load_baked()
	_check(w.is_solid(p), "un volumen nuevo está entero")
	_check(w.load_state(bytes), "carga el estado guardado")
	_check(not w.is_solid(p), "y recupera lo excavado")
	print("crystal_volume_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
