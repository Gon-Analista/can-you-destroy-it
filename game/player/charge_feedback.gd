class_name ChargeFeedback
extends Node
## El golpe de cada etapa de la carga de un combinado (ver ChargeStages): al encajar un círculo
## suena una campana con su "thrum" (más aguda en cada etapa, por la pentatónica de La), la
## cámara da un tirón y cierra un poco el campo de visión, las manos retroceden y se iluminan,
## el orbe destella y la mirilla late (`Events.spell_charge_stage`). La última etapa es la
## potencia completa: suena el acorde grande y todo pega más fuerte. El bucle de carga sube a
## escalones, uno por etapa. Lo crea y lo llama SpellCaster.

## Campanas de las etapas intermedias, de grave a aguda (La4, Do#5, Mi5, Fa#5). Con menos de 5
## etapas se usan las últimas: la de antes de la potencia completa siempre es el Fa#.
const STAGE_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_charge_stage_01.ogg"),
	preload("res://audio/sfx/sfx_charge_stage_02.ogg"),
	preload("res://audio/sfx/sfx_charge_stage_03.ogg"),
	preload("res://audio/sfx/sfx_charge_stage_04.ogg"),
]
const FULL_SFX: AudioStream = preload("res://audio/sfx/sfx_charge_full_01.ogg")
## Los hechizos del cielo suenan una cuarta más grave (La -> Mi: siguen en la tonalidad).
const SKY_PITCH: float = 0.75
## Tono y volumen del bucle de carga sin cargar y con la carga completa.
const LOOP_PITCH := Vector2(0.85, 1.25)
const LOOP_DB := Vector2(-18.0, -6.0)
## Lo que tarda el bucle en subir cada escalón (1/s).
const LOOP_GLIDE: float = 7.0

var camera: Camera3D
var hands: WizardHands

## Nivel actual del bucle de carga (0..1).
var _loop_level: float = 0.0


## Empieza una carga con `stages` etapas (0 = continua).
func begin(stages: int) -> void:
	_loop_level = 0.0
	Events.spell_charge_stage.emit(0, stages)


## La carga termina (lanzada o cancelada).
func end() -> void:
	Events.spell_charge_stage.emit(-1, 0)


## Se completa la etapa `stage` de `total`. `sky`: hechizo del cielo (los círculos están sobre
## el blanco).
func stage(stage_index: int, total: int, sky: bool) -> void:
	var full: bool = stage_index >= total
	var f: float = float(stage_index) / float(maxi(total, 1))
	var pitch: float = SKY_PITCH if sky else 1.0
	if full:
		AudioDirector.play_sfx(FULL_SFX, -2.0, pitch)
	else:
		var idx: int = STAGE_SFX.size() - (total - stage_index)
		AudioDirector.play_sfx(
			STAGE_SFX[clampi(idx, 0, STAGE_SFX.size() - 1)], lerpf(-9.0, -5.0, f), pitch
		)
	if camera is CameraRig:
		var rig := camera as CameraRig
		rig.add_trauma(0.32 if full else 0.1 + 0.08 * f)
		rig.punch_fov(-3.2 if full else -(0.7 + 1.1 * f))
	if hands:
		hands.play_charge_stage(stage_index, total)
	Events.spell_charge_stage.emit(stage_index, total)


## Bucle de carga: con etapas sube a escalones (y un poco dentro de cada una); sin etapas, con
## la carga `k`.
func update_loop(player: AudioStreamPlayer, k: float, stages: ChargeStages, delta: float) -> void:
	var target: float = k
	if stages.is_staged():
		var step: float = 1.0 / float(stages.count)
		var inside: float = clampf(k - float(stages.reached) * step, 0.0, step)
		target = float(stages.reached) * step + inside * 0.15
	_loop_level = move_toward(_loop_level, target, delta * LOOP_GLIDE)
	player.pitch_scale = lerpf(LOOP_PITCH.x, LOOP_PITCH.y, _loop_level)
	player.volume_db = lerpf(LOOP_DB.x, LOOP_DB.y, _loop_level)
