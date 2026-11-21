extends SceneTree
## Capturas para comparar paletas: carga la escena principal en modo demo y, para cada paleta,
## hora y vista, guarda una imagen del juego. Necesita ventana (xvfb-run):
## xvfb-run godot --path game --script res://tests/tools/palette_shots.gd -- --autoplay --no-cast
##   --out=/tmp/paleta --palettes=actual,noche --times=0.45,0.0 --views=claro,valle,cristal

const VIEWS: Dictionary = {
	"claro": {"pos": Vector3(-6.0, 0.2, 76.0), "yaw": -20.0, "pitch": 1.0},
	"valle": {"pos": Vector3(-30.0, 0.2, 40.0), "yaw": 60.0, "pitch": -5.0},
	"castillo": {"pos": Vector3(60.0, 0.2, -40.0), "yaw": -8.0, "pitch": 4.0},
	"bosque": {"pos": Vector3(40.0, 0.2, 70.0), "yaw": -110.0, "pitch": -3.0},
	"cristal": {"pos": Vector3(14.0, 0.2, 112.0), "yaw": 8.0, "pitch": 9.0},
}


func _initialize() -> void:
	_run()


func _arg(name: String, def: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return def


func _run() -> void:
	var out: String = _arg("out", "/tmp/paleta")
	DirAccess.make_dir_recursive_absolute(out)
	var palettes: PackedStringArray = _arg("palettes", "actual").split(",")
	var times: PackedStringArray = _arg("times", "0.45").split(",")
	var views: PackedStringArray = _arg("views", "claro").split(",")
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 160:
		await process_frame
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var head: Node3D = player.get_node(^"Head")
	var dn: Node = get_first_node_in_group(&"day_night")
	dn.set(&"day_length_sec", 1.0e9)
	for pal: String in palettes:
		dn.call(&"set_palette", StringName(pal))
		for t: String in times:
			dn.set(&"time_of_day", float(t))
			for vn: String in views:
				var v: Dictionary = VIEWS[vn]
				var p: Vector3 = v["pos"]
				p.y = Valley.ground_height(p.x, p.z) + 0.2
				player.global_position = p
				player.rotation.y = deg_to_rad(VariantCast.to_float(v["yaw"]))
				head.rotation.x = deg_to_rad(VariantCast.to_float(v["pitch"]))
				for i: int in 8:
					await process_frame
				var img: Image = root.get_texture().get_image()
				var path: String = "%s/%s_%s_%s.png" % [out, pal, vn, t]
				img.save_png(path)
				print("shot ", path)
	quit(0)
