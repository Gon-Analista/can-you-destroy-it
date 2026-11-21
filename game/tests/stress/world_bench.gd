extends SceneTree
## Banco de rendimiento del mundo: carga la escena principal en modo demo, pone la cámara en
## varios puntos de vista y mide el tiempo de frame (CPU+GPU), las llamadas de dibujo, los
## objetos y los triángulos de cada uno. Necesita ventana (con headless no se dibuja nada):
## xvfb-run godot --path game --script res://tests/stress/world_bench.gd -- --autoplay --no-cast
## Imprime una línea por vista y el total, para comparar antes y después de un cambio.

const VIEWS: Array[Dictionary] = [
	{"name": "claro", "pos": Vector3(0.0, 0.2, 73.0), "yaw": 0.0, "pitch": 0.0},
	{"name": "bosque", "pos": Vector3(40.0, 0.2, 70.0), "yaw": -110.0, "pitch": -3.0},
	{"name": "castillo", "pos": Vector3(60.0, 0.2, -40.0), "yaw": -8.0, "pitch": 4.0},
	{"name": "valle", "pos": Vector3(-30.0, 0.2, 40.0), "yaw": 60.0, "pitch": -5.0},
	{"name": "atras", "pos": Vector3(0.0, 0.2, 90.0), "yaw": 180.0, "pitch": 0.0},
]
const WARM_FRAMES: int = 20
const MEASURE_FRAMES: int = 60


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 200:
		await process_frame
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var head: Node3D = player.get_node(^"Head")
	var world: SubViewport = main.get_node(^"WorldView/WorldViewport")
	var total_ms: float = 0.0
	for v: Dictionary in VIEWS:
		player.global_position = v["pos"]
		var p: Vector3 = player.global_position
		p.y = Valley.ground_height(p.x, p.z) + 0.2
		player.global_position = p
		player.rotation.y = deg_to_rad(v["yaw"] as float)
		head.rotation.x = deg_to_rad(v["pitch"] as float)
		for i: int in WARM_FRAMES:
			await process_frame
		var t0: int = Time.get_ticks_usec()
		for i: int in MEASURE_FRAMES:
			await process_frame
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / MEASURE_FRAMES
		total_ms += ms
		var vp: RID = world.get_viewport_rid()
		var calls: int = RenderingServer.viewport_get_render_info(
			vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
		)
		var objs: int = RenderingServer.viewport_get_render_info(
			vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
		)
		var prims: int = RenderingServer.viewport_get_render_info(
			vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
		)
		var sh_calls: int = RenderingServer.viewport_get_render_info(
			vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
		)
		var sh_prims: int = RenderingServer.viewport_get_render_info(
			vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
		)
		var script_ms: float = (
			(
				Performance.get_monitor(Performance.TIME_PROCESS)
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			)
			* 1000.0
		)
		print(
			(
				(
					"bench %-9s %6.2f ms (%5.1f fps)  draws %4d  objs %4d  tris %7d"
					% [v["name"], ms, 1000.0 / ms, calls, objs, prims]
				)
				+ "  sombra: draws %4d tris %7d  scripts %.2f ms" % [sh_calls, sh_prims, script_ms]
			)
		)
	var avg: float = total_ms / VIEWS.size()
	print("bench MEDIA %6.2f ms (%5.1f fps)" % [avg, 1000.0 / avg])
	quit(0)
