class_name MagicCircles
extends Node3D
## Círculos mágicos con runas de los niveles 6 a 10 de los hechizos (capa de magia HD).
##
## - Hechizos que se cargan (Bola de Fuego, Choque Térmico): mientras cargas aparecen círculos
##   cada vez más grandes y más lejos, alineados desde las manos hacia donde apuntas y girando
##   en sentidos alternos. Con carga por etapas (`ChargeStages`) cada círculo encaja de golpe
##   al completar su etapa: se dibuja en un instante, llega algo grande y se asienta con un
##   destello, y los que ya estaban laten; con la última (potencia completa) destellan todos,
##   giran más deprisa y sale una onda. Al lanzar, el hechizo los atraviesa: cada uno destella
##   y se abre. Si se cancela, se apagan encogiéndose.
## - Hechizos de toque (Chispa, Escarcha): al lanzar sale de la mano un círculo pequeño que gira
##   rápido y se apaga (dos a nivel 8, tres a nivel 10).
## - Sellos sueltos (`stamp`): un círculo que se dibuja, destella y se apaga donde haga falta: de
##   ellos salen los ecos del Arcano, y tres rodean el pozo de la Gravedad.

const SHADER: Shader = preload("res://fx/hd/hd_magic_circle.gdshader")
const POOL: int = 20
const MAX_CHARGE_CIRCLES: int = 5
## Distancia (m) del primer círculo y separación de los siguientes, que crece.
const FIRST_DIST: float = 1.4
const STEP_DIST: float = 0.75
## Tamaño aparente (escala / distancia) del primer círculo de carga y cuánto crece cada uno: el
## primero algo más ancho que el orbe y cada siguiente un 17 % más grande también en pantalla,
## para que se lean como anillos concéntricos que se abren (no uno encima de otro).
const FIRST_SPAN: float = 0.27
const SPAN_GROWTH: float = 1.17
## Al encajar un círculo de etapa: tiempo en dibujarse, en asentarse y cuánto más grande llega.
const SNAP_SWEEP: float = 0.07
const SNAP_TIME: float = 0.2
const SNAP_OVERSHOOT: float = 0.25
## Destello del círculo que encaja, latido de los que ya estaban y destello de la potencia
## completa (moderados y menores en los círculos grandes: con el resplandor HDR, un círculo
## grande delante de la cámara se quema a blanco).
const SNAP_FLASH: float = 0.85
const STAGE_PULSE: float = 0.3
const FULL_FLASH: float = 0.5
## Opacidad del contorno de los círculos de carga por etapas (delante del orbe; ver el shader).
const CHARGE_INK: float = 0.85
## Cuánto tarda en apagarse un círculo cancelado (s).
const CANCEL_TIME: float = 0.28
## Con pocas etapas los círculos empiezan más arriba en la serie de tamaños (el primero ya fuera
## del resplandor del orbe): con 1 etapa se salta 2 tamaños, con 2 o 3 se salta 1.
const FEW_STAGES_SKIP: PackedInt32Array = [0, 2, 1, 1, 0, 0]
## Onda de la potencia completa: tamaño respecto al primer círculo (sin su rebote), vida (s) y
## destello. Contenida: un círculo cercano a la cámara se hace enorme en pantalla.
const WAVE_SIZE: float = 1.3
const WAVE_LIFE: float = 0.34
const WAVE_FLASH: float = 0.3

var _quads: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
## Estado por quad: 0 libre, 1 de carga, 2 soltándose (destello), 3 de toque, 4 sello (eco, pozo),
## 5 cancelado (se apaga).
var _state: PackedInt32Array = []
var _age: PackedFloat32Array = []
var _spin_speed: PackedFloat32Array = []
var _spin: PackedFloat32Array = []
var _base_scale: PackedFloat32Array = []
## Duración de cada sello (estado 4) y cuánto destella al cerrarse. En los de carga por etapas,
## la edad a la que encajó (-1 = aún no).
var _life: PackedFloat32Array = []
var _flash_peak: PackedFloat32Array = []
var _charge_ids: Array[int] = []
## Círculos pedidos para la carga actual (si el grupo se quedó sin quads, no se recrean cada
## fotograma: eso reiniciaría el encaje de las etapas y repetiría la onda final).
var _charge_count: int = 0
## Tamaños que se saltan los círculos de la carga actual (ver FEW_STAGES_SKIP).
var _ring_skip: int = 0
## Quad de la onda de la potencia completa de las manos (-1 = ninguna): sigue a las manos.
var _wave_id: int = -1
var _origin := Vector3.ZERO
var _dir := Vector3.FORWARD
## Los círculos de carga actuales son del cielo (no de las manos).
var _sky: bool = false
## Última etapa completada de la carga actual y segundos desde entonces.
var _last_stage: int = 0
var _stage_age: float = 10.0


func _ready() -> void:
	top_level = true
	for i: int in POOL:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		mi.mesh = quad
		mi.layers = MagicLayer.MAGIC_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.render_priority = 3
		mat.set_shader_parameter("rune_seed", float(i) * 1.7 + 0.3)
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_quads.append(mi)
		_mats.append(mat)
		_state.append(0)
		_age.append(0.0)
		_spin_speed.append(0.0)
		_spin.append(0.0)
		_base_scale.append(1.0)
		_life.append(1.0)
		_flash_peak.append(0.9)


## Mientras se carga un hechizo combinado: `count` círculos (1..5) que aparecen con la carga `k`,
## de `origin` (las manos) hacia `aim`. Con `stages` > 0 aparecen por etapas (ver
## `ChargeStages`): cada uno encaja de golpe al completar la suya.
## `palette` (opcional): un color por círculo (la Gran Convergencia, uno por elemento).
func charging(
	k: float,
	count: int,
	origin: Vector3,
	aim: Vector3,
	col: Color,
	hot: Color,
	stages: int = 0,
	palette: PackedColorArray = PackedColorArray()
) -> void:
	count = clampi(count, 0, MAX_CHARGE_CIRCLES)
	if _sky:
		_release_charge(false)
		_sky = false
	_origin = origin
	_dir = (aim - origin).normalized() if aim.distance_to(origin) > 0.01 else _dir
	if _charge_count != count or _charge_ids.is_empty():
		_release_charge(false)
		_charge_count = count
		_ring_skip = FEW_STAGES_SKIP[clampi(stages, 0, FEW_STAGES_SKIP.size() - 1)]
		_new_charge()
		for c: int in count:
			var i: int = _free()
			if i < 0:
				break
			_charge_ids.append(i)
			_state[i] = 1
			_age[i] = 0.0
			_life[i] = -1.0
			_spin[i] = randf() * TAU
			_spin_speed[i] = (0.8 + c * 0.25) * (1.0 if c % 2 == 0 else -1.0)
			# Cada uno más grande también en pantalla: se abren en cono hacia el blanco.
			var ring: int = c + _ring_skip
			_base_scale[i] = _dist(ring) * FIRST_SPAN * pow(SPAN_GROWTH, ring)
			# Tonos alternos para distinguir cada anillo (o el de la paleta).
			var ring_col: Color = col if c % 2 == 0 else col.lerp(hot, 0.45)
			if not palette.is_empty():
				ring_col = palette[c % palette.size()]
			_mats[i].set_shader_parameter("color", ring_col)
			_mats[i].set_shader_parameter("color_hot", hot)
			_mats[i].set_shader_parameter("ink_alpha", CHARGE_INK if stages > 0 else 0.55)
			_mats[i].set_shader_parameter("rune_count", 10.0 + c * 3.0)
	var reached: int = _track_stage(k, stages)
	var full: float = 1.0 if stages > 0 and reached >= stages else 0.0
	if _wave_id >= 0:
		# La onda va con las manos (si no, el temblor de la cámara la deja atrás, descentrada).
		_quads[_wave_id].set_meta(&"pos", _origin + _dir * _dist(_ring_skip))
		_quads[_wave_id].set_meta(&"dir", _dir)
	for c: int in _charge_ids.size():
		var i: int = _charge_ids[c]
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.006 + c) * 0.03 * k
		if stages > 0:
			# Por etapas: encaja de golpe al completar la suya.
			var need: int = ChargeStages.stage_of_circle(c, count, stages)
			var snap_scale: float = _staged(i, c, need, stages, reached)
			var dir_sign: float = 1.0 if c % 2 == 0 else -1.0
			_spin_speed[i] = (0.8 + c * 0.25) * dir_sign * (1.0 + full * 1.2)
			_mats[i].set_shader_parameter("intensity", 0.8 + float(reached) / stages * 0.2)
			_place(i, _origin + _dir * _dist(c + _ring_skip), _base_scale[i] * snap_scale * pulse)
			continue
		# Carga continua: cada círculo aparece cuando la carga pasa su umbral, barriendo.
		var start: float = float(c) / float(maxi(count, 1)) * 0.85
		var a: float = clampf((k - start) / 0.18, 0.0, 1.0)
		_mats[i].set_shader_parameter("appear", a)
		_mats[i].set_shader_parameter("intensity", 0.8 + k * 0.5)
		_mats[i].set_shader_parameter("fade", 1.0)
		_mats[i].set_shader_parameter("flash", 0.0)
		_quads[i].visible = a > 0.0
		_place(i, _origin + _dir * _dist(c + _ring_skip), _base_scale[i] * (0.7 + 0.3 * a) * pulse)


## Hechizos del cielo (Meteoro, Trueno, Lluvia): un círculo en el blanco, pegado a la
## superficie, y `count - 1` a lo largo del camino por el que caerá desde `sky` (cada vez más
## grandes y mirando por ese camino: el hechizo los atraviesa todos al caer). Aparecen con la
## carga `k`, del blanco hacia el cielo; con `stages` > 0, el del blanco sale al empezar (marca
## dónde caerá) y los del camino encajan en grupos, uno por etapa.
func charging_sky(
	k: float,
	count: int,
	target: Vector3,
	normal: Vector3,
	sky: Vector3,
	col: Color,
	hot: Color,
	stages: int = 0
) -> void:
	count = clampi(count, 1, POOL - 2)
	if _charge_count != count or _charge_ids.is_empty() or not _sky:
		_release_charge(false)
		_sky = true
		_charge_count = count
		_new_charge()
		for c: int in count:
			var i: int = _free()
			if i < 0:
				break
			_charge_ids.append(i)
			_state[i] = 1
			_age[i] = 0.0
			_life[i] = -1.0
			_spin[i] = randf() * TAU
			_spin_speed[i] = (0.35 + c * 0.12) * (1.0 if c % 2 == 0 else -1.0)
			_base_scale[i] = 2.4 if c == 0 else 2.8 + c * 1.5
			_mats[i].set_shader_parameter("color", col if c % 2 == 0 else col.lerp(hot, 0.45))
			_mats[i].set_shader_parameter("color_hot", hot)
			_mats[i].set_shader_parameter("ink_alpha", CHARGE_INK if stages > 0 else 0.55)
			_mats[i].set_shader_parameter("rune_count", 16.0 + c * 4.0)
	var path: Vector3 = sky - target
	var reached: int = _track_stage(k, stages)
	var full: float = 1.0 if stages > 0 and reached >= stages else 0.0
	for c: int in _charge_ids.size():
		var i: int = _charge_ids[c]
		var s: float
		if stages > 0:
			var need: int = 0 if c == 0 else ChargeStages.stage_of_circle(c - 1, count - 1, stages)
			var snap_scale: float = _staged(i, c, need, stages, reached)
			var dir_sign: float = 1.0 if c % 2 == 0 else -1.0
			_spin_speed[i] = (0.35 + c * 0.12) * dir_sign * (1.0 + full * 1.5)
			_mats[i].set_shader_parameter("intensity", 0.9 + float(reached) / stages * 0.45)
			s = _base_scale[i] * snap_scale
		else:
			var start: float = float(c) / float(maxi(count, 1)) * 0.8
			var a: float = clampf((k - start) / 0.2, 0.0, 1.0)
			_mats[i].set_shader_parameter("appear", a)
			_mats[i].set_shader_parameter("intensity", 0.85 + k * 0.5)
			_mats[i].set_shader_parameter("fade", 1.0)
			_mats[i].set_shader_parameter("flash", 0.0)
			_quads[i].visible = a > 0.0
			s = _base_scale[i] * (0.6 + 0.4 * a)
		if c == 0:
			# En el blanco, pegado a la superficie del cristal.
			_dir = -normal if normal.length() > 0.1 else Vector3.FORWARD
			_place(i, target + normal * 0.15, s)
		else:
			# En la primera parte de la caída (hasta ~24 m sobre el blanco), inclinados hacia el
			# mago para que se lean como círculos y no como rayas.
			var toward: Vector3 = Vector3(path.x, 0.0, path.z).normalized()
			_dir = (-path.normalized() - toward * 0.7).normalized()
			var h: float = 4.0 + 20.0 * float(c - 1) / float(maxi(count - 2, 1))
			_place(i, target + path * (h / maxf(path.y, 1.0)), s)


## Al lanzar el combinado: los círculos destellan y se abren mientras el hechizo los cruza.
func release() -> void:
	_release_charge(true)


## Cancelado (se abre un menú o el libro a media carga): se apagan encogiéndose.
func cancel() -> void:
	_wave_id = -1
	for i: int in _charge_ids:
		if _quads[i].visible:
			_state[i] = 5
			_age[i] = 0.0
			_base_scale[i] = _quads[i].scale.x
		else:
			_free_quad(i)
	_charge_ids.clear()


## Círculos de toque al lanzar con una mano.
func muzzle(origin: Vector3, aim: Vector3, count: int, col: Color, hot: Color) -> void:
	var dir: Vector3 = (aim - origin).normalized()
	for c: int in count:
		var i: int = _free()
		if i < 0:
			return
		_state[i] = 3
		_age[i] = -c * 0.05
		_spin[i] = randf() * TAU
		_spin_speed[i] = (7.0 + c * 2.0) * (1.0 if c % 2 == 0 else -1.0)
		_base_scale[i] = 0.12 + c * 0.07
		_mats[i].set_shader_parameter("color", col)
		_mats[i].set_shader_parameter("color_hot", hot)
		_mats[i].set_shader_parameter("ink_alpha", 0.55)
		_mats[i].set_shader_parameter("rune_count", 12.0)
		_mats[i].set_shader_parameter("appear", 1.0)
		_mats[i].set_shader_parameter("flash", 0.6)
		_mats[i].set_shader_parameter("intensity", 1.1)
		_quads[i].set_meta(&"pos", origin + dir * (0.25 + c * 0.35))
		_quads[i].set_meta(&"dir", dir)
		_quads[i].visible = false


## Sello suelto (ecos del Arcano, pozo de Gravedad): un círculo de `size` m en `pos`, de cara a
## lo largo de `dir`, que se dibuja barriendo, destella (hasta `flash`), gira a `spin_speed` y
## dura `life` s. Los sellos grandes y cerca de la cámara destellan menos (con el resplandor HDR
## se vuelven un disco blanco). Devuelve su índice (o -1 si no queda ninguno libre).
func stamp(
	pos: Vector3,
	dir: Vector3,
	size: float,
	col: Color,
	hot: Color,
	life: float = 0.7,
	spin_speed: float = 3.0,
	flash: float = 0.9
) -> int:
	var i: int = _free()
	if i < 0:
		return -1
	_state[i] = 4
	_age[i] = 0.0
	_life[i] = life
	_flash_peak[i] = flash
	_spin[i] = randf() * TAU
	_spin_speed[i] = spin_speed
	_base_scale[i] = size
	_mats[i].set_shader_parameter("color", col)
	_mats[i].set_shader_parameter("color_hot", hot)
	_mats[i].set_shader_parameter("ink_alpha", 0.55)
	_mats[i].set_shader_parameter("rune_count", clampf(12.0 + size * 2.0, 12.0, 28.0))
	_mats[i].set_shader_parameter("appear", 0.0)
	_mats[i].set_shader_parameter("flash", 0.0)
	_mats[i].set_shader_parameter("fade", 1.0)
	_mats[i].set_shader_parameter("intensity", 1.2)
	_quads[i].set_meta(&"pos", pos)
	_quads[i].set_meta(&"dir", dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD)
	_quads[i].visible = true
	_animate_stamp(i)
	return i


func _process(delta: float) -> void:
	_stage_age += delta
	for i: int in POOL:
		if _state[i] == 0:
			continue
		_age[i] += delta
		_spin[i] += _spin_speed[i] * delta
		_mats[i].set_shader_parameter("spin", _spin[i])
		match _state[i]:
			2:
				# Destello y apertura: 0,45 s.
				var t: float = _age[i] / 0.45
				_mats[i].set_shader_parameter("flash", maxf(0.0, 1.0 - t * 1.5))
				_mats[i].set_shader_parameter("fade", clampf(1.0 - t, 0.0, 1.0))
				_quads[i].scale = Vector3.ONE * _base_scale[i] * (1.0 + t * 0.8)
				if t >= 1.0:
					_free_quad(i)
			3:
				if _age[i] < 0.0:
					continue
				var t: float = _age[i] / 0.38
				_quads[i].visible = true
				_mats[i].set_shader_parameter("fade", clampf(1.0 - t, 0.0, 1.0))
				_mats[i].set_shader_parameter("flash", maxf(0.0, 0.6 - t))
				var pos: Vector3 = _quads[i].get_meta(&"pos")
				var dir: Vector3 = _quads[i].get_meta(&"dir")
				_dir = dir
				_place(i, pos + dir * t * 0.4, _base_scale[i] * (0.6 + t * 0.9))
				if t >= 1.0:
					_free_quad(i)
			4:
				_animate_stamp(i)
			5:
				var t: float = _age[i] / CANCEL_TIME
				_mats[i].set_shader_parameter("fade", clampf(1.0 - t, 0.0, 1.0))
				_mats[i].set_shader_parameter("flash", 0.0)
				_quads[i].scale = Vector3.ONE * _base_scale[i] * maxf(0.05, 1.0 - t * 0.45)
				if t >= 1.0:
					_free_quad(i)


## Sello: se dibuja barriendo en 0,14 s, destella al cerrarse, gira y se apaga al final.
func _animate_stamp(i: int) -> void:
	var t: float = _age[i] / maxf(_life[i], 0.05)
	var a: float = clampf(_age[i] / 0.14, 0.0, 1.0)
	_mats[i].set_shader_parameter("appear", a)
	var flash: float = maxf(0.0, 1.0 - absf(_age[i] - 0.16) * 6.67) * _flash_peak[i]
	_mats[i].set_shader_parameter("flash", flash)
	_mats[i].set_shader_parameter("fade", clampf((1.0 - t) / 0.3, 0.0, 1.0))
	_dir = _quads[i].get_meta(&"dir")
	var pos: Vector3 = _quads[i].get_meta(&"pos")
	_place(i, pos, _base_scale[i] * (0.7 + 0.3 * a + t * 0.2))
	if t >= 1.0:
		_free_quad(i)


## Carga nueva: aún no hay etapas completadas.
func _new_charge() -> void:
	_last_stage = 0
	_stage_age = 10.0


## Etapa completada con la carga `k`; si acaba de cambiar, reinicia el latido. Con la última
## (potencia completa), una onda sale del primer círculo, junto al orbe.
func _track_stage(k: float, stages: int) -> int:
	var reached: int = ChargeStages.stage_at(k, stages)
	if reached != _last_stage:
		_last_stage = reached
		_stage_age = 0.0
		if stages > 0 and reached >= stages and not _charge_ids.is_empty():
			_full_wave.call_deferred(_charge_ids[0])
	return reached


## Potencia completa: un sello algo mayor que el primer círculo, que destella y se apaga (onda
## de energía alrededor del orbe).
func _full_wave(i: int) -> void:
	if _state[i] != 1 or not _quads[i].visible:
		return
	var mat: ShaderMaterial = _mats[i]
	var col: Color = mat.get_shader_parameter("color")
	var hot: Color = mat.get_shader_parameter("color_hot")
	var b: Basis = _quads[i].global_transform.basis
	var size: float = _base_scale[i] * WAVE_SIZE
	var w: int = stamp(
		_quads[i].global_position, -b.z.normalized(), size, col, hot, WAVE_LIFE, 0.0, WAVE_FLASH
	)
	if not _sky:
		_wave_id = w


## Círculo de carga `c` (quad `i`) con etapas: encaja (se dibuja en un instante, llega grande y
## se asienta con un destello) al completar su etapa `need` (0 = desde el principio). Pone sus
## parámetros y devuelve su escala relativa.
func _staged(i: int, c: int, need: int, stages: int, reached: int) -> float:
	if reached < need:
		_life[i] = -1.0
		_quads[i].visible = false
		return 0.7
	if _life[i] < 0.0:
		_life[i] = _age[i]
	var t: float = _age[i] - _life[i]
	var settle: float = maxf(0.0, 1.0 - t / SNAP_TIME)
	var s: float = 1.0 + SNAP_OVERSHOOT * settle * settle
	# El que encaja destella; los que ya estaban laten con cada etapa nueva.
	var damp: float = 1.0 / (1.0 + 0.6 * c)
	var flash: float = maxf(0.0, 1.0 - t * 4.5) * SNAP_FLASH * damp
	flash = maxf(flash, maxf(0.0, 1.0 - _stage_age * 5.0) * STAGE_PULSE * damp)
	if reached >= stages:
		# Potencia completa: destellan todos a la vez y quedan un poco más grandes y vivos.
		flash = maxf(flash, maxf(0.0, 1.0 - _stage_age * 3.0) * FULL_FLASH * damp)
		flash = maxf(flash, (0.04 + 0.04 * sin(_age[i] * 9.0)) * damp)
		s *= 1.04 + 0.1 * maxf(0.0, 1.0 - _stage_age * 4.0)
	_mats[i].set_shader_parameter("appear", clampf(t / SNAP_SWEEP, 0.0, 1.0))
	_mats[i].set_shader_parameter("fade", 1.0)
	_mats[i].set_shader_parameter("flash", flash)
	_quads[i].visible = true
	return s


func _dist(c: int) -> float:
	return FIRST_DIST + STEP_DIST * c


## Pone el quad `i` en `pos`, de cara a lo largo de `_dir` (se ve casi de frente desde la cámara).
func _place(i: int, pos: Vector3, s: float) -> void:
	var z: Vector3 = -_dir
	var up: Vector3 = Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(z).normalized()
	var y: Vector3 = z.cross(x).normalized()
	_quads[i].global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * s), pos)


func _release_charge(burst: bool) -> void:
	_wave_id = -1
	for i: int in _charge_ids:
		if burst and _quads[i].visible:
			_state[i] = 2
			_age[i] = 0.0
		else:
			_free_quad(i)
	_charge_ids.clear()


func _free() -> int:
	for i: int in POOL:
		if _state[i] == 0:
			return i
	return -1


func _free_quad(i: int) -> void:
	if i == _wave_id:
		_wave_id = -1
	_state[i] = 0
	_quads[i].visible = false
