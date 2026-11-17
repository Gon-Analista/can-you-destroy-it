class_name WorldLayout
extends RefCounted
## Dónde está cada cosa en el claro del valle (m). Un solo sitio para que el valle, los caminos,
## el Pilón, el Santuario y el jugador estén de acuerdo.
## El Cristal Madre está en el origen; su punta principal mide ≈ 57 m (30 veces el mago, GDD 4.1).

const CRYSTAL_SCALE: float = 2.3
## Radio aproximado de la base del racimo (m), para dejar libre el suelo a su alrededor.
const CRYSTAL_FOOTPRINT: float = 13.0
const PLAYER_START := Vector3(0.0, 0.2, 32.0)
const PYLON := Vector3(-22.0, 0.0, 21.0)
const SANCTUM := Vector3(23.0, 0.0, 22.0)
## Orientación del Santuario: el lado abierto del templete mira al cristal.
const SANCTUM_YAW_DEG: float = 47.0
