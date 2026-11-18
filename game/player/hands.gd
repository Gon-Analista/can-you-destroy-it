class_name WizardHands
extends CanvasLayer
## Manos del mago en primera persona. Cada mano lleva su elemento (GDD 5.2): una llamita flota
## sobre cada palma. Al pulsar las dos a la vez, las manos se juntan, las dos llamas viajan al
## centro y se funden en el hechizo combinado (la Bola de Fuego), que crece mientras se mantiene.
## Sprites pixel art 2D de Sprite AI (ver docs/sprite_ai.md): una tira de 6 frames de la mano
## IZQUIERDA en vertical pasando de abierta a ahuecada; la derecha es su reflejo. Los hechizos
## son `SpellOrb` 3D anclados a la cámara.
##
## Todo lo gobiernan las cargas, siempre a píxel entero (sin rotar ni escalar los sprites):
##   recién lanzada -> la mano baja, abierta, sin llama
##   recargando     -> sube a su lado y la llama vuelve a encenderse y crece
##   combinando     -> las manos se juntan y se ahuecan; las llamas se funden en el orbe central
##   lanzar         -> empujón hacia arriba de la mano (o de las dos) y la llama (u orbe) estalla

const STRIP: Texture2D = preload("res://player/hands/hand_l_vertical_strip.png")
const FRAMES: int = 6
const FRAME_SIZE := Vector2(192, 192)
## Esquina superior izquierda de la mano izquierda (pantalla de 640x360): abajo tras lanzar,
## en alto con la llama lista y juntas sosteniendo el hechizo combinado.
const REST_POS := Vector2(70, 228)
const READY_POS := Vector2(84, 194)
const JOINED_POS := Vector2(158, 188)
## La llama flota sobre la punta de los dedos (las manos 2D tapan el 3D que quede detrás):
## posición dentro del sprite de la mano izquierda.
const FLAME_IN_SPRITE := Vector2(116, 0)
## El hechizo combinado flota sobre las palmas juntas: altura respecto al borde superior.
const ORB_ABOVE_SPRITE_TOP: float = 38.0
## Distancia a la cámara de las llamas con el FOV de serie (ver `orb_depth`).
const ORB_DEPTH: float = 0.85
const ORB_DEPTH_FOV: float = 70.0
## Entre las palmas, el fuego es una bola que gira con lenguas cortas: largas, subirían hasta
## la mira y taparían el blanco.
const COMBO_FLOW: float = 0.4
## Empujón al lanzar: las manos suben y se cierran hacia el centro.
const CAST_PUSH := Vector2(10, -22)
## Velocidad a la que las manos se juntan y se separan (1/s).
const JOIN_SPEED: float = 9.0
## A partir de esta mezcla las llamas ya se han fundido en el orbe central.
const MERGED_AT: float = 0.8
## Tinte de las manos cuando el hechizo las ilumina (HDR suave).
const HAND_GLOW := Color(1.35, 1.08, 0.82)
## Destello de las manos cuando encaja una etapa de la carga (y más fuerte con la última).
const STAGE_GLOW := Color(1.9, 1.55, 1.15)
const NIGHT_TINT := Color(0.5, 0.55, 0.85)
const LEVEL_UP_SFX: AudioStream = preload("res://audio/sfx/sfx_spell_combine_01.ogg")

## Carga de cada mano (0 = recién lanzada, 1 = lista). [izquierda, derecha]
var charges: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
## Carga del hechizo combinado mientras las manos están juntas (0..1).
var combine_charge: float = 0.0
var move_speed: float = 0.0
## Si es false no se muestran los hechizos propios (la galería de VFX pone el suyo).
var orb_enabled: bool = true:
	set(value):
		orb_enabled = value
		_apply_orb_visibility()
## El báculo (aparece al comprarlo; ver WizardStaff), detrás de las manos.
var staff: WizardStaff

var _sprites: Array[Sprite2D] = []
var _pending_flare: bool = false
var _flare_side: Array[bool] = [false, false]
var _night: float = 0.0
var _toss_side: int = 0
var _grimoire_open: bool = false
var _flames: Array[SpellOrb] = []
var _flame_spent: Array[bool] = [false, false]
var _combo_orb: SpellOrb
var _camera: Camera3D
var _combining: bool = false
var _join: float = 0.0
var _kick: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _kick_vel: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _grab: float = 0.0
var _grab_vel: float = 0.0
var _ready_pop: float = 0.0
## Destello de las manos al completar una etapa de la carga (decae).
var _stage_glow: float = 0.0
var _t: float = 0.0
var _walk_phase: float = 0.0


func _ready() -> void:
	add_to_group(&"night_listeners")
	add_to_group(&"wizard_hands")
	Events.grimoire_opened.connect(func() -> void: _grimoire_open = true)
	Events.grimoire_closed.connect(
		func() -> void:
			_grimoire_open = false
			_play_level_up()
	)
	# El FOV de Opciones cambia en pausa: las llamas se recolocan a su nueva distancia (diferido,
	# cuando la cámara ya tiene el FOV nuevo).
	Settings.changed.connect(
		func() -> void:
			if _camera:
				_place_orbs.call_deferred()
	)
	layer = 0
	for side: int in 2:
		var s := Sprite2D.new()
		s.name = "HandL" if side == 0 else "HandR"
		s.texture = STRIP
		s.hframes = FRAMES
		s.centered = false
		s.flip_h = side == 1
		add_child(s)
		_sprites.append(s)


## Ancla los hechizos a la cámara: `hand_visual` es la llama de cada palma y `combo_visual`
## el orbe que se forma al juntar las manos (lo llama el jugador).
func attach_camera(
	camera: Camera3D, hand_visual: SpellVisualDef, combo_visual: SpellVisualDef
) -> void:
	_camera = camera
	for side: int in 2:
		var flame := SpellOrb.new()
		flame.name = "HandFlameL" if side == 0 else "HandFlameR"
		flame.def = hand_visual
		flame.charge = charges[side]
		camera.add_child(flame)
		_flames.append(flame)
	_combo_orb = SpellOrb.new()
	_combo_orb.name = "HandsComboOrb"
	_combo_orb.def = combo_visual
	_combo_orb.charge = 0.0
	camera.add_child(_combo_orb)
	_combo_orb.visible = false
	_apply_orb_visibility()
	_place_orbs()
	staff = WizardStaff.new()
	staff.name = "Staff"
	add_child(staff)
	move_child(staff, 0)
	staff.setup(self, camera)


## Lanzar con una mano (0 izquierda, 1 derecha): su llama estalla y la mano da un empujón.
func play_cast(side: int) -> void:
	_kick_vel[side] = 15.0
	if side < _flames.size() and not _flames[side].is_releasing():
		_flames[side].release()
		_flame_spent[side] = true


## Las manos empiezan a juntarse: el orbe central aparece pequeño entre ellas.
## Las manos se juntan; `visual` es el aspecto del hechizo combinado de esta pareja de elementos.
func begin_combine(visual: SpellVisualDef = null) -> void:
	if visual and _combo_orb and _combo_orb.def != visual:
		var old: SpellOrb = _combo_orb
		_combo_orb = SpellOrb.new()
		_combo_orb.name = "HandsComboOrb"
		_combo_orb.def = visual
		old.name = "OldComboOrb"
		old.queue_free()
		_camera.add_child(_combo_orb)
	_combining = true
	combine_charge = 0.0
	if _combo_orb:
		_combo_orb.appear()
		# Lenguas cortas (también en el Meteoro, cuyo fuego va centrado en la roca: más largas
		# llegaban a la mira con la carga completa).
		_combo_orb.set_flow(Vector2(0.0, -1.0), COMBO_FLOW)
		_combo_orb.charge = 0.0
		_combo_orb.visible = orb_enabled


## Se lanza el hechizo combinado: el orbe sale volando (lo sustituye el proyectil), las dos
## manos empujan y se separan.
func release_combine() -> void:
	_combining = false
	for side: int in 2:
		_kick_vel[side] = 18.0
		_flame_spent[side] = true
		if side < _flames.size():
			_flames[side].visible = false
	# El proyectil sale exactamente de donde estaba el orbe: éste se apaga sin estallar.
	if _combo_orb:
		_combo_orb.visible = false


## Se completa una etapa de la carga (`stage` de `total`): las manos dan un tirón hacia abajo
## (el círculo empuja), se iluminan y el orbe destella. La última, más fuerte.
func play_charge_stage(stage: int, total: int) -> void:
	var full: bool = stage >= total
	var f: float = float(stage) / float(maxi(total, 1))
	for side: int in 2:
		_kick_vel[side] = -(6.0 + 6.0 * f) * (1.6 if full else 1.0)
	_stage_glow = 1.0 if full else 0.55 + 0.3 * f
	if full:
		_ready_pop = 1.0
	if _combo_orb and _combining:
		_combo_orb.flare(0.55 if full else 0.2 + 0.15 * f)


## Se deshace la combinación sin lanzar (se abre un menú a media carga): el orbe se apaga y
## las llamas vuelven a cada mano, sin gastarse.
func cancel_combine() -> void:
	_combining = false
	combine_charge = 0.0
	_stage_glow = 0.0
	if _combo_orb:
		_combo_orb.visible = false
	for side: int in 2:
		_kick_vel[side] = -6.0


## Cambia la llama de las dos manos (al subir de nivel la Chispa pasa a Llama, a Llama mágica...).
## Recrea los orbes sólo si el aspecto es otro: ocurre al comprar una mejora, no en caliente.
func set_flame_visual(def: SpellVisualDef, celebrate: bool = false, only_side: int = -1) -> void:
	if def == null or _camera == null:
		return
	var changed: bool = false
	for side: int in _flames.size():
		if only_side >= 0 and side != only_side:
			continue
		if _flames[side].def == def:
			continue
		var old: SpellOrb = _flames[side]
		var flame := SpellOrb.new()
		flame.name = "HandFlame%s" % ("L" if side == 0 else "R")
		old.name = "OldFlame"
		flame.def = def
		flame.charge = charges[side]
		old.queue_free()
		_camera.add_child(flame)
		_flames[side] = flame
		_flame_spent[side] = false
		_flare_side[side] = true
		changed = true
	_place_orbs()
	# Al subir de nivel (no al empezar), la transformación se ve en cuanto se cierra el
	# Grimorio: con el libro abierto quedaría tapada.
	if celebrate and changed:
		_pending_flare = true
		if not _grimoire_open:
			_play_level_up.call_deferred()


## Al cambiar de elemento con Q / E: la mano da un tirón y su llama nueva se enciende con un
## destello pequeño.
func play_switch(side: int) -> void:
	_kick_vel[side] = -10.0
	if side < _flames.size():
		_flames[side].flare()


## Las llamas nuevas se encienden de golpe: las manos dan un tirón, destello, onda, chispas y
## un acorde que sube. Que subir de nivel se note.
func _play_level_up() -> void:
	if not _pending_flare:
		return
	_pending_flare = false
	for side: int in _flames.size():
		if not _flare_side[side]:
			continue
		_flare_side[side] = false
		_flames[side].flare()
		_kick_vel[side] = -14.0
	_ready_pop = 1.0
	AudioDirector.play_sfx(LEVEL_UP_SFX, -2.0)


func set_night(k: float) -> void:
	_night = k


## Pantalla de carga: enciende un momento cada aspecto posible de las llamas (con su destello
## y su estallido) delante de la cámara, para compilarlos antes de jugar.
func warm_up(defs: Array[SpellVisualDef]) -> void:
	var temp: Array[SpellOrb] = []
	for i: int in defs.size():
		var o := SpellOrb.new()
		o.def = defs[i]
		_camera.add_child(o)
		o.position = Vector3((float(i) - defs.size() * 0.5) * 0.12, 0.0, -1.2)
		o.flare()
		temp.append(o)
	await get_tree().create_timer(0.25).timeout
	for o: SpellOrb in temp:
		o.release()
	await get_tree().create_timer(0.8).timeout
	for o: SpellOrb in temp:
		o.queue_free()


func is_combining() -> bool:
	return _combining


## Al echar un cristal a la tolva: las manos se alternan dando un pequeño lanzamiento.
func play_toss() -> void:
	_toss_side = 1 - _toss_side
	_kick_vel[_toss_side] = 9.0


## Al recoger un fragmento: tirón hacia abajo (lo atrapa).
func play_grab() -> void:
	_grab_vel = 10.0


func play_ready() -> void:
	_ready_pop = 1.0


## Punto de la pantalla del que sale el hechizo: la llama de esa mano, o el centro entre las
## palmas si `side` es 2 (hechizo combinado).
## Distancia a la que van las llamas para que se vean siempre del mismo tamaño en pantalla que
## las manos 2D, sea cual sea el campo de visión (Opciones): más cerca cuanto más abierto.
static func orb_depth(cam: Camera3D) -> float:
	var ref: float = tan(deg_to_rad(ORB_DEPTH_FOV) * 0.5)
	return ORB_DEPTH * ref / tan(deg_to_rad(clampf(cam.fov, 20.0, 150.0)) * 0.5)


func palm_screen_position(side: int) -> Vector2:
	if side >= 2:
		return _combo_screen_position()
	return _flame_screen_position(side)


func _process(delta: float) -> void:
	_t += delta
	_walk_phase += delta * move_speed * 1.7
	_ready_pop = maxf(0.0, _ready_pop - delta * 3.0)
	_stage_glow = maxf(0.0, _stage_glow - delta * 3.5)
	for side: int in 2:
		_spring_kick(side, delta)
	_grab = _spring_grab(_grab, delta)
	var join_target: float = 1.0 if _combining else 0.0
	_join = move_toward(_join, join_target, delta * JOIN_SPEED * (1.0 if _combining else 0.6))
	var join_eased: float = smoothstep(0.0, 1.0, _join)
	var screen_w: float = get_viewport().get_visible_rect().size.x
	for side: int in 2:
		var sprite: Sprite2D = _sprites[side]
		var closed: float = _ease(charges[side])
		sprite.frame = clampi(
			int(round(lerpf(closed, float(FRAMES - 1), join_eased))), 0, FRAMES - 1
		)
		var pos: Vector2 = _hand_pos(side)
		if side == 1:
			pos.x = screen_w - FRAME_SIZE.x - pos.x
		# Al cargar el hechizo combinado las manos tiemblan, más cuanto más carga (a píxel entero).
		if _combining:
			var amp: float = combine_charge * 2.0
			pos += Vector2(randf_range(-amp, amp), randf_range(-amp, amp) * 0.5)
		sprite.position = pos.round()
		# La luz del hechizo baña las manos: cálidas al cargar la Bola de Fuego y un poco al
		# sostener su llama (las manos son 2D y no reciben la luz 3D del orbe).
		var warm: float = 0.25 * _ease(charges[side]) + combine_charge * join_eased * 0.9
		# De noche las manos se oscurecen (son 2D: no reciben luz), salvo lo que ilumina el hechizo.
		var base: Color = Color.WHITE.lerp(NIGHT_TINT, _night)
		sprite.modulate = base.lerp(HAND_GLOW, clampf(warm + _night * 0.25, 0.0, 1.0))
		if _stage_glow > 0.0:
			sprite.modulate = sprite.modulate.lerp(STAGE_GLOW, minf(_stage_glow, 1.0))
	_update_orbs()


## Posición de la esquina de la mano `side` en coordenadas de la mano izquierda (la derecha es
## su reflejo), antes de redondear.
func _hand_pos(side: int) -> Vector2:
	var pos: Vector2 = REST_POS.lerp(READY_POS, _ease(charges[side]))
	pos = pos.lerp(JOINED_POS, smoothstep(0.0, 1.0, _join))
	pos += CAST_PUSH * _kick[side] + Vector2(0, 6.0 * _grab) + _bob()
	# Latido al completar la carga: las manos se aprietan un poco hacia el centro.
	pos.x += _ready_pop * 3.0
	return pos


func _flame_screen_position(side: int) -> Vector2:
	var screen_w: float = (
		640.0 if not is_inside_tree() else get_viewport().get_visible_rect().size.x
	)
	var pos: Vector2 = _hand_pos(side) + FLAME_IN_SPRITE
	if side == 1:
		pos.x = screen_w - pos.x
	# Al juntar las manos, las llamas viajan hacia el centro donde se funden.
	return pos.lerp(_combo_screen_position(), smoothstep(0.0, MERGED_AT, _join))


func _combo_screen_position() -> Vector2:
	var screen_w: float = (
		640.0 if not is_inside_tree() else get_viewport().get_visible_rect().size.x
	)
	var y: float = (_hand_pos(0).y + _hand_pos(1).y) * 0.5 + ORB_ABOVE_SPRITE_TOP
	return Vector2(screen_w * 0.5, y)


func _bob() -> Vector2:
	var breathe := Vector2(0, sin(_t * 1.6) * 1.5)
	var walk := (
		Vector2(cos(_walk_phase) * 2.0, absf(sin(_walk_phase)) * 4.0) * minf(move_speed / 4.0, 1.0)
	)
	return breathe + walk


## La mano se cierra deprisa al principio y se asienta al final.
static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 2.0)


## Muelle amortiguado del empujón de cada mano.
func _spring_kick(side: int, delta: float) -> void:
	var vel: float = _kick_vel[side]
	vel += (-_kick[side] * 240.0 - vel * 20.0) * delta
	_kick[side] += vel * delta
	_kick_vel[side] = vel


func _spring_grab(value: float, delta: float) -> float:
	_grab_vel += (-value * 240.0 - _grab_vel * 20.0) * delta
	return value + _grab_vel * delta


func _update_orbs() -> void:
	if _combo_orb == null:
		return
	_place_orbs()
	var merged: bool = _join >= MERGED_AT
	for side: int in 2:
		var flame: SpellOrb = _flames[side]
		# El estallido puede durar más que la recarga: la llama nueva se enciende en cuanto la
		# recarga pasa del 20 %, haya acabado o no.
		if _flame_spent[side] and charges[side] > 0.2 and not _combining:
			_flame_spent[side] = false
			flame.appear()
		if flame.is_releasing() or _flame_spent[side]:
			continue
		flame.visible = orb_enabled and not merged
		# Mientras viajan al centro, las llamas se encogen: su fuego pasa al orbe central.
		var shrink: float = 1.0 - smoothstep(0.0, MERGED_AT, _join)
		flame.charge = maxf(charges[side] * lerpf(0.4, 1.0, shrink), 0.05)
	if _combining and not _combo_orb.is_releasing():
		# El orbe central nace de las dos llamas: crece al fundirse y luego con la carga.
		var merge: float = smoothstep(0.3, MERGED_AT, _join)
		_combo_orb.visible = orb_enabled and merge > 0.0
		_combo_orb.charge = maxf(merge * lerpf(0.15, 1.0, combine_charge), 0.02)


func _place_orbs() -> void:
	for side: int in 2:
		_place(_flames[side], _flame_screen_position(side))
	_place(_combo_orb, _combo_screen_position())


func _place(orb: SpellOrb, screen: Vector2) -> void:
	var world: Vector3 = _camera.project_position(screen, orb_depth(_camera))
	orb.position = _camera.to_local(world)


func _apply_orb_visibility() -> void:
	for flame: SpellOrb in _flames:
		flame.visible = orb_enabled and flame.visible
	if _combo_orb:
		_combo_orb.visible = orb_enabled and _combining
