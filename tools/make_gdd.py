import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer,
                                Table, TableStyle, PageBreak, KeepTogether, NextPageTemplate)
from reportlab.graphics.shapes import Drawing, Circle, String, Line, Polygon, Rect
import math
from pathlib import Path
from reportlab.lib.utils import ImageReader
from reportlab.platypus import Image as RLImage
from PIL import Image as PILImage
import io

REF = Path(__file__).resolve().parent.parent / "docs" / "referencias"

F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", F + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Serif-Bold", F + "DejaVuSerif-Bold.ttf"))
pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans", boldItalic="Sans-Bold")

INK = colors.HexColor("#14183a")
MANA = colors.HexColor("#3978da")
MANA_D = colors.HexColor("#2a43a7")
GLOW = colors.HexColor("#a5dae5")
SOFT = colors.HexColor("#eef3ff")
GREY = colors.HexColor("#5d5a72")
LINE = colors.HexColor("#c9cfee")

OUT = sys.argv[1]
W, H = A4

s_body = ParagraphStyle("b", fontName="Sans", fontSize=9.6, leading=14.2, textColor=INK, spaceAfter=6)
s_h1 = ParagraphStyle("h1", fontName="Serif-Bold", fontSize=19, leading=24, textColor=MANA_D, spaceBefore=4, spaceAfter=10, keepWithNext=1)
s_h2 = ParagraphStyle("h2", fontName="Sans-Bold", fontSize=11.5, leading=15, textColor=INK, spaceBefore=10, spaceAfter=5, keepWithNext=1)
s_bul = ParagraphStyle("bul", parent=s_body, leftIndent=14, bulletIndent=3, spaceAfter=3)
s_cell = ParagraphStyle("c", fontName="Sans", fontSize=8.4, leading=11, textColor=INK)
s_cellh = ParagraphStyle("ch", fontName="Sans-Bold", fontSize=8.4, leading=11, textColor=colors.white)
s_quote = ParagraphStyle("q", parent=s_body, fontSize=11, leading=16, textColor=MANA_D, leftIndent=10,
                         borderPadding=(8, 10, 8, 10), backColor=SOFT, spaceBefore=6, spaceAfter=12)

story = []
P = lambda t: story.append(Paragraph(t, s_body))
H1 = lambda t: story.append(Paragraph(t, s_h1))
H2 = lambda t: story.append(Paragraph(t, s_h2))
def B(items):
    for i in items:
        story.append(Paragraph(i, s_bul, bulletText="•"))
def T(rows, widths, keep=True):
    data = [[Paragraph(c, s_cellh) for c in rows[0]]] + [[Paragraph(c, s_cell) for c in r] for r in rows[1:]]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), MANA_D),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, SOFT]),
        ("GRID", (0, 0), (-1, -1), 0.4, LINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(KeepTogether([t]) if keep else t)
    story.append(Spacer(1, 8))


def loop_diagram():
    d = Drawing(170 * mm, 92 * mm)
    cx, cy, r = 85 * mm, 47 * mm, 27 * mm
    steps = ["Lanzar hechizo", "Cae fragmento", "Entregar al Pilón", "Ganar maná", "Mejorar en el Santuario"]
    n = len(steps)
    pts = []
    for i in range(n):
        a = math.pi / 2 - i * 2 * math.pi / n
        pts.append((cx + r * 1.85 * math.cos(a), cy + r * 1.4 * math.sin(a)))
    for i in range(n):
        x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % n]
        # shorten
        dx, dy = x2 - x1, y2 - y1; L = math.hypot(dx, dy); ux, uy = dx / L, dy / L
        t = min(25 * mm / max(abs(ux), 1e-6), 5.5 * mm / max(abs(uy), 1e-6)) + 2
        sx, sy = x1 + ux * t, y1 + uy * t
        ex, ey = x2 - ux * t, y2 - uy * t
        d.add(Line(sx, sy, ex, ey, strokeColor=MANA, strokeWidth=1.4))
        px, py = -uy, ux
        d.add(Polygon([ex, ey, ex - ux * 7 + px * 3.5, ey - uy * 7 + py * 3.5,
                       ex - ux * 7 - px * 3.5, ey - uy * 7 - py * 3.5], fillColor=MANA, strokeColor=MANA))
    for i, (x, y) in enumerate(pts):
        d.add(Rect(x - 25 * mm, y - 5.5 * mm, 50 * mm, 11 * mm, rx=5 * mm, ry=5 * mm,
                   fillColor=SOFT if i else MANA_D, strokeColor=MANA, strokeWidth=1))
        d.add(String(x, y - 1.3 * mm, steps[i], fontName="Sans-Bold", fontSize=8.5,
                     fillColor=colors.white if i == 0 else INK, textAnchor="middle"))
    d.add(String(cx, cy - 1 * mm, "hechizos más fuertes", fontName="Sans", fontSize=8, fillColor=GREY, textAnchor="middle"))
    return d


def cover(c, doc):
    c.saveState()
    c.setFillColor(INK); c.rect(0, 0, W, H, fill=1, stroke=0)
    img = ImageReader(str(REF / "estilo_referencia.png"))
    iw, ih = img.getSize()
    dh = W * ih / iw
    c.drawImage(img, 0, H - dh, W, dh)
    c.setFillColor(colors.Color(0.06, 0.07, 0.22, alpha=0.82)); c.rect(0, 0, W, 92 * mm, fill=1, stroke=0)
    c.setFillColor(colors.HexColor("#c79bff")); c.rect(0, 92 * mm, W, 1.2 * mm, fill=1, stroke=0)
    c.setFillColor(colors.white); c.setFont("Serif-Bold", 34)
    c.drawCentredString(W / 2, 58 * mm, "Can you destroy it?")
    c.setFillColor(GLOW); c.setFont("Sans", 12)
    c.drawCentredString(W / 2, 47 * mm, "Game Design Document  \u00b7  v0.2")
    c.setFillColor(colors.HexColor("#c9c6e4")); c.setFont("Sans", 9.5)
    c.drawCentredString(W / 2, 39 * mm, "Incremental en primera persona  \u00b7  Pixel art  \u00b7  Godot 4.7  \u00b7  Noviembre 2026")
    c.setFont("Sans", 7); c.setFillColor(colors.HexColor("#8f8cb0"))
    c.drawCentredString(W / 2, 14 * mm, "Imagen de portada: referencia de estilo, no arte final.")
    c.restoreState()


def page(c, doc):
    c.saveState()
    c.setStrokeColor(LINE); c.setLineWidth(0.5); c.line(18 * mm, H - 14 * mm, W - 18 * mm, H - 14 * mm)
    c.setFont("Sans", 7.5); c.setFillColor(GREY)
    c.drawString(18 * mm, H - 12 * mm, "Can you destroy it?  —  GDD v0.2")
    c.drawRightString(W - 18 * mm, 11 * mm, str(doc.page))
    c.restoreState()


doc = BaseDocTemplate(OUT, pagesize=A4, title="Can you destroy it? - GDD", author="Can you destroy it? team",
                      leftMargin=18 * mm, rightMargin=18 * mm, topMargin=20 * mm, bottomMargin=18 * mm)
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")
doc.addPageTemplates([PageTemplate("cover", [frame], onPage=cover), PageTemplate("body", [frame], onPage=page)])

story.append(NextPageTemplate("body")); story.append(PageBreak())

# 1
H1("1. Visión general")
story.append(Paragraph("Al pie del castillo, en medio del valle, ha brotado un cristal de maná gigantesco. "
                       "Tú eres un aprendiz con una chispita patética. <b>¿Puedes destruirlo?</b>", s_quote))
T([["Campo", "Definición"],
   ["Género", "Incremental / clicker activo en primera persona, con progresión finita (tiene final)."],
   ["Duración objetivo", "2 a 3 horas para completar. Un final claro y memorable, no un idle infinito."],
   ["Plataforma", "PC (Steam). Ratón y teclado. Steam Deck como objetivo verificado."],
   ["Motor", "Godot 4.7 (GDScript tipado)."],
   ["Estilo visual", "Pixel art vibrante: cielo azul intenso, bosques verdes, magia violeta y rosa (ver sección 11)."],
   ["Fantasía central", "Pasar de aprendiz torpe a archimago que desintegra una montaña de cristal combinando elementos."],
   ["Objetivo del jugador", "Romper el Cristal Madre por completo y llenar el Pilón de Maná al 100 %."],
   ["Referencias", "<b>One Million Coins</b> (bóveda finita, empiezas sin nada, ~2 h, árbol con muchos nodos en varias ramas). "
                   "<b>Aerolicious</b> (destruir un bloque enorme pieza a pieza, relajante y satisfactorio)."]],
  [38, 136])

H2("1.1 Pitch en una frase")
P("Un incremental en primera persona donde golpeas un cristal colosal con hechizos cada vez más locos, "
  "recoges los pedazos que caen, los entregas a un pilón que se va llenando de maná y usas ese poder "
  "para convertirte en el mago que finalmente lo hace añicos.")

H2("1.2 Qué tomamos de cada referencia")
T([["De One Million Coins", "De Aerolicious", "Lo nuestro"],
   ["Recurso finito y visible: sabes exactamente cuánto queda.",
    "Un objeto enorme hecho de miles de piezas que se van desprendiendo.",
    "El cristal es a la vez el enemigo, la mina y la meta."],
   ["Empiezas con las manos vacías; el primer minuto es lento a propósito.",
    "Ritmo relajante, feedback físico satisfactorio en cada pieza.",
    "Combinación de hechizos como fuente de descubrimiento."],
   ["Muchos nodos de mejora en varias ramas; sesión corta y cerrada.",
    "Progreso visible en el propio objeto (se va vaciando).",
    "Un lugar físico (el Santuario) donde mejoras y que crece contigo."],
   ["<i>Crítica recibida: final poco memorable.</i>", "", "<b>Final espectacular diseñado desde el día 1</b> (ver sección 9)."]],
  [58, 58, 58])

H2("1.3 Supuestos de este documento")
P("Interpretamos la idea así: el <b>Cristal Madre</b> es lo que golpeas y rompes; el <b>Pilón de Maná</b> es el "
  "contenedor gigante que rellenas entregando los fragmentos. Llenar el pilón y destruir el cristal son la misma "
  "barra de progreso vista desde dos lados. Si la intención era otra, ajustamos el documento.")

# 2
story.append(PageBreak())
H1("2. Bucle principal")
story.append(loop_diagram())
story.append(Spacer(1, 6))
B(["<b>Lanzar</b>: apuntas al cristal y lanzas. Al principio una chispita lenta que hace un 'tic' ridículo.",
   "<b>Cae un fragmento</b>: un pedacito de cristal se desprende y cae rebotando al suelo, brillando.",
   "<b>Entregar</b>: lo recoges y lo llevas al Pilón. Al tirarlo dentro, el nivel líquido de maná sube.",
   "<b>Ganar maná</b>: cada fragmento entregado suma al progreso permanente del Pilón <i>y</i> te da maná para gastar.",
   "<b>Mejorar</b>: subes al Santuario y compras mejoras. Vuelves, lanzas algo mejor, y el ciclo acelera."])
H2("2.1 Dos números, una sola meta")
T([["Recurso", "Qué es", "¿Se gasta?"],
   ["Esencia del Cristal", "Lo que le queda al Cristal Madre: 1.000.000 de puntos al empezar.", "Baja con cada golpe. No vuelve."],
   ["Pilón de Maná (%)", "Total entregado. Es la barra de victoria.", "Nunca baja."],
   ["Maná", "Moneda para comprar mejoras. Cada fragmento entregado da maná igual a su valor.", "Sí, en el Santuario."]],
  [40, 92, 42])
P("Así el jugador nunca siente que comprar una mejora le 'quita' progreso: el pilón sólo sube.")

H2("2.2 La entrega como parte del juego")
P("Entregar no es un trámite: es la primera cosa que el jugador quiere automatizar, y por eso es la primera gran "
  "recompensa. La progresión de la entrega es un arco propio:")
T([["Etapa", "Cómo se entrega", "Sensación"],
   ["Manos", "Recoges 1 fragmento, caminas 10 m, lo tiras al Pilón.", "Humilde. 'Esto es ridículo.'"],
   ["Bolsa de aprendiz", "Llevas 5, luego 20, luego 100 fragmentos.", "Primeros viajes eficientes."],
   ["Telequinesis", "Los fragmentos cercanos vuelan hacia ti; luego, directo al Pilón.", "Ya eres un mago de verdad."],
   ["Familiares", "Pequeños espíritus recogen y entregan solos.", "Tienes sirvientes."],
   ["Vórtice", "El Pilón aspira todo lo que cae en el valle.", "Lluvia de cristal fluyendo en espiral."]],
  [34, 86, 54])

# 3
H1("3. Sentirse un mago")
P("Todo el diseño se mide contra una pregunta: <b>¿esto me hace sentir más mago?</b> Reglas que se derivan:")
B(["<b>Las manos son el arma.</b> Vista en primera persona con ambas manos visibles. Cada mano tiene un elemento "
   "asignado y brilla con su color. No hay pistolas disfrazadas.",
   "<b>El primer hechizo tiene que dar vergüenza.</b> La chispita sale con un 'pff', vuela lenta y hace caer un trocito "
   "del tamaño de una uña. El contraste con el final es el corazón del juego.",
   "<b>Cada mejora se ve y se oye.</b> Más daño = proyectil más grande, más brillante, más grave. Nunca un +5 % invisible.",
   "<b>Descubrir es magia.</b> Las combinaciones de elementos no se compran: se descubren probando y quedan anotadas en el Grimorio.",
   "<b>El mundo reacciona.</b> El valle cambia a medida que el Pilón se llena: auroras de maná en el cielo, faroles que se encienden en la aldea, estandartes nuevos en el castillo. El cristal cambia de color al exponer capas interiores.",
   "<b>Gestos, no menús.</b> Cargar un hechizo = mantener pulsado, las manos tiemblan y crepitan. Soltar = liberación con retroceso de cámara."])

# 4
H1("4. Espacio físico")
H2("4.1 El Valle del Cristal")
P("Un valle verde al pie de una montaña coronada por un castillo de torres azules, con una aldea de tejados rojos y bosques de "
  "pinos alrededor. En un claro del valle ha brotado el <b>Cristal Madre</b>: un racimo de cristales de hielo azul, con una "
  "punta principal unas 30 veces más alta que el jugador y un corazón violeta oscuro en la base. Los fragmentos caen sobre "
  "la hierba. La escala es el primer mensaje: <i>esto es imposible</i>.")
H2("4.2 El Pilón de Maná")
P("Una columna gigante de vidrio y bronce dorado en el borde del claro, vacía al principio. Por dentro se ve el maná líquido "
  "subiendo. Marcas talladas al 10 %, 25 %, 50 %, 75 % y 100 % abren nuevas secciones del Santuario y nuevos elementos. "
  "Cuanto más lleno, más brilla y más zumba; de noche ilumina todo el valle.")
H2("4.3 El Santuario (lugar físico de mejora)")
P("La torre del mago, en el linde del bosque, con vista al cristal. Empieza siendo una cabaña con una "
  "vela y un atril vacío, y <b>crece físicamente</b> con cada compra: aparecen estanterías, vitrales, velas, "
  "instrumentos. El jugador ve su progreso al mirar alrededor.")
T([["Estación", "Función", "Se desbloquea"],
   ["Grimorio de Constelaciones", "Árbol de mejoras principal (7 ramas). Se abre como un libro y las mejoras son estrellas.", "Desde el inicio"],
   ["Mesa de Runas", "Inscribir runas que modifican hechizos (multidisparo, rebote, perforación, eco).", "Pilón 10 %"],
   ["Altar de Elementos", "Desbloquear y mejorar elementos nuevos; asignarlos a cada mano.", "Pilón 10 %"],
   ["Jaula de Familiares", "Invocar y mejorar familiares que recogen, entregan o lanzan.", "Pilón 25 %"],
   ["Vitrina del Báculo", "Mejoras del báculo / foco: cambian la forma de canalizar.", "Pilón 50 %"],
   ["Espejo del Archimago", "Estadísticas, tiempo jugado, combinaciones descubiertas.", "Desde el inicio"]],
  [42, 98, 34])

# 5
H1("5. Sistema de hechizos")
H2("5.1 Elementos")
T([["Elemento", "Personalidad", "Rol"],
   ["Chispa (fuego)", "El inicial. Rápido, débil, constante.", "Daño base."],
   ["Escarcha", "Lento, congela facetas.", "Las facetas congeladas reciben daño extra (debilitar)."],
   ["Rayo", "Instantáneo, salta entre facetas.", "Daño en cadena, buen contra áreas grandes."],
   ["Tierra", "Pesado, cargado.", "Golpes enormes y lentos; arranca fragmentos grandes."],
   ["Arcano", "Puro, extraño.", "Amplifica y duplica: eco, multicast, resonancia."]],
  [32, 62, 80])
H2("5.2 Combinación")
P("Cada mano lleva un elemento. <b>Clic izquierdo</b> lanza la mano izquierda, <b>clic derecho</b> la derecha y "
  "<b>ambos a la vez</b> fusionan los dos en un hechizo combinado. Más adelante se desbloquea un tercer 'espacio' "
  "(el báculo) para combinaciones triples. Las combinaciones nuevas se descubren al probarlas y se registran en el Grimorio "
  "con una animación de página que se escribe sola.")
T([["Combinación", "Hechizo", "Efecto"],
   ["Chispa + Chispa", "Bola de Fuego", "Explosión en área; el primer hechizo 'de verdad'."],
   ["Chispa + Escarcha", "Choque Térmico", "Agrieta la faceta: el siguiente golpe hace x3."],
   ["Chispa + Rayo", "Haz de Plasma", "Rayo continuo mientras mantienes pulsado."],
   ["Escarcha + Rayo", "Lanza Cargada", "Perfora varias capas; fragmentos de mayor valor."],
   ["Tierra + Chispa", "Meteoro", "Cae del cielo tras una carga; enorme área."],
   ["Tierra + Escarcha", "Lluvia de Estalactitas", "Muchos impactos pequeños durante unos segundos."],
   ["Tierra + Rayo", "Magnetismo", "Utilidad: arrastra fragmentos al Pilón."],
   ["Arcano + X", "Eco de X", "Repite el hechizo X una o más veces."],
   ["Arcano + Tierra", "Gravedad", "Atrae todos los fragmentos de la sala."],
   ["Chispa + Escarcha + Rayo", "Tormenta Elemental", "Triple. Tormenta permanente sobre el cristal."],
   ["Los cinco", "Gran Convergencia", "Hechizo final. Sólo funciona contra el Núcleo (ver 9)."]],
  [40, 38, 96])
H2("5.3 Runas (modificadores)")
B(["<b>Multidisparo</b>: +1 proyectil por nivel.", "<b>Rebote</b>: el proyectil rebota entre facetas.",
   "<b>Perforación</b>: atraviesa capas.", "<b>Sobrecarga</b>: mantener para cargar, más daño y fragmentos más grandes.",
   "<b>Eco</b>: probabilidad de relanzar gratis.", "<b>Cosecha</b>: fragmentos con más valor a cambio de menos daño."])

# 6
story.append(PageBreak())
H1("6. El Cristal Madre")
P("Inspirado en Aerolicious: el cristal está hecho de miles de <b>facetas</b> (≈ 4.000 piezas físicas) que se desprenden "
  "de verdad. El jugador ve cómo la silueta cambia y se va vaciando. Tiene <b>1.000.000 de Esencia</b> repartida en capas, "
  "y cada capa cambia el color, el sonido y lo que suelta.")
T([["Capa", "Esencia", "Aspecto", "Particularidad"],
   ["Corteza", "0 a 10 %", "Hielo azul pálido, escarchado", "Fácil. Enseña el bucle. Sólo fragmentos comunes."],
   ["Manto Geódico", "10 a 45 %", "Azul translúcido con geodas", "Geodas: bolsas que sueltan muchos fragmentos de golpe."],
   ["Venas Resonantes", "45 a 80 %", "Venas de colores por elemento", "Cada vena es débil a un elemento. Premia combinar."],
   ["Corazón Cristalino", "80 a 99 %", "Blanco azulado, casi luminoso", "Facetas duras que exigen hechizos combinados."],
   ["Núcleo", "último 1 %", "Corazón violeta oscuro de la base", "Inmune a todo salvo la Gran Convergencia."]],
  [32, 22, 42, 78])
H2("6.1 Tipos de fragmento")
T([["Fragmento", "Valor", "Origen"],
   ["Astilla", "1", "Golpe normal."],
   ["Fragmento", "10", "Golpe fuerte o carga."],
   ["Geoda", "100+", "Romper una geoda."],
   ["Fragmento Resonante", "x5 + bonus", "Golpear una vena con su elemento débil."],
   ["Lágrima del Núcleo", "especial", "Sólo en el Corazón; desbloquea nodos finales."]],
  [48, 30, 96])

# 7
H1("7. Árbol de mejoras (Grimorio)")
P("≈ 200 nodos en 7 constelaciones. Coste exponencial suave dentro de cada rama, con nodos 'hito' grandes que cambian "
  "la forma de jugar (no sólo números).")
T([["Rama", "Qué mejora", "Nodos hito de ejemplo"],
   ["Potencia", "Daño por hechizo.", "Chispa -> Llama -> Infierno (cambia el modelo del proyectil)."],
   ["Canalización", "Cadencia, carga, maná por segundo al mantener.", "Lanzamiento continuo al mantener pulsado."],
   ["Elementos", "Desbloqueo y fuerza de cada elemento.", "Tercer espacio de combinación (báculo)."],
   ["Telequinesis", "Recogida y entrega.", "Atraer fragmentos -> envío directo al Pilón -> Vórtice."],
   ["Familiares", "Automatización.", "Primer familiar; familiares que lanzan hechizos."],
   ["Pilón", "Valor de cada fragmento entregado.", "Resonancia: el Pilón dispara rayos al cristal."],
   ["Resonancia", "Críticos, fragmentos raros, geodas.", "Críticos que rompen facetas enteras."]],
  [30, 60, 84])

# 8
story.append(PageBreak())
H1("8. Ritmo y progresión")
T([["Tiempo", "Rango", "Qué pasa", "Desbloqueo clave"],
   ["0 a 5 min", "Aprendiz", "Chispita, recoges a mano, primeras 3 mejoras baratas.", "Bolsa de aprendiz."],
   ["5 a 20 min", "Iniciado", "Daño y cadencia escalan; primera telequinesis.", "Escarcha + primera combinación."],
   ["20 a 50 min", "Hechicero", "Mesa de Runas, Rayo, Bola de Fuego en área.", "Primer familiar."],
   ["50 a 90 min", "Magus", "Tierra, Meteoro, venas resonantes.", "Báculo: combinaciones triples."],
   ["90 a 140 min", "Archimago", "Arcano, Eco, Tormenta Elemental; automatización casi total.", "Lágrimas del Núcleo."],
   ["Final", "Leyenda", "El Núcleo queda expuesto.", "Gran Convergencia."]],
  [24, 24, 80, 46])
H2("8.1 Números de arranque (a balancear)")
T([["Parámetro", "Valor inicial", "Notas"],
   ["Daño de la chispa", "1 Esencia", "Cada golpe suelta 1 astilla."],
   ["Cadencia", "1 lanzamiento cada 1,5 s", "Lento a propósito."],
   ["Distancia cristal -> Pilón", "≈ 10 m", "Unos 4 s de caminata."],
   ["Capacidad de manos", "1 fragmento", "La primera mejora (5 maná) sube a 5."],
   ["Primera mejora", "5 maná", "Debe llegar en menos de 30 s."],
   ["Coste por nivel", "base x 1,15 a 1,25", "Curva por rama; hitos con salto mayor."]],
  [48, 44, 82])
P("Regla de diseño: <b>siempre debe haber algo comprable en menos de 60 segundos</b> durante la primera hora, "
  "y nunca más de 3 minutos sin una mejora en todo el juego.")

# 9
H1("9. El final")
P("La crítica más repetida a One Million Coins es un cierre sin momento final. Aquí el final es el clímax de toda la fantasía:")
B(["Al llegar al 99 % el cristal se resquebraja y deja expuesto el <b>Núcleo</b>, una esfera de luz que no recibe daño.",
   "El Grimorio revela la última página: la <b>Gran Convergencia</b>. Hay que asignar los cinco elementos y cargar con ambas manos.",
   "La carga dura varios segundos: el valle tiembla, la música se apaga, las manos se llenan de luz.",
   "Al soltar, el Núcleo estalla, el Pilón llega al 100 % y libera una columna de maná que atraviesa las nubes; el cielo entero se llena de auroras y la aldea celebra.",
   "Pantalla final con el tiempo total, combinaciones descubiertas y la pregunta respondida: <i>'Yes, you could.'</i>"])

# 10
story.append(PageBreak())
H1("10. Feedback y sensación")
T([["Momento", "Visual", "Audio"],
   ["Lanzar", "Retroceso de manos, destello, estela.", "Crepitar según elemento; más grave al subir de nivel."],
   ["Impacto", "Grieta en la faceta, partículas, leve sacudida.", "'Tink' cristalino, tono según capa."],
   ["Fragmento cae", "Rebota con física, brilla hasta que lo recoges.", "Tintineo al rebotar."],
   ["Entrega", "Fragmentos vuelan al Pilón, el nivel sube visiblemente.", "Gota de maná + zumbido creciente del Pilón."],
   ["Mejora", "Aparece objeto nuevo en el Santuario.", "Acorde mágico, página que se escribe."],
   ["Combinación nueva", "Pausa breve, nombre del hechizo en grande.", "Fanfarria corta."]],
  [32, 72, 70])
H2("10.1 Controles")
T([["Acción", "Tecla"],
   ["Moverse / mirar", "WASD + ratón"],
   ["Lanzar mano izquierda / derecha", "Clic izquierdo / clic derecho"],
   ["Combinar", "Ambos clics a la vez (mantener para cargar)"],
   ["Cambiar elemento de una mano", "Q / E"],
   ["Recoger / entregar / interactuar", "F"],
   ["Abrir Grimorio rápido", "Tab"]],
  [80, 94])
H2("10.2 HUD")
B(["Arriba: barra del Pilón en %, con las marcas de desbloqueo.",
   "Abajo a la derecha: maná disponible y fragmentos en la bolsa.",
   "Sin números flotantes de daño al principio; se desbloquean como opción para quien los quiera.",
   "Las manos y los propios hechizos son el indicador principal de poder."])

# 11
story.append(PageBreak())
H1("11. Dirección de arte y audio")
def ref_img(name, width_mm, key_grey=False, scale=1):
    im = PILImage.open(REF / name).convert("RGBA")
    if key_grey:
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                if max(r, g, b) - min(r, g, b) < 12 and 165 < max(r, g, b) < 212:
                    px[x, y] = (0, 0, 0, 0)
    if scale > 1:
        im = im.resize((im.width * scale, im.height * scale), PILImage.NEAREST)
    buf = io.BytesIO(); im.save(buf, "PNG"); buf.seek(0)
    w = width_mm * mm
    return RLImage(buf, width=w, height=w * im.height / im.width)
cap = ParagraphStyle("cap", parent=s_cell, textColor=GREY, alignment=TA_CENTER)
imgs = Table([[ref_img("cristal_referencia.png", 48, key_grey=True, scale=4), ref_img("estilo_referencia.png", 62)],
              [Paragraph("Referencia del Cristal Madre (el personaje da la escala).", cap),
               Paragraph("Referencia de estilo y color: valle, castillo y manos del mago.", cap)]],
             colWidths=[80 * mm, 94 * mm])
imgs.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("VALIGN", (0, 0), (-1, 0), "BOTTOM")]))
story.append(imgs); story.append(Spacer(1, 8))
H2("11.1 Estilo")
B(["<b>Pixel art</b> detallado y luminoso, de colores saturados y alegres: nada de grimdark. Contornos limpios, sombreado por bandas "
   "(sin degradados suaves) y dithering sólo para cielo y brillos.",
   "<b>Primera persona con manos</b> como en la referencia: mangas violeta oscuro con brazaletes dorados, manos de piel cálida, "
   "y la magia girando entre ellas en espirales rosa, violeta y cian con destellos blancos en forma de estrella.",
   "<b>El Cristal Madre</b>: racimo de cristales de hielo con una punta principal enorme y puntas secundarias alrededor. "
   "Caras claras arriba a la izquierda (luz del sol), sombras en azul profundo y un corazón violeta oscuro en la base que "
   "anticipa el Núcleo.",
   "<b>El mundo</b>: cielo azul con nubes blancas voluminosas, montañas azuladas, castillo de piedra clara con tejados azul cobalto "
   "y estandartes rojos, aldea de tejados rojos, pinos verdes. Profundidad por perspectiva atmosférica (lo lejano más azul y claro)."])
H2("11.2 Paleta base")
def palette():
    sw = [("#3978da", "Cielo"), ("#2a43a7", "Azul profundo"), ("#a5dae5", "Cristal luz"), ("#458fb8", "Cristal medio"),
          ("#284b86", "Cristal sombra"), ("#654fae", "Violeta manga"), ("#c79bff", "Magia violeta"), ("#ff7ad9", "Magia rosa"),
          ("#3f9a3c", "Bosque"), ("#c8423a", "Tejados"), ("#e6dddb", "Piedra castillo"), ("#d8a23a", "Oro brazalete")]
    d = Drawing(174 * mm, 31 * mm)
    w = 174 * mm / 6
    for i, (hx, name) in enumerate(sw):
        x, y = (i % 6) * w, (1 - i // 6) * 15 * mm
        d.add(Rect(x + 1, y + 5 * mm, w - 2, 9 * mm, fillColor=colors.HexColor(hx), strokeColor=None))
        d.add(String(x + 2, y + 2.4 * mm, name, fontName="Sans-Bold", fontSize=6.3, fillColor=INK))
        d.add(String(x + 2, y + 0.2 * mm, hx, fontName="Sans", fontSize=6, fillColor=GREY))
    return d
story.append(palette())
P("Paleta orientativa extraída de las referencias. La paleta definitiva se fija como recurso del proyecto (ver dev guidelines) "
  "y todo sprite nuevo debe usarla.")
H2("11.3 Enfoque técnico de render (propuesta)")
B(["Mundo en <b>3D</b> renderizado a <b>baja resolución interna</b> (640x360) y escalado por enteros con filtro nearest, para que "
   "todo se vea como pixel art nítido y permita caminar entre el Cristal, el Pilón y el Santuario como en One Million Coins.",
   "Texturas pintadas en pixel art con filtro nearest y densidad de texel constante; iluminación por bandas con shader toon, "
   "contorno por post-proceso y paleta limitada.",
   "Fondo (cielo, montañas, castillo, aldea lejana) como capas 2D pintadas con parallax: así el horizonte es idéntico a la referencia.",
   "Manos y hechizos en primer plano como sprites 2D animados a mano sobre una capa de canvas, a la misma escala de píxel.",
   "Alternativa si el prototipo M1 no convence: 2D puro en vista frontal fija, rotando entre tres pantallas (Cristal, Pilón, Santuario)."])
H2("11.4 Audio")
B(["<b>Música</b>: orquesta pequeña de fantasía (arpa, flauta, cuerdas, coro suave) con capas que se suman con cada rango de mago.",
   "<b>Ambiente</b>: viento en el valle, pájaros, campanas lejanas de la aldea; con el Pilón lleno, un zumbido de maná armónico.",
   "<b>Sonido del cristal</b>: el 'tink' es la firma del juego. Debe ser satisfactorio incluso la milésima vez."])

# 12
H1("12. Alcance e hitos")
T([["Hito", "Contenido", "Criterio de éxito"],
   ["M1 Prototipo", "Proyecto Godot 4.7 con pipeline pixel art, cristal con facetas, chispa, fragmentos, entrega manual, Pilón, 5 mejoras.", "Los primeros 5 minutos ya son divertidos."],
   ["M2 Vertical slice", "Santuario básico, 2 elementos, 1 combinación, telequinesis, capa Corteza completa.", "30 minutos sin bajones."],
   ["M3 Contenido", "5 elementos, todas las combinaciones, 7 ramas, familiares, todas las capas.", "Se puede terminar de principio a fin."],
   ["M4 Final y pulido", "Gran Convergencia, balance, audio, logros de Steam.", "Duración 2 a 3 h; el final emociona."]],
  [32, 88, 54])
H2("12.1 Preguntas abiertas")
B(["Confirmar el enfoque de render 11.3 (3D a baja resolución) frente a un 2D puro, tras el prototipo M1.",
   "Resolución interna final (640x360 propuesta) tras probarla en monitor 1440p y Steam Deck.",
   "¿Hay modo infinito o New Game+ tras el final?",
   "Precio y fecha objetivo en Steam."])

doc.build(story)
