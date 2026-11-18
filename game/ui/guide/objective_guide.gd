class_name ObjectiveGuide
extends Control
## Guía de objetivos: dice adónde ir sin repetir instrucciones (pedido del jugador: "mejor que te
## guíe donde debes"). Sustituye a los marcadores sueltos del HUD hacia la trituradora y el
## Santuario.
## - Sobre el objetivo, un rombo de cristal que gira, con los metros debajo y, si es urgente o
##   acaba de aparecer, su nombre encima. Fuera de la pantalla, una flecha en el borde con los
##   metros.
## - En el mundo (capa de magia HD, `GuideTrail`): columna de luz sobre el objetivo y estela de
##   destellos por el suelo, sólo para lo urgente (tutorial, bolsa llena, mejora nueva, palanca).
## - Se desvanece al acercarse y desaparece al llegar (con un destello de sonido).
## Qué objetivo toca lo decide `Guidance.pick` (reglas puras, probadas en tutorial_smoke).

const DEF: GuidanceDef = preload("res://data/ui/guidance.tres")
const ARRIVE_SFX: AudioStream = preload("res://audio/sfx/sfx_guide_arrive_01.ogg")
const NEW_SFX: AudioStream = preload("res://audio/sfx/sfx_guide_new_01.ogg")
const C_SHADOW := Color("#14183a")
const C_CYAN := Color("#a5dae5")
const C_GOLD := Color("#ffd27a")
const C_PINK := Color("#ff7ad9")
const C_VIOLET := Color("#c79bff")
## Los marcadores no suben de aquí (arriba están la esencia y el Pilón) ni bajan de aquí.
const TOP: float = 58.0
const BOTTOM_GAP: float = 46.0
const SIDE: float = 16.0
const TAG_W: float = 160.0
## Flecha hacia la derecha y hacia abajo a la derecha ('#' color, '+' brillo); el resto de
## direcciones salen girándolas o reflejándolas.
const ARROW_SIDE: PackedStringArray = [
	"#.....",
	"##....",
	"#+#...",
	"#++#..",
	"#+++#.",
	"#++++#",
	"#+++#.",
	"#++#..",
	"#+#...",
	"##....",
	"#....."
]
const ARROW_DIAG: PackedStringArray = [
	"......#", ".....##", "....#+#", "...#++#", "..#+++#", ".#++++#", "#######"
]
## El rombo flota por encima del objetivo (px) con los metros debajo: así no lo tapa.
const GEM_LIFT: float = -22.0
## Alto que ocupan sobre el objetivo el rombo y su nombre (px): por encima de `_top` no caben.
const STACK_H: float = 34.0
## Altura del objetivo sobre su punto de referencia (m), para el rombo.
const CRYSTAL_AT := Vector3(0.0, 12.0, 0.0)
## Con el panel del tutorial arriba, los marcadores bajan hasta aquí para no quedar debajo.
const TOP_TUTORIAL: float = 96.0

## Objetivo que se muestra ahora (`Guidance.Kind`) y su punto en el mundo.
var kind: int = Guidance.Kind.NONE
var target := Vector3.INF
## Objetivo que toca según las reglas (`kind` lo sigue tras apagar el anterior).
var wanted: int = Guidance.Kind.NONE
## Oculta la guía (dentro de la casucha).
var suppressed: bool = false

var _sit := Guidance.Situation.new()
var _camera: Camera3D
var _trail: GuideTrail
var _urgent: bool = false
var _alpha: float = 0.0
var _pop: float = 0.0
var _tag_t: float = 0.0
var _t: float = 0.0
var _screen := Vector2.ZERO
var _edge: bool = false
var _edge_dir := Vector2.RIGHT
var _dist_m: int = -1
## El texto de la distancia lleva delante el nombre del objetivo (flecha del borde).
var _dist_named: bool = false
var _top: float = TOP
## Placa oscura detrás de la flecha del borde y su texto.
var _plate := Rect2()
var _tag_lever: bool = false
var _arrived: bool = false
var _shard: int = -1
var _shard_scan: float = 0.0
var _new_upgrade: bool = false
var _tag: Label
var _dist: Label
var _player: Node3D
var _pool: ShardPool
## Lágrimas del Núcleo y la que se señala (índice en CoreTears, -1 = ninguna).
var _tears: CoreTears
var _tear: int = -1
var _crusher: CrystalCrusher
var _sanctum: Sanctum
var _tutorial: Tutorial
var _flock: FamiliarFlock


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tag = _label(UiFonts.BOLD)
	_dist = _label(UiFonts.BOLD)
	Events.mana_changed.connect(func(_m: int) -> void: _recheck_upgrades())
	Events.upgrade_bought.connect(func(_id: StringName, _l: int) -> void: _recheck_upgrades())
	Events.grimoire_opened.connect(_mark_seen)
	Events.grimoire_closed.connect(_mark_seen)
	Events.locale_changed.connect(_refresh_tag)
	_recheck_upgrades()


func bind(camera: Camera3D) -> void:
	_camera = camera
	_trail = GuideTrail.new()
	_trail.name = "GuideTrail"
	_trail.trail_length = DEF.trail_length_m
	camera.get_viewport().add_child.call_deferred(_trail)


## Hay una mejora pagable que no se había visto (la guía lleva al Santuario).
func has_new_upgrade() -> bool:
	return _new_upgrade


func _label(font: Font) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", UiFonts.SMALL)
	UiFonts.outline(l, C_SHADOW)
	l.size = Vector2(TAG_W, UiFonts.LINE)
	l.visible = false
	add_child(l)
	return l


## Lo visto se guarda en la partida (`Progression.seen_upgrades`): al volver a cargar no se
## insiste otra vez con mejoras que el jugador ya decidió no comprar.
func _recheck_upgrades() -> void:
	var prog: Progression = GameState.progression
	var seen: Dictionary[StringName, int] = prog.seen_upgrades
	var early: bool = GameState.total_upgrade_levels() < DEF.guide_any_upgrade_until
	_new_upgrade = false
	for n: UpgradeNode in GameState.UPGRADES:
		if prog.purchase_block(n) != &"":
			continue
		var lv: int = prog.get_level(n.id)
		if not seen.has(n.id) or (early and seen[n.id] < lv):
			_new_upgrade = true
			return


## Al abrir o cerrar el Grimorio, lo que se puede pagar ya está visto.
func _mark_seen() -> void:
	var prog: Progression = GameState.progression
	for n: UpgradeNode in GameState.UPGRADES:
		if prog.purchase_block(n) == &"":
			prog.seen_upgrades[n.id] = prog.get_level(n.id)
	_recheck_upgrades()


func _find_nodes() -> bool:
	var tree: SceneTree = get_tree()
	if _player == null:
		_player = tree.get_first_node_in_group(&"player") as Node3D
	if _pool == null:
		_pool = tree.get_first_node_in_group(&"shard_pool") as ShardPool
	if _crusher == null:
		_crusher = tree.get_first_node_in_group(&"crystal_crusher") as CrystalCrusher
	if _sanctum == null:
		_sanctum = tree.get_first_node_in_group(&"sanctum") as Sanctum
	if _tutorial == null:
		_tutorial = tree.get_first_node_in_group(&"tutorial") as Tutorial
	if _flock == null:
		_flock = tree.get_first_node_in_group(&"familiar_flock") as FamiliarFlock
	if _tears == null:
		_tears = tree.get_first_node_in_group(&"core_tears") as CoreTears
	return _player != null and _camera != null


func _process(delta: float) -> void:
	_t += delta
	if not _find_nodes():
		return
	var at: Vector3 = _player.global_position
	_fill_situation(at, delta)
	_top = TOP if _sit.phase == Guidance.Phase.DONE else TOP_TUTORIAL
	wanted = Guidance.Kind.NONE if suppressed else Guidance.pick(_sit)
	# Cambio de objetivo: el viejo se apaga deprisa y el nuevo entra con un salto.
	if wanted != kind:
		_alpha = move_toward(_alpha, 0.0, delta * 7.0)
		if _alpha <= 0.0:
			_switch_to(wanted)
	_urgent = Guidance.is_urgent(kind, _sit)
	var goal: float = 0.0
	if kind != Guidance.Kind.NONE:
		target = _target_of(kind)
		goal = _goal_alpha(at)
		if wanted == kind:
			_alpha = move_toward(_alpha, goal, delta * 4.0)
	var lever: bool = _sit.bag == 0 and _sit.hopper > 0
	if lever != _tag_lever:
		_tag_lever = lever
		_refresh_tag()
	_pop = maxf(0.0, _pop - delta * 4.0)
	_tag_t = maxf(0.0, _tag_t - delta)
	_check_arrival(goal)
	_update_world(at, delta)
	_place_labels()
	queue_redraw()


func _fill_situation(at: Vector3, delta: float) -> void:
	var prog: Progression = GameState.progression
	_sit.phase = _tutorial.guide_phase() if _tutorial else Guidance.Phase.DONE
	_sit.bag = prog.bag_count()
	_sit.capacity = GameState.bag_capacity()
	_sit.direct_send = GameState.has_direct_send()
	_sit.hopper = (_crusher.hopper_count() + _crusher.queued_count()) if _crusher else 0
	_sit.crushing = _crusher != null and _crusher.is_busy()
	_sit.new_upgrade = _new_upgrade
	_sit.pickup_learned = prog.times(&"pickup") >= DEF.pickup_learn
	_sit.auto_lever = _flock != null and _flock.active_count(FamiliarDef.Role.COLLECTOR) > 0
	# Fragmento suelto más cercano: se mantiene el elegido mientras siga ahí (sin saltos) y cada
	# poco se mira si hay otro bastante más cerca.
	_shard_scan -= delta
	if _pool:
		var keep: bool = _shard >= 0 and _pool.is_loose(_shard)
		if keep and _pool.position_of(_shard).distance_to(at) > DEF.shard_radius_m:
			keep = false
		if not keep or _shard_scan <= 0.0:
			_shard_scan = 0.4
			var best: int = _pool.nearest(at, DEF.shard_radius_m)
			if (
				not keep
				or (
					best >= 0
					and (
						_pool.position_of(best).distance_to(at) + 2.0
						< _pool.position_of(_shard).distance_to(at)
					)
				)
			):
				_shard = best
	_sit.shard_near = _shard >= 0
	_tear = _tears.nearest(at, DEF.shard_radius_m * 2.0) if _tears else -1
	_sit.tear_near = _tear >= 0


func _switch_to(k: int) -> void:
	var was: int = kind
	kind = k
	_arrived = false
	_dist_m = -1
	_pop = 1.0
	_tag_t = DEF.tag_sec
	_refresh_tag()
	# Sonido sólo para lo que no tiene ya el suyo (bolsa llena y mejora nueva suenan en el HUD;
	# el tutorial suena al cumplir cada paso): olvidarse de la palanca.
	if (
		was != Guidance.Kind.NONE
		and k == Guidance.Kind.CRUSHER
		and _sit.phase == Guidance.Phase.DONE
		and not _sit.bag_full()
		and _sit.bag == 0
	):
		AudioDirector.play_sfx(NEW_SFX, -6.0, 1.12)


func _refresh_tag() -> void:
	_dist_m = -1
	match kind:
		Guidance.Kind.CRUSHER:
			_tag.text = tr("PALANCA") if _tag_lever else tr("TRITURADORA")
		Guidance.Kind.SANCTUM:
			_tag.text = tr("¡MEJORA!")
		Guidance.Kind.CRYSTAL:
			_tag.text = tr("CRISTAL MADRE")
		Guidance.Kind.TEAR:
			_tag.text = tr("¡LÁGRIMA!")
		_:
			_tag.text = ""


func _target_of(k: int) -> Vector3:
	match k:
		Guidance.Kind.SHARD:
			if _shard >= 0 and _pool:
				return _pool.position_of(_shard)
		Guidance.Kind.CRUSHER:
			if _crusher:
				return _crusher.marker_position()
		Guidance.Kind.SANCTUM:
			if _sanctum:
				return _sanctum.marker_position() + Vector3.UP * 0.5
		Guidance.Kind.CRYSTAL:
			return CRYSTAL_AT
		Guidance.Kind.TEAR:
			if _tear >= 0 and _tears:
				return _tears.position_of(_tear)
	return target if target != Vector3.INF else CRYSTAL_AT


## Lo visible que debe estar: nada al llegar, menos cuanto más cerca.
func _goal_alpha(at: Vector3) -> float:
	var flat := Vector2(target.x - at.x, target.z - at.z)
	var d: float = flat.length()
	match kind:
		Guidance.Kind.SHARD, Guidance.Kind.TEAR:
			return smoothstep(1.8, 4.5, d)
		Guidance.Kind.CRUSHER:
			if _crusher and _crusher.player_in_range():
				return 0.0
		Guidance.Kind.SANCTUM:
			if _sanctum and _sanctum.player_in_range():
				return 0.0
		Guidance.Kind.CRYSTAL:
			# Es enorme: sólo se señala cuando no está a la vista.
			_project(target)
			return 1.0 if _edge else 0.0
	var k: float = smoothstep(DEF.fade_near_m, DEF.fade_far_m, d)
	return k if _urgent else k * 0.75


## Al llegar a un objetivo urgente, un destello de sonido (una vez por objetivo).
func _check_arrival(goal: float) -> void:
	var stations: bool = kind == Guidance.Kind.CRUSHER or kind == Guidance.Kind.SANCTUM
	if not stations:
		return
	if goal <= 0.0 and _alpha > 0.2 and not _arrived and _urgent:
		_arrived = true
		AudioDirector.play_sfx(ARRIVE_SFX, -4.0)
	elif goal > 0.5:
		_arrived = false


func _color() -> Color:
	match kind:
		Guidance.Kind.SHARD:
			return C_CYAN
		Guidance.Kind.CRUSHER:
			return C_GOLD if _sit.bag_full() else C_PINK
		Guidance.Kind.SANCTUM:
			return C_GOLD
		Guidance.Kind.TEAR:
			return C_PINK
	return C_VIOLET


func _update_world(at: Vector3, delta: float) -> void:
	if _trail == null or not _trail.is_inside_tree():
		return
	var show: bool = kind != Guidance.Kind.NONE and kind != Guidance.Kind.CRYSTAL and visible
	if not show:
		_trail.hide_all(delta)
		return
	var k: float = _alpha if _urgent else 0.0
	var h: float = 0.28 if kind == Guidance.Kind.SHARD else 1.0
	_trail.guide(at, target, _color(), k, k, h, delta)


func _place_labels() -> void:
	var on: bool = kind != Guidance.Kind.NONE and _alpha > 0.01 and visible
	_tag.visible = false
	_dist.visible = false
	if not on:
		return
	_project(target)
	var m: int = roundi(
		Vector2(target.x - _player.global_position.x, target.z - _player.global_position.z).length()
	)
	if kind == Guidance.Kind.CRYSTAL:
		# El cristal es enorme: en vez de sus metros, su nombre.
		_dist.text = _tag.text
		_dist_m = -2
	else:
		# Fuera de la pantalla, lo urgente dice también qué es (la flecha sola no lo cuenta).
		var named: bool = _edge and _urgent and _tag.text != ""
		if m != _dist_m or named != _dist_named:
			_dist_m = m
			_dist_named = named
			_dist.text = ("%s  %d M" % [_tag.text, m]) if named else ("%d M" % m)
	var col: Color = _color()
	_dist.add_theme_color_override(&"font_color", col.lightened(0.35))
	_dist.modulate.a = _alpha
	_dist.visible = true
	if _edge:
		# Flecha y texto juntos sobre una placa oscura (se leen sobre el cielo y la hierba).
		var w: float = _text_w(_dist)
		# Con la dirección de la flecha (8 direcciones): texto y flecha quedan alineados.
		var sd: Vector2 = _snap_dir(_edge_dir)
		var off: float = 12.0 + absf(sd.x) * w * 0.5 + absf(sd.y) * 9.0
		var mid: Vector2 = (_screen - sd * off).round()
		_dist.position = _clamp_label(_dist, mid + Vector2(0, -6))
		var label_rect := Rect2(
			_dist.position + Vector2((TAG_W - w) * 0.5, 0), Vector2(w, UiFonts.LINE)
		)
		_plate = label_rect.merge(Rect2(_screen - sd * 6.0 - Vector2(6, 6), Vector2(12, 12)))
		_plate = _plate.grow(3).abs()
		_plate.position = _plate.position.round()
		_plate.size = _plate.size.round()
		return
	_dist.position = _clamp_label(_dist, _screen + Vector2(0, GEM_LIFT + 12))
	var tag_on: bool = _tag.text != "" and (_urgent or _tag_t > 0.0)
	if tag_on:
		_tag.visible = true
		_tag.add_theme_color_override(&"font_color", col)
		_tag.modulate.a = _alpha * (1.0 if _urgent else clampf(_tag_t / 0.6, 0.0, 1.0))
		_tag.position = _clamp_label(_tag, _screen + Vector2(0, GEM_LIFT - 23 - roundf(_pop * 3.0)))


## Etiqueta centrada en `at`, pero siempre entera dentro de la pantalla.
func _clamp_label(l: Label, at: Vector2) -> Vector2:
	var w: float = _text_w(l)
	var slack: float = (TAG_W - w) * 0.5
	var x: float = clampf(at.x - TAG_W * 0.5, 4.0 - slack, size.x - 4.0 - TAG_W + slack)
	return Vector2(x, at.y).round()


func _text_w(l: Label) -> float:
	return UiFonts.BOLD.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.SMALL).x


## Proyecta un punto del mundo a la pantalla (`_screen`). Si queda fuera (o detrás), lo pega al
## borde y `_edge` queda en true.
func _project(world: Vector3) -> void:
	var sz: Vector2 = size
	var behind: bool = _camera.is_position_behind(world)
	var p: Vector2 = _camera.unproject_position(world)
	_edge = not (
		not behind
		and p.x > SIDE
		and p.x < sz.x - SIDE
		and p.y > _top + STACK_H
		and p.y < sz.y - BOTTOM_GAP
	)
	if not _edge:
		_screen = p.round()
		return
	var center := Vector2(sz.x * 0.5, (_top + sz.y - BOTTOM_GAP) * 0.5)
	var dir: Vector2 = p - center
	if behind:
		# Detrás: la flecha va al lado por el que hay que girarse, a media altura.
		var local: Vector3 = _camera.global_transform.affine_inverse() * world
		dir = Vector2(1.0 if local.x >= 0.0 else -1.0, 0.18)
	var half_x: float = sz.x * 0.5 - SIDE
	var half_y: float = (sz.y - BOTTOM_GAP - _top) * 0.5
	var k: float = minf(half_x / maxf(absf(dir.x), 0.001), half_y / maxf(absf(dir.y), 0.001))
	_screen = (center + dir * k).round()
	_edge_dir = dir.normalized()


func _draw() -> void:
	if kind == Guidance.Kind.NONE or _alpha <= 0.01:
		return
	var col: Color = _color()
	if _edge:
		draw_rect(_plate, Color(C_SHADOW, 0.72 * _alpha))
		draw_rect(_plate, Color(col, 0.55 * _alpha), false, 1.0)
		_draw_arrow(_screen, _edge_dir, col)
	else:
		_draw_gem(_screen + Vector2(0, GEM_LIFT), col)


## Rombo de cristal que gira (el ancho y el brillo cambian por fotogramas, como pixel art
## animado), con un pulso que se abre si el objetivo es urgente.
func _draw_gem(p: Vector2, col: Color) -> void:
	var a: float = _alpha
	var frame: int = int(_t * 8.0) % 8
	var spin: float = cos(float(frame) / 8.0 * TAU)
	var bob: float = roundf(sin(floor(_t * 6.0) * 0.7) * 1.5) - roundf(_pop * 3.0)
	var c := Vector2(p.x, p.y + bob)
	if _urgent:
		var ph: float = fmod(_t, 1.4) / 1.4
		_diamond_outline(c, roundi(lerpf(6.0, 15.0, ph)), Color(col, a * (1.0 - ph) * 0.8))
	# Nunca de canto del todo (una raya de 1 px no se lee como rombo).
	var half: float = roundf(5.0 * (0.45 + 0.55 * absf(spin)))
	var light_left: bool = spin > 0.0
	var top: int = 5
	var bottom: int = 9
	# Sombra (1 px alrededor) y cuerpo, fila a fila.
	for row: int in range(-top - 1, bottom + 2):
		var hw: float = _gem_half(row, top + 1, bottom + 1, half + 1.0)
		if hw >= 0.0:
			draw_rect(Rect2(c.x - hw, c.y + row, hw * 2.0 + 1.0, 1), Color(C_SHADOW, a))
	for row: int in range(-top, bottom + 1):
		var hw: float = _gem_half(row, top, bottom, half)
		if hw < 0.0:
			continue
		var y: float = c.y + row
		draw_rect(Rect2(c.x - hw, y, hw * 2.0 + 1.0, 1), Color(col, a))
		var lit: Color = Color(col.lightened(0.55), a)
		if light_left:
			draw_rect(Rect2(c.x - hw, y, hw, 1), lit)
		else:
			draw_rect(Rect2(c.x + 1.0, y, hw, 1), lit)
		if row > 0:
			draw_rect(Rect2(c.x - hw, y, 1, 1), Color(col.darkened(0.3), a))
	draw_rect(Rect2(c.x - (1.0 if light_left else -1.0), c.y - 2.0, 1, 1), Color(Color.WHITE, a))


## Medio ancho de la fila `row` del rombo (arriba `top` filas, abajo `bottom`), o -1 si fuera.
static func _gem_half(row: int, top: int, bottom: int, half: float) -> float:
	if row < -top or row > bottom:
		return -1.0
	var k: float = 1.0 - (float(-row) / float(top) if row < 0 else float(row) / float(bottom))
	return roundf(half * k)


func _diamond_outline(c: Vector2, r: int, col: Color) -> void:
	for i: int in r + 1:
		var j: int = r - i
		draw_rect(Rect2(c.x + i, c.y + j, 1, 1), col)
		draw_rect(Rect2(c.x - i, c.y + j, 1, 1), col)
		draw_rect(Rect2(c.x + i, c.y - j, 1, 1), col)
		draw_rect(Rect2(c.x - i, c.y - j, 1, 1), col)


## Flecha en el borde de la pantalla hacia el objetivo, en 8 direcciones (pixel art sin rotar),
## que empuja hacia fuera a saltitos.
func _draw_arrow(p: Vector2, dir: Vector2, col: Color) -> void:
	var a: float = _alpha
	var octant: int = _octant(dir)
	var diag: bool = octant % 2 == 1
	var rows: PackedStringArray = ARROW_DIAG if diag else ARROW_SIDE
	var push: float = float(int(_t * 5.0) % 3)
	var snapped_dir: Vector2 = _snap_dir(dir)
	var c: Vector2 = (p - snapped_dir * (6.0 - push)).round()
	var cx: int = 3 if diag else 2
	var cy: int = 3 if diag else 5
	for pass_i: int in 2:
		for y: int in rows.size():
			var row: String = rows[y]
			for x: int in row.length():
				var ch: String = row[x]
				if ch == ".":
					continue
				var q: Vector2 = _turn(Vector2(x - cx, y - cy), octant)
				if pass_i == 0:
					draw_rect(Rect2(c + q - Vector2.ONE, Vector2(3, 3)), Color(C_SHADOW, a))
				else:
					var tone: Color = col.lightened(0.5) if ch == "+" else col
					draw_rect(Rect2(c + q, Vector2.ONE), Color(tone, a))


## Octante de una dirección (0 derecha, 2 abajo, 4 izquierda, 6 arriba).
static func _octant(dir: Vector2) -> int:
	return posmod(roundi(dir.angle() / (PI * 0.25)), 8)


## La dirección redondeada a la más cercana de las 8 de la flecha.
static func _snap_dir(dir: Vector2) -> Vector2:
	return Vector2.from_angle(float(_octant(dir)) * PI * 0.25)


## Gira o refleja un punto de la flecha base (derecha / abajo-derecha) hacia el octante `o`
## (0 derecha, 2 abajo, 4 izquierda, 6 arriba; impares, las diagonales).
static func _turn(v: Vector2, o: int) -> Vector2:
	match o:
		1:
			return v
		2:
			return Vector2(-v.y, v.x)
		3:
			return Vector2(-v.x, v.y)
		4:
			return Vector2(-v.x, v.y)
		5:
			return Vector2(-v.x, -v.y)
		6:
			return Vector2(v.y, -v.x)
		7:
			return Vector2(v.x, -v.y)
	return v
