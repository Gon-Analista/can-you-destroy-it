class_name WorldLayout
extends RefCounted
## Dónde está cada cosa en el claro del valle (m). Un solo sitio para que el valle, los caminos,
## el Pilón, el Santuario y el jugador estén de acuerdo.
## El Cristal Madre está en el origen: un racimo que se puede excavar (crystal/data, horneado
## con tools/crystal_volume.py), de 63 m de alto y una base de ~42 m de ancho.

## Radio aproximado de la base del racimo (m), para dejar libre el suelo a su alrededor.
const CRYSTAL_FOOTPRINT: float = 24.0
const PLAYER_START := Vector3(0.0, 0.2, 50.0)
const PYLON := Vector3(-33.0, 0.0, 36.0)
const SANCTUM := Vector3(35.0, 0.0, 34.0)
## Orientación del Santuario: el lado abierto del templete mira al cristal.
const SANCTUM_YAW_DEG: float = 47.0
