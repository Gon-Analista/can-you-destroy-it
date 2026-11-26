class_name CameraRig
extends Camera3D
## Sacudida de cámara por "trauma" (se suma con cada golpe y decae) y golpe de FOV.
## Respeta Settings.screen_shake (accesibilidad). El campo de visión base es el de Opciones
## (Settings.fov); la capa de magia HD lo copia cada fotograma y las manos y los hechizos se
## anclan con project_position, así que todo sigue alineado a cualquier FOV.

@export var max_offset: float = 0.06
@export var max_roll_deg: float = 1.2
@export var decay: float = 2.2

## 0..1: cuánto se está corriendo (abre el campo de visión).
var sprint: float = 0.0
## Cabeceo al andar (lo marca el jugador con la fase de los pasos).
var bob: Vector2 = Vector2.ZERO

var _trauma: float = 0.0
var _fov_kick: float = 0.0
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _dip: float = 0.0
var _dip_vel: float = 0.0
## Retroceso al soltar un combinado: la cámara cabecea hacia arriba (muelle) y el campo de
## visión se abre un instante, como si el hechizo te empujara.
var _recoil: float = 0.0
var _recoil_vel: float = 0.0
var _fov_push: float = 0.0


func _ready() -> void:
	_noise.frequency = 1.6
	Events.spell_impacted.connect(_on_impact)
	# Opciones cambia el FOV con el juego en pausa (sin _process): se aplica ya.
	Settings.changed.connect(_apply_fov)
	Events.spell_cast.connect(_on_cast)


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


## Golpe de campo de visión (grados; negativo = se cierra, como un zoom de golpe). Escala con
## Settings.screen_shake (accesibilidad).
func punch_fov(degrees: float) -> void:
	_fov_kick = minf(_fov_kick, degrees * Settings.screen_shake)


## Retroceso de un hechizo que sale de las manos (`amount` 0..2: un toque .. cargado a tope).
## Escala con Settings.screen_shake (accesibilidad).
func recoil(amount: float) -> void:
	var a: float = clampf(amount, 0.0, 2.5) * Settings.screen_shake
	_recoil_vel += 1.1 * a
	_fov_push = maxf(_fov_push, 4.5 * a)
	add_trauma(0.18 + 0.2 * amount)


func _on_impact(hit: SpellHit) -> void:
	if not hit.by_player:
		return
	# Cada elemento se siente distinto (`ImpactStyle`): la roca sacude, el rayo da un tirón seco
	# hacia dentro, el viento y el arcano empujan el campo de visión hacia fuera.
	var pf: ImpactStyle.Profile = ImpactStyle.profile(ImpactStyle.of(hit))
	add_trauma(hit.tier.shake * (3.0 if hit.resonant else 1.0) * pf.trauma)
	if hit.resonant:
		_fov_kick = -4.0
	elif not hit.minor:
		var kick: float = pf.fov * clampf(hit.tier.crack_radius / 1.6, 0.4, 1.5)
		kick *= Settings.screen_shake
		_fov_kick = minf(_fov_kick, kick) if kick < 0.0 else maxf(_fov_kick, kick)


func _on_cast(_tier: SpellTier, _side: int) -> void:
	_fov_kick = minf(_fov_kick, -0.8)


func _process(delta: float) -> void:
	_t += delta * 60.0
	_trauma = maxf(0.0, _trauma - decay * delta)
	var shake: float = _trauma * _trauma * Settings.screen_shake
	# Caída al aterrizar: muelle amortiguado.
	_dip_vel += (-_dip * 180.0 - _dip_vel * 16.0) * delta
	_dip += _dip_vel * delta
	h_offset = max_offset * shake * _noise.get_noise_2d(_t, 0.0) + bob.x
	v_offset = max_offset * shake * _noise.get_noise_2d(0.0, _t) + bob.y + _dip
	rotation.z = deg_to_rad(max_roll_deg) * shake * _noise.get_noise_2d(_t, _t)
	# Muelle del retroceso en pasos cortos (estable aunque el fotograma sea largo).
	var steps: int = clampi(ceili(delta * 120.0), 1, 8)
	var dt: float = delta / float(steps)
	for i: int in steps:
		_recoil_vel += (-_recoil * 160.0 - _recoil_vel * 15.0) * dt
		_recoil += _recoil_vel * dt
	rotation.x = _recoil
	_fov_push = lerpf(_fov_push, 0.0, 1.0 - exp(-delta * 7.0))
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-delta * 10.0))
	_apply_fov()


func _apply_fov() -> void:
	fov = Settings.fov + _fov_kick + _fov_push + sprint * 7.0


## Aterrizar: la cámara se hunde y rebota, más cuanto más fuerte la caída.
func land(strength: float) -> void:
	_dip_vel -= clampf(strength, 0.0, 1.0) * 2.2
