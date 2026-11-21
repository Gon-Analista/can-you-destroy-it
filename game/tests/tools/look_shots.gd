extends SceneTree
## Capturas para comparar opciones de "descanso visual" (tono, calma de lejos, suavizado).
## Como palette_shots, pero con --looks=base,tono,calma,smaa,ssaa,tono+calma... (se combinan con +).
## Con --motion=N además guarda N fotogramas caminando de lado y girando despacio (para medir parpadeo).
## xvfb-run godot --path game --script res://tests/tools/look_shots.gd -- --autoplay --no-cast --backdrop
##   --out=/tmp/look --looks=base,tono --times=0.45 --views=claro,cristal [--motion=24]

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
	var out: String = _arg("out", "/tmp/look")
	DirAccess.make_dir_recursive_absolute(out)
	var looks: PackedStringArray = _arg("looks", "base").split(",")
	var times: PackedStringArray = _arg("times", "0.45").split(",")
	var views: PackedStringArray = _arg("views", "claro").split(",")
	var motion: int = int(_arg("motion", "0"))
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 160:
		await process_frame
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var head: Node3D = player.get_node(^"Head")
	var vp: SubViewport = main.get_node(^"WorldView/WorldViewport")
	var env: Environment = (vp.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	var dn: Node = get_first_node_in_group(&"day_night")
	dn.set(&"day_length_sec", 1.0e9)
	# Nubes quietas: así las capturas de cada opción se comparan bien.
	(env.sky.sky_material as ShaderMaterial).set_shader_parameter(&"cloud_speed", 0.0)
	var base_contrast: float = env.adjustment_contrast
	var base_sat: float = env.adjustment_saturation
	for look: String in looks:
		var f: PackedStringArray = look.split("+")
		# tono = AgX, filmico = Filmic; los dos bajan algo el contraste del ajuste.
		var soft: bool = f.has("tono") or f.has("filmico")
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		if f.has("tono"):
			env.tonemap_mode = Environment.TONE_MAPPER_AGX
		elif f.has("filmico"):
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = float(_arg("exposure", "1.0")) if soft else 1.0
		env.tonemap_white = float(_arg("white", "1.0")) if soft else 1.0
		env.adjustment_contrast = base_contrast * (0.94 if soft else 1.0)
		env.adjustment_saturation = base_sat
		var calm: float = 1.0 if f.has("calma") else (0.5 if f.has("calma50") else 0.0)
		RenderingServer.global_shader_parameter_set(&"terrain_calm", calm)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if f.has("smaa") else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_scale = 2.0 if f.has("ssaa") else 1.0
		for t: String in times:
			dn.set(&"time_of_day", float(t))
			for vn: String in views:
				var v: Dictionary = VIEWS[vn]
				var p: Vector3 = v["pos"]
				p.y = Valley.ground_height(p.x, p.z) + 0.2
				var yaw: float = VariantCast.to_float(v["yaw"])
				player.global_position = p
				player.rotation.y = deg_to_rad(yaw)
				head.rotation.x = deg_to_rad(VariantCast.to_float(v["pitch"]))
				for i: int in 10:
					await process_frame
				var tag: String = look.replace("+", "-")
				var img: Image = root.get_texture().get_image()
				var path: String = "%s/%s_%s_%s.png" % [out, tag, vn, t]
				img.save_png(path)
				print("shot ", path)
				if motion > 0:
					var dir: String = "%s/mov_%s_%s_%s" % [out, tag, vn, t]
					DirAccess.make_dir_recursive_absolute(dir)
					var right: Vector3 = player.global_transform.basis.x
					for k: int in motion:
						# 4 m/s de lado a 60 fps y 12 °/s de giro: un paseo normal.
						var q: Vector3 = p + right * (4.0 / 60.0) * k
						q.y = Valley.ground_height(q.x, q.z) + 0.2
						player.global_position = q
						player.rotation.y = deg_to_rad(yaw + 0.2 * k)
						await process_frame
						await process_frame
						root.get_texture().get_image().save_png("%s/%03d.png" % [dir, k])
	quit(0)
