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


func _ready() -> void:
	_noise.frequency = 1.6
	Events.spell_impacted.connect(_on_impact)
	Events.spell_cast.connect(_on_cast)


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _on_impact(hit: SpellHit) -> void:
	if not hit.by_player:
		return
	add_trauma(hit.tier.shake * (3.0 if hit.resonant else 1.0))
	if hit.resonant:
		_fov_kick = -4.0


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
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-delta * 10.0))
	fov = Settings.fov + _fov_kick + sprint * 7.0


## Aterrizar: la cámara se hunde y rebota, más cuanto más fuerte la caída.
func land(strength: float) -> void:
	_dip_vel -= clampf(strength, 0.0, 1.0) * 2.2
