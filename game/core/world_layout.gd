class_name WorldLayout
extends RefCounted
## Dónde está cada cosa en el claro del valle (m). Un solo sitio para que el valle, los caminos,
## el Pilón, el Santuario y el jugador estén de acuerdo.
## El Cristal Madre está en el origen: un racimo que se puede excavar (crystal/data, horneado
## con tools/crystal_volume.py), de 108 m de alto y una base de ~75 m de ancho.
## El aprendiz empieza dentro de su casucha (`HUT`), con la puerta mirando al cristal.

## Radio aproximado de la base del racimo (m), para dejar libre el suelo a su alrededor.
const CRYSTAL_FOOTPRINT: float = 40.0
## La casucha del aprendiz: la puerta (lado -z) da al cristal.
const HUT := Vector3(0.0, 0.0, 78.0)
## Dentro de la casucha, mirando a la puerta.
const PLAYER_START := Vector3(0.0, 0.2, 80.2)
const PYLON := Vector3(-46.0, 0.0, 52.0)
const SANCTUM := Vector3(48.0, 0.0, 50.0)
## La Jaula de Familiares (GDD 4.3): detrás del Pilón, a la vista desde el camino y sin
## pisarlo. Aparece al comprar el primer familiar.
const FAMILIAR_NEST := Vector3(-40.0, 0.0, 60.5)
## Orientación del Santuario: el lado abierto del templete mira al cristal.
const SANCTUM_YAW_DEG: float = 47.0
