extends SceneTree
## Genera res://data/shards/*.tres (Astilla, Fragmento, Fragmento grande).
## godot --headless --path game --script ../tools/godot/make_shard_types.gd

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/shards")
	#  id         nombre               plural                 dmg val  r     h     tip   lados pitch speed
	var rows: Array = [
		[&"splinter", "Astilla", "astillas", 0, 1, 0.06, 0.34, 0.16, 4, 1.45, 1.15],
		[&"shard", "Fragmento", "fragmentos", 3, 5, 0.26, 0.45, 0.3, 5, 1.0, 1.0],
		[&"chunk", "Fragmento grande", "fragmentos grandes", 10, 25, 0.55, 0.8, 0.45, 6, 0.72, 0.8],
	]
	for r: Array in rows:
		var t := ShardType.new()
		t.id = r[0]
		t.display_name = r[1]
		t.display_name_plural = r[2]
		t.min_damage = r[3]
		t.value = r[4]
		t.radius = r[5]
		t.height = r[6]
		t.tip = r[7]
		t.sides = r[8]
		t.pickup_pitch = r[9]
		t.launch_speed = r[10]
		print(t.id, ": ", error_string(ResourceSaver.save(t, "res://data/shards/%s.tres" % t.id)))
	quit()
