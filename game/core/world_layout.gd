class_name WorldLayout
extends RefCounted
## Dónde está cada cosa en el claro del valle (m). Un solo sitio para que el valle, los caminos,
## el Pilón, el Santuario y el jugador estén de acuerdo.
## El Cristal Madre está en el origen: un racimo que se puede excavar (crystal/data, horneado
## con tools/crystal_volume.py), de ~135 m de alto y una base de ~95 m de ancho: un 25 % más
## grande que el primero. Las estaciones se alejaron en proporción; la casucha no se movió.
## El aprendiz empieza dentro de su casucha (`HUT`), con la puerta mirando al cristal.

## Radio aproximado de la base del racimo (m), para dejar libre el suelo a su alrededor.
const CRYSTAL_FOOTPRINT: float = 50.0
## La casucha del aprendiz: la puerta (lado -z) da al cristal.
const HUT := Vector3(0.0, 0.0, 78.0)
## Dentro de la casucha, mirando a la puerta.
const PLAYER_START := Vector3(0.0, 0.2, 80.2)
const PYLON := Vector3(-53.0, 0.0, 60.0)
const SANCTUM := Vector3(55.0, 0.0, 57.5)
## La Jaula de Familiares (GDD 4.3): detrás del Pilón, a la vista desde el camino y sin
## pisarlo. Aparece al comprar el primer familiar.
const FAMILIAR_NEST := Vector3(-47.0, 0.0, 68.5)
## Orientación del Santuario: el lado abierto del templete mira al cristal.
const SANCTUM_YAW_DEG: float = 47.0
## El Espejo del Archimago (GDD 4.3): junto al Santuario, en el lado del cristal y a más de 6 m
## del atril (no se pisan los dos "F"), mirando hacia el claro.
const ARCHMAGE_MIRROR := Vector3(59.8, 0.0, 52.1)
const ARCHMAGE_MIRROR_YAW_DEG: float = -130.0
## La Mesa de Runas (GDD 4.3): al otro lado del Santuario, junto al final de su camino (a más
## de 6 m del atril y del espejo), con su frente hacia el claro.
const RUNE_TABLE := Vector3(48.8, 0.0, 62.9)
const RUNE_TABLE_YAW_DEG: float = -104.0
## La Vitrina del Báculo (GDD 4.3): al sur del final del camino del Santuario, a la vista al
## llegar y a más de 6 m del atril, del espejo y de la mesa, con su frente hacia el camino.
const STAFF_VITRINE := Vector3(47.5, 0.0, 51.0)
const STAFF_VITRINE_YAW_DEG: float = -60.0
