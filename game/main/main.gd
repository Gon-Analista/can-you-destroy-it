extends Node3D
## Escena raíz provisional: valida el pipeline pixel art (640x360, escalado entero)
## y el cableado del estado. Se reemplaza en M1 por el valle real.

@onready var _pylon_label: Label = %PylonLabel
@onready var _fps_label: Label = %FpsLabel


func _ready() -> void:
	Events.pylon_changed.connect(_on_pylon_changed)
	_fps_label.visible = OS.is_debug_build()
	GameState.emit_all()


func _process(_delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "%d fps" % Engine.get_frames_per_second()


func _on_pylon_changed(_progress: int, ratio: float) -> void:
	_pylon_label.text = tr("Pilón de Maná: %.2f %%") % (ratio * 100.0)
