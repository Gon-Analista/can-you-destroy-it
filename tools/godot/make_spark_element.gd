extends SceneTree
## Genera res://data/elements/spark.tres (ElementDef con sus 5 niveles).
## godot --headless --path game --script ../tools/godot/make_spark_element.gd
## Después se ajusta desde el editor; este script sólo existe para el primer volcado.

func _init() -> void:
	var e := ElementDef.new()
	e.id = &"spark"
	e.display_name = "Chispa"
	e.color = Color("#ffa53a")
	e.base_damage = 1.0
	e.cooldown_sec = 1.5
	#       cd    dmg spd  size  wob  smin smax sc   part light crack shake core       glow
	var rows: Array = [
		[1.5, 1, 24.0, 0.16, 0.55, 1, 1, 0.8, 10, 1.5, 0.8, 0.06, "#fff4c2", "#ffa53a"],
		[1.0, 2, 30.0, 0.22, 0.38, 1, 2, 1.0, 18, 2.5, 1.0, 0.10, "#fff6d6", "#ff9a3a"],
		[0.6, 5, 38.0, 0.30, 0.22, 2, 3, 1.15, 28, 3.5, 1.3, 0.14, "#ffffff", "#ff7f3d"],
		[0.35, 12, 48.0, 0.40, 0.12, 2, 4, 1.3, 40, 5.0, 1.6, 0.18, "#ffffff", "#ff6a5a"],
		[0.18, 30, 60.0, 0.55, 0.06, 3, 5, 1.5, 56, 7.0, 2.0, 0.22, "#ffffff", "#ff7ad9"],
	]
	for r: Array in rows:
		var t := SpellTier.new()
		t.cooldown_sec = r[0]
		t.damage = r[1]
		t.speed = r[2]
		t.size = r[3]
		t.wobble = r[4]
		t.shards_min = r[5]
		t.shards_max = r[6]
		t.shard_scale = r[7]
		t.impact_particles = r[8]
		t.light_energy = r[9]
		t.crack_radius = r[10]
		t.shake = r[11]
		t.color_core = Color(r[12])
		t.color_glow = Color(r[13])
		e.tiers.append(t)
	var err: Error = ResourceSaver.save(e, "res://data/elements/spark.tres")
	print("spark.tres: ", error_string(err))
	quit()
