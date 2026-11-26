extends SceneTree
## Captura del Grimorio sin cargar el mundo: abre el libro sobre un fondo y guarda PNG.
## xvfb-run godot --path game --script res://tests/tools/grimoire_shots.gd -- --out=/tmp/g
## [--page=N] [--hover=N] [--mana=N] [--levels=id:n,...] [--far]

var _out: String = "/tmp/grimoire"


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	var prog: RefCounted = gs.get(&"progression")
	var page: int = -1
	var hover: int = -1
	var at_sanctum: bool = true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--page="):
			page = int(a.get_slice("=", 1))
		elif a.begins_with("--hover="):
			hover = int(a.get_slice("=", 1))
		elif a.begins_with("--mana="):
			prog.set(&"mana", int(a.get_slice("=", 1)))
		elif a == "--far":
			at_sanctum = false
		elif a.begins_with("--levels="):
			var levels: Dictionary = prog.get(&"upgrade_levels")
			for pair: String in a.get_slice("=", 1).split(","):
				levels[StringName(pair.get_slice(":", 0))] = int(pair.get_slice(":", 1))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	var bg := ColorRect.new()
	bg.color = Color("#5d8fd0")
	bg.size = Vector2(640, 360)
	root.add_child(bg)
	var book: Control = load("res://ui/grimoire.gd").new()
	root.add_child(book)
	await process_frame
	book.call(&"open", at_sanctum)
	if page >= 0:
		book.call(&"open_page", page)
	for i: int in 30:
		await process_frame
	if hover >= 0:
		var ups: Array = gs.get(&"UPGRADES")
		var node: Resource = ups[hover]
		var ev := InputEventMouseMotion.new()
		ev.position = Vector2(node.get(&"star_pos") + Vector2i(80, 42)) + Vector2(3, 2)
		book.call(&"_gui_input", ev)
	for i: int in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out + ".png")
	quit()
