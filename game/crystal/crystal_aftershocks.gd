class_name CrystalAftershocks
extends Node
## Réplicas de los golpes enormes (combinados cargados a tope de nivel alto). Un cráter de
## `MotherCrystal._dig` no pasa de `MAX_RADIUS`: si el daño pediría uno mayor, el golpe principal
## se queda en ese tope y el resto del volumen se lo llevan réplicas alrededor, una por fotograma
## (excavar cuesta en el hilo principal), cada una con su estallido y su polvo. La esencia ya la
## descontó el golpe principal: las réplicas no la vuelven a contar.

## Radio máximo (m) de un cráter (el de siempre).
const MAX_RADIUS: float = 14.0
## Tope de réplicas por golpe y su radio respecto al cráter principal.
const MAX_SHOCKS: int = 10
const SHOCK_RADIUS: float = 0.8
## Segundos entre réplicas (como mucho una por fotograma).
const INTERVAL: float = 0.05

var _crystal: MotherCrystal
var _queue: Array[Vector4] = []
var _normals: Array[Vector3] = []
var _tiers: Array[SpellTier] = []
var _wait: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(crystal: MotherCrystal) -> void:
	_crystal = crystal
	_rng.randomize()
	set_process(false)


## Golpe en `at` (global) con normal `normal` que pediría un cráter de `wanted` m: encola las
## réplicas que hagan falta para llevarse ese volumen (el volumen crece con el cubo del radio),
## que estallan con el aspecto `tier`.
func queue(at: Vector3, normal: Vector3, wanted: float, tier: SpellTier) -> void:
	if wanted <= MAX_RADIUS:
		return
	var r: float = MAX_RADIUS * SHOCK_RADIUS
	var extra: float = pow(wanted, 3.0) - pow(MAX_RADIUS, 3.0)
	var n: int = clampi(ceili(extra / pow(r, 3.0)), 1, MAX_SHOCKS)
	var n_hat: Vector3 = normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var t1: Vector3 = n_hat.cross(Vector3.UP)
	if t1.length() < 0.1:
		t1 = n_hat.cross(Vector3.RIGHT)
	t1 = t1.normalized()
	var t2: Vector3 = n_hat.cross(t1).normalized()
	# Se reparten en espiral alrededor del cráter, cada vez más lejos y algo hacia dentro.
	var spread: float = minf(wanted, MAX_RADIUS * 2.6)
	for i: int in n:
		var a: float = float(i) * 2.39996 + _rng.randf() * 0.4
		var d: float = spread * sqrt((float(i) + 0.6) / float(n))
		var p: Vector3 = at + (t1 * cos(a) + t2 * sin(a)) * d - n_hat * r * 0.35
		_queue.append(Vector4(p.x, p.y, p.z, r * _rng.randf_range(0.85, 1.1)))
		_normals.append(n_hat)
		_tiers.append(tier)
	_wait = 0.12
	set_process(true)


func is_busy() -> bool:
	return not _queue.is_empty()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	if _queue.is_empty() or _crystal == null:
		set_process(false)
		return
	_wait = INTERVAL
	var q: Vector4 = _queue.pop_front()
	var n: Vector3 = _normals.pop_front()
	_crystal.aftershock(Vector3(q.x, q.y, q.z), n, q.w, _tiers.pop_front())
