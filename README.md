# konami-fpga

🇬🇧 English (below) · [🇪🇸 Español](#español)

FPGA recreations of **Konami** arcade boards, built on the **JTFRAME** framework (GPLv3). MiSTer target.

> ℹ️ Independent project — **NOT** an official jotego core. Built on his GPLv3 JTFRAME framework.

## Cores

### Asterix (Konami, 1993)
Run-and-gun beat-'em-up (GX068 board, Xexex-family lineage). Hardware: **MC68000** main CPU + **Z80**
sound CPU + **YM2151** (FM) + **K053260** (PCM sound) + Konami video customs — **K056832** (tilemap),
**K053244/K053245** (sprites, with shadow blending), **K053251** (priority mixer) — plus the board's
**palette blitter** (a bus-master ROM→palette copier, recreated as HLE; it is a **sound boot-gate**: the
68000 will not proceed past POST until the Z80+K053260 handshake completes).

**Status: playable on MiSTer** — boot, video (tilemap + sprites + shadows), the palette blitter, and
**audio (YM2151 FM + K053260 PCM, all 4 channels including the coin sound)** all run on hardware.

Unlike `moomesa`'s K054539, the **K053260** PCM chip already exists as a validated module in the common
jtframe tree (`jt053260`), so this core reuses it instead of writing a new one from scratch; the
core-specific work is the 68000 memory map, the palette blitter, and adapting the K056832/K053244/K053245
video pipeline (tile-bank, rowscroll, sprite priority/shadow rules) to this board's exact wiring.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: all game ROMs are loaded at
**runtime** from the `.mra`; the bitstream bakes no game data. Or build from source (`cores/asterix/`).
See [`BUILD.md`](BUILD.md).

### Martial Champion (Konami, 1993)
One-on-one fighting game (GX234 board, `mystwarr.cpp` family — the same MAME driver as Mystic
Warriors). Hardware: **MC68000** main CPU @ 16 MHz + **Z80** sound CPU + **K054539** (PCM sound) +
Konami video customs — **K056832** (tilemap, 5 bpp), **K055673** (sprites, `LAYOUT_GX`), **K055555**
(priority mixer), **K054338** (color / alpha blend), **K053252** (CRTC) — plus the board's
**K053990** and a 128-byte serial **EEPROM** for settings.

> ℹ️ Two things that set this board apart from the rest of the family. **It has no FM chip at all**:
> all of its audio is the single K054539, where its siblings pair a YM2151 with the PCM. And the
> **K053990 is not an encryption or challenge/response protection** — it is a memory-to-memory
> **blitter that masters the 68000 bus**, so the hard part is arbitrating work RAM and sprite RAM
> with the CPU, not the arithmetic.

Video is **384×224 at an 8 MHz pixel clock** (HTOTAL 512 / VTOTAL 264) — wider and faster than the
288×224 @ 6 MHz of its sibling Mystic Warriors.

**Status: runs and is playable on MiSTer** — boot, video (tilemap + sprites + alpha + priority), the
K053990 blitter and the board's own sound self-test all run on hardware. **One known open issue**:
with many sprites on screen a character can lose parts of its body for a frame, because the sprite
ROM fetch does not keep up with the line. This build improves it a great deal but does not close it.
The one-pixel horizontal framing error of the previous release **is** fixed.

The **K054539** PCM chip is the same from-scratch module as `moomesa`'s — there is no `jt539` in
jtframe, it is a private module — validated **bit-exact** against a MAME-derived C++ model, plus the
programmable NMI timer this board's Z80 needs.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: all game ROMs are loaded at
**runtime** from the `.mra`; the bitstream bakes only the K054539's **generated** Q16 volume/pan
tables (`voltab.hex` / `pantab.hex`, math, not game data) and a zero-init table — **no copyrighted
data**.

> ⚠️ Unlike the other cores here, **only the `.rbf` and the `.mra` are published** for Martial
> Champion: `cores/mtlchamp/` holds just `mra/`, with no `hdl/` or `cfg/`. This core **cannot be
> built from this repo**.

### Mystic Warriors: Wrath of the Ninjas (Konami, 1993)
Four-player ninja run-and-gun (GX128 board, `mystwarr.cpp` family — the same MAME driver as Martial
Champion, and the game the driver is named after). Hardware: **MC68000** main CPU @ 16 MHz + **Z80**
sound CPU @ 8 MHz + **two K054539** PCM chips + **K054321** (sound latch) + the Konami video customs
— **K056832** (tilemap, 5 bpp), **K055673** (sprites, `LAYOUT_GX`), **K055555** (priority mixer),
**K054338** (colour / shadow / alpha), **K053252** (CRTC) — and a serial **EEPROM** for settings.

> ℹ️ Like Martial Champion, this board carries **no FM chip**: all of its audio is PCM, here from
> **two** K054539s. Video is **288×224 at a 6 MHz pixel clock**, the narrower and slower half of the
> pair.

**Status: runs and is playable on MiSTer** — boot and self-test, video (tilemaps + sprites + zoom +
sprite shadow/highlight + priority), both PCM chips, 2-button controls and the board's Service Mode
all run on hardware. This release also closes the **speed** deficit that made the game run at 1.4×:
the 68000 was executing at 11.32 of its 16 MHz because the work RAM lived in SDRAM (it is static RAM
on the real board) and the program ROM was served one word per transaction; both are fixed, and it
now runs at **15.47 MHz, 96.7 % of nominal**.

**Two known open issues.** The `MASK ROM CHECK` of the board's own self-test reports **BAD on all
eleven mask ROMs** — the ROM read-back port of the three video customs is not implemented; that path
is used only by the self-test, never while playing. And on the **stage-3 boss** the two searchlight
beams show a dark band across them that the original PCB does not show.

The **K054539** PCM chip is a private module written from scratch (there is no `jt539` in jtframe),
shared with `moomesa` and `mtlchamp`, here instantiated twice.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: all game ROMs are loaded at
**runtime** from the `.mra`; the bitstream bakes only the K054539's **generated** Q16 volume/pan
tables (`voltab.hex` / `pantab.hex`, math, not game data) and a zero-init table — **no copyrighted
data**.

> ⚠️ As with Martial Champion, **only the `.rbf` and the `.mra` are published** for Mystic Warriors:
> `cores/mystwarr/` holds just `mra/`, with no `hdl/` or `cfg/`. This core **cannot be built from
> this repo**.

### Wild West C.O.W.-Boys of Moo Mesa (Konami, 1992)
Run-and-gun beat-'em-up (the cartoon cowboys). Hardware (GX151 / Xexex-family board): **MC68000** main
CPU + **Z80** sound CPU + **YM2151** (FM) + **K054539** (PCM sound) + Konami video customs — **K056832**
(tilemap), **K053246/K053247** (sprites), **K054338** (color / alpha blend), **K053251** (priority) —
plus the board's **protection blitter** (recreated as HLE).

**Status: playable on MiSTer** — boot, video (tilemap + sprites + alpha), the protection blitter, and
**audio (YM2151 FM + K054539 PCM)** all run on hardware.

Two notable parts are **written from scratch**: the **`k054539`** PCM chip (there is no `jt539` in
jtframe — it is a private module) and the **`k056832`** tilemap. The K054539 is validated **bit-exact**
against a MAME-derived C++ model.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: all game ROMs are loaded at
**runtime** from the `.mra`; the bitstream bakes only the K054539's **generated** Q16 volume/pan tables
(`voltab.hex` / `pantab.hex`, math, not game data) and a zero-init table — **no copyrighted data**.
Or build from source (`cores/moomesa/`). See [`BUILD.md`](BUILD.md).

> ℹ️ Naming: the PCM chip keeps its real silicon name (`k054539`, no `jt`); the GAMETOP is
> `jtmoomesa_game` (memgen imposes the `jt`).

### Sunset Riders (Konami, 1991)
Western run-and-gun beat-'em-up (GX063 board, `tmnt2.cpp` family). Hardware: **MC68000** main CPU +
**Z80** sound CPU + **YM2151** (FM) + **K053260** (PCM sound) + Konami video customs — **K052109**
(tilemap), **K053244/K053245** (sprites), **K053251** (priority mixer) — plus the board's
**protection** at `0x1C0800` (recreated as HLE: it sorts the 128 sprites by logical priority and writes
the resulting hardware priority back into sprite RAM) and a 128-byte serial **EEPROM** for settings.

**Status: playable on MiSTer** — boot, video (tilemap + sprites + priority/shadow), the protection and
**audio (YM2151 FM + K053260 PCM)** all run on hardware. Both sets ship as `.mra`: the 4-player **EAC**
and the 2-player **EBD**.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: all game ROMs are loaded at
**runtime** from the `.mra`; the bitstream bakes no game data. Or build from source (`cores/ssriders/`).
See [`BUILD.md`](BUILD.md).

## Build

This repo contains **only the core code** (`cores/<core>/`, e.g. `cores/asterix/`, `cores/moomesa/`,
`cores/ssriders/`).
The framework and third-party cores (jtframe, jt51) are **not included** — jtframe provides them. Quick
version:

1. Clone [jtcores](https://github.com/jotego/jtcores) (brings jtframe + modules).
2. Copy this repo's `cores/<core>/` into your jtcores checkout.
3. Build: `jtcore <core> -mister -c` (e.g. `jtcore asterix -mister -c`).

📋 **Step-by-step in [`BUILD.md`](BUILD.md).**

Core layout:
```
cores/<core>/
├── hdl/   Core Verilog
├── cfg/   macros.def, mem.yaml, files.yaml, mame2mra.toml
└── mra/   .mra definition (how to assemble the ROMs)
```

> ⚠️ **`mtlchamp` and `mystwarr` are the exceptions**: only their `.rbf` and `.mra` are published,
> so `cores/mtlchamp/` and `cores/mystwarr/` hold `mra/` alone — no `hdl/`, no `cfg/` — and they
> cannot be built from this repo. Everything above applies to `asterix`, `moomesa` and `ssriders`.

## ROMs

**Not included** (copyrighted material). Everyone provides the original ROMs of their own board for each
game. The `.mra` describes how to assemble them; every ROM (program, sound, PCM samples, tiles,
sprites) is loaded at runtime, so the `.rbf` carries no copyrighted data.

## Credits

- **JTFRAME**, **jt51** — the GPLv3 frameworks this core is built on
- **MAME** — hardware reference (`moo.cpp` driver, `k054539.cpp` sound chip; `konami/asterix.cpp` and
  `konami/tmnt2.cpp` drivers, `k052109.cpp` / `k053244_k053245.cpp` / `k053251.cpp` video chips)
- **Furrtek** — silicon reverse-engineering of the K054539

## Acknowledgements

- To **Sorgelig** and the whole **MiSTer FPGA** project and community.
- To the **MAME community**, for the preservation and reverse-engineering work without which this core
  would not be possible.
- And to **Anthropic**, for **Claude**.

## License

**GPLv3** (see [`LICENSE`](LICENSE)) — required by the JTFRAME / jt51 dependencies; their copyright
notices are preserved in the sources.

---

## Español

🇪🇸 Español · [🇬🇧 English ↑](#konami-fpga)

Recreaciones en FPGA de placas arcade de **Konami**, construidas sobre el framework **JTFRAME** (GPLv3).
Objetivo MiSTer.

> ℹ️ Proyecto independiente — **NO** es un core oficial de jotego. Construido sobre su framework JTFRAME
> (GPLv3).

## Cores

### Asterix (Konami, 1993)
Run-and-gun / yo-contra-el-barrio (placa GX068, familia Xexex). Hardware: CPU principal **MC68000** + CPU
de sonido **Z80** + **YM2151** (FM) + **K053260** (sonido PCM) + customs de vídeo de Konami — **K056832**
(tilemap), **K053244/K053245** (sprites, con mezcla de sombra), **K053251** (mezclador de prioridad) —
más el **blitter de paleta** de la placa (un copiador ROM→paleta por bus-master, recreado por HLE; es un
**boot-gate de sonido**: el 68000 no pasa del POST hasta que el handshake Z80+K053260 se completa).

**Estado: jugable en MiSTer** — arranque, vídeo (tilemap + sprites + sombras), el blitter de paleta y el
**audio (FM del YM2151 + PCM del K053260, los 4 canales, incluida la moneda)** funcionan en hardware.

A diferencia del K054539 de `moomesa`, el chip PCM **K053260** ya existe como módulo validado en el árbol
común de jtframe (`jt053260`), así que este core lo reutiliza en vez de escribir uno desde cero; el
trabajo propio del core es el mapa de memoria del 68000, el blitter de paleta, y adaptar el pipeline de
vídeo K056832/K053244/K053245 (banco de tiles, rowscroll, reglas de prioridad/sombra de sprites) al
cableado exacto de esta placa.

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: todas las ROMs del juego se
cargan en **runtime** desde el `.mra`; el bitstream no hornea ningún dato del juego. O compila desde
fuente (`cores/asterix/`). Ver [`BUILD.md`](BUILD.md).

### Martial Champion (Konami, 1993)
Juego de lucha uno contra uno (placa GX234, familia `mystwarr.cpp` — el mismo driver de MAME que
Mystic Warriors). Hardware: CPU principal **MC68000** @ 16 MHz + CPU de sonido **Z80** + **K054539**
(sonido PCM) + customs de vídeo de Konami — **K056832** (tilemap, 5 bpp), **K055673** (sprites,
`LAYOUT_GX`), **K055555** (mezclador de prioridad), **K054338** (color / mezcla alpha), **K053252**
(CRTC) — más el **K053990** de la placa y una **EEPROM** en serie de 128 bytes para los ajustes.

> ℹ️ Dos cosas separan a esta placa del resto de la familia. **No lleva chip de FM**: todo su audio
> es el único K054539, mientras que sus hermanas acompañan el PCM con un YM2151. Y el **K053990 no
> es un cifrado ni una protección de desafío/respuesta** — es un **blitter memoria a memoria que
> hace de MAESTRO DEL BUS** del 68000, así que la dificultad está en arbitrar con la CPU el acceso
> a la work RAM y a la sprite RAM, no en la aritmética.

El vídeo es **384×224 con reloj de píxel de 8 MHz** (HTOTAL 512 / VTOTAL 264): más ancho y más
rápido que los 288×224 @ 6 MHz de su hermana Mystic Warriors.

**Estado: arranca y es jugable en MiSTer** — el arranque, el vídeo (tilemap + sprites + alpha +
prioridad), el blitter K053990 y el autotest de sonido de la propia placa funcionan en hardware.
**Queda un defecto conocido**: con muchos sprites en pantalla un personaje puede perder partes del
cuerpo durante un cuadro, porque el fetch de la ROM de sprites no llega a tiempo dentro de la línea.
Esta versión lo mejora mucho pero no lo cierra. El descuadre horizontal de un píxel de la versión
anterior **sí** está arreglado.

El chip PCM **K054539** es el mismo módulo escrito desde cero que el de `moomesa` — no existe
`jt539` en jtframe, es un módulo privado — validado **bit-exacto** contra un modelo C++ derivado de
MAME, más el temporizador NMI programable que necesita el Z80 de esta placa.

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: todas las ROMs del juego
se cargan en **runtime** desde el `.mra`; el bitstream solo hornea las tablas Q16 de volumen/pan del
K054539 (`voltab.hex` / `pantab.hex`, matemáticas, no datos del juego) y una tabla de ceros —
**ningún dato con copyright**.

> ⚠️ A diferencia de los otros cores de este repo, de Martial Champion **solo se publican el `.rbf`
> y el `.mra`**: `cores/mtlchamp/` contiene únicamente `mra/`, sin `hdl/` ni `cfg/`. Este core **no
> se puede compilar desde este repo**.

### Mystic Warriors: Wrath of the Ninjas (Konami, 1993)
Run-and-gun de ninjas para cuatro jugadores (placa GX128, familia `mystwarr.cpp` — el mismo driver de
MAME que Martial Champion, y el juego que le da nombre). Hardware: CPU principal **MC68000** @ 16 MHz
+ CPU de sonido **Z80** @ 8 MHz + **dos K054539** de PCM + **K054321** (latch de sonido) + los customs
de vídeo de Konami — **K056832** (tilemap, 5 bpp), **K055673** (sprites, `LAYOUT_GX`), **K055555**
(mezclador de prioridad), **K054338** (color / sombra / alpha), **K053252** (CRTC) — y una **EEPROM**
en serie para los ajustes.

> ℹ️ Igual que Martial Champion, esta placa **no lleva chip de FM**: todo su audio es PCM, aquí de
> **dos** K054539. El vídeo es de **288×224 con reloj de píxel de 6 MHz**, la mitad más estrecha y más
> lenta de la pareja.

**Estado: arranca y es jugable en MiSTer** — el arranque y el autotest, el vídeo (tilemaps + sprites +
zoom + sombra/realce de sprite + prioridad), los dos chips de PCM, los 2 botones y el Modo Servicio de
la propia placa funcionan en hardware. Esta versión cierra además el déficit de **velocidad** que hacía
que el juego fuese 1,4× más lento: el 68000 ejecutaba a 11,32 de sus 16 MHz porque la work RAM vivía en
la SDRAM (en la placa real es RAM estática) y la ROM de programa servía una palabra por transacción;
las dos cosas están arregladas y ahora va a **15,47 MHz, el 96,7 % de lo nominal**.

**Quedan dos defectos conocidos.** El `MASK ROM CHECK` del autotest de la placa da **BAD en las once
mask ROM**: el puerto de relectura de ROM de los tres customs de vídeo no está implementado, un camino
que sólo usa el autotest y nunca el juego. Y en el **jefe de la fase 3**, los dos haces de los focos
salen cortados por una franja oscura que la PCB original no tiene.

El chip PCM **K054539** es un módulo privado escrito desde cero (no existe `jt539` en jtframe),
compartido con `moomesa` y `mtlchamp`, aquí instanciado dos veces.

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: todas las ROMs del juego se
cargan en **runtime** desde el `.mra`; el bitstream solo hornea las tablas Q16 de volumen/pan del
K054539 (`voltab.hex` / `pantab.hex`, matemáticas, no datos del juego) y una tabla de ceros —
**ningún dato con copyright**.

> ⚠️ Igual que con Martial Champion, de Mystic Warriors **solo se publican el `.rbf` y el `.mra`**:
> `cores/mystwarr/` contiene únicamente `mra/`, sin `hdl/` ni `cfg/`. Este core **no se puede compilar
> desde este repo**.

### Wild West C.O.W.-Boys of Moo Mesa (Konami, 1992)
Run-and-gun / yo-contra-el-barrio (los vaqueros de dibujos). Hardware (placa GX151 / familia Xexex):
CPU principal **MC68000** + CPU de sonido **Z80** + **YM2151** (FM) + **K054539** (sonido PCM) + customs
de vídeo de Konami — **K056832** (tilemap), **K053246/K053247** (sprites), **K054338** (color / mezcla
alpha), **K053251** (prioridad) — más el **blitter de protección** de la placa (recreado por HLE).

**Estado: jugable en MiSTer** — arranque, vídeo (tilemap + sprites + alpha), el blitter de protección y
el **audio (FM del YM2151 + PCM del K054539)** funcionan en hardware.

Dos piezas están **escritas desde cero**: el chip PCM **`k054539`** (no existe `jt539` en jtframe — es
un módulo privado) y el tilemap **`k056832`**. El K054539 está validado **bit-exacto** contra un modelo
C++ derivado de MAME.

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: todas las ROMs del juego se
cargan en **runtime** desde el `.mra`; el bitstream solo hornea las tablas Q16 de volumen/pan del
K054539 (`voltab.hex` / `pantab.hex`, matemáticas, no datos del juego) y una tabla de ceros — **ningún
dato con copyright**. O compila desde fuente (`cores/moomesa/`). Ver [`BUILD.md`](BUILD.md).

> ℹ️ Nomenclatura: el chip PCM conserva su nombre real de silicio (`k054539`, sin `jt`); el GAMETOP es
> `jtmoomesa_game` (memgen impone el `jt`).

### Sunset Riders (Konami, 1991)
Run-and-gun / yo-contra-el-barrio del oeste (placa GX063, familia `tmnt2.cpp`). Hardware: CPU principal
**MC68000** + CPU de sonido **Z80** + **YM2151** (FM) + **K053260** (sonido PCM) + customs de vídeo de
Konami — **K052109** (tilemap), **K053244/K053245** (sprites), **K053251** (mezclador de prioridad) —
más la **protección** de la placa en `0x1C0800` (recreada por HLE: ordena los 128 sprites por su
prioridad lógica y escribe de vuelta en la spriteram la prioridad hardware resultante) y una **EEPROM**
en serie de 128 bytes para los ajustes.

**Estado: jugable en MiSTer** — arranque, vídeo (tilemap + sprites + prioridad/sombra), la protección y
el **audio (FM del YM2151 + PCM del K053260)** funcionan en hardware. Se entregan los dos sets como
`.mra`: el de 4 jugadores (**EAC**) y el de 2 (**EBD**).

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: todas las ROMs del juego se
cargan en **runtime** desde el `.mra`; el bitstream no hornea ningún dato del juego. O compila desde
fuente (`cores/ssriders/`). Ver [`BUILD.md`](BUILD.md).

## Construir

Este repo contiene **solo el código del core** (`cores/<core>/`, p.ej. `cores/asterix/`,
`cores/moomesa/`, `cores/ssriders/`). El framework y los cores de terceros (jtframe, jt51) **no se incluyen** — los aporta
jtframe. Versión rápida:

1. Clona [jtcores](https://github.com/jotego/jtcores) (trae jtframe + módulos).
2. Copia `cores/<core>/` de este repo dentro de tu checkout de jtcores.
3. Compila: `jtcore <core> -mister -c` (p.ej. `jtcore asterix -mister -c`).

📋 **Pasos detallados en [`BUILD.md`](BUILD.md).**

Estructura del core:
```
cores/<core>/
├── hdl/   Verilog del core
├── cfg/   macros.def, mem.yaml, files.yaml, mame2mra.toml
└── mra/   definición .mra (cómo ensamblar las ROMs)
```

> ⚠️ **`mtlchamp` y `mystwarr` son las excepciones**: de ellos solo se publican el `.rbf` y el
> `.mra`, así que `cores/mtlchamp/` y `cores/mystwarr/` contienen únicamente `mra/` — sin `hdl/`
> ni `cfg/` — y no se pueden compilar desde este repo. Todo lo de arriba vale para `asterix`,
> `moomesa` y `ssriders`.

## ROMs

**No se incluyen** (material con copyright). Cada cual aporta las ROMs originales de su propia placa para
cada juego. El `.mra` describe cómo ensamblarlas; cada ROM (programa, sonido, samples PCM, tiles, sprites) se
carga en runtime, así que el `.rbf` no lleva ningún dato con copyright.

## Créditos

- **JTFRAME**, **jt51** — los frameworks GPLv3 sobre los que se construye este core
- **MAME** — referencia de hardware (driver `moo.cpp`, chip de sonido `k054539.cpp`; drivers
  `konami/asterix.cpp` y `konami/tmnt2.cpp`, chips de vídeo `k052109.cpp` / `k053244_k053245.cpp` / `k053251.cpp`)
- **Furrtek** — ingeniería inversa del silicio del K054539

## Agradecimientos

- A **Sorgelig** y todo el proyecto y comunidad **MiSTer FPGA**.
- A la **comunidad MAME**, por el trabajo de preservación e ingeniería inversa sin el cual este core no
  sería posible.
- Y a **Anthropic**, por **Claude**.

## Licencia

**GPLv3** (ver [`LICENSE`](LICENSE)) — obligado por las dependencias JTFRAME / jt51; sus avisos de
copyright se conservan en las fuentes.

<!-- omf_release:dependencias:ssriders -->
## Dependencias externas de `ssriders`

Este repositorio contiene **solo el código de los cores**. Para compilar `ssriders`
hacen falta estas piezas, que se distribuyen desde su propio origen:

| Qué | De dónde | Dónde va |
|---|---|---|
| jtframe — framework de compilacion y modulos comunes: edge/counter, video (vtimer, jtframe_obj.yaml, linebuf), cpu (m68k, z80), sdram (dwnld), ram (dual_nvram16). ⚠ NO sirve el upstream tal cual: este core depende de parches nuestros al framework, sobre todo `jtframe_romrq_bcache.v` — ver «Parches al framework» mas abajo | [https://github.com/jotego/jtframe](https://github.com/jotego/jtframe) | `modules/jtframe` |
| fx68k — MC68000 (CPU principal) — entra via jtframe_m68k.yaml, pero es un repo aparte: fx68k.sv, fx68kAlu.sv, uaddrPla.sv | [https://github.com/jtfpga/fx68k](https://github.com/jtfpga/fx68k) | `modules/fx68k` |
| simson — jtcolmix_053251.v -- el K053251 (mezclador de prioridad). La cadena de sprites YA NO viene de aqui: se reescribio en hdl/ en la sesion 94 | [https://github.com/jotego/jtcores](https://github.com/jotego/jtcores) | `cores/simson` |
| jt51 — YM2151 (sonido) | [https://github.com/jotego/jt51](https://github.com/jotego/jt51) | `modules/jt51` |
| jt053260 — K053260 (PCM). ⚠ Con el upstream tal cual la voz sale distorsionada: hacen falta los 2 fixes de decode ADPCM — ver «Parches al framework» mas abajo | [https://github.com/jotego/jtcores](https://github.com/jotego/jtcores) | `modules/jt053260` |
| jteeprom — jt5911.sv -- EEPROM en serie de ajustes | [https://github.com/jotego/jteeprom](https://github.com/jotego/jteeprom) | `modules/jteeprom` |
<!-- /omf_release:dependencias:ssriders -->
### Parches al framework

Con las dependencias de arriba **tal cual vienen de su origen, este core no funciona**. Se apoya en
correcciones que hicimos sobre código de terceros y que no están (todavía) aguas arriba. Se dice aquí
porque no hay forma de deducirlo del código que sí se publica:

| Fichero | Qué pasa sin el parche |
|---|---|
| `modules/jtframe/hdl/sdram/jtframe_romrq_bcache.v` | La caché de 2 vías entrega datos partidos entre dos direcciones. La CPU nunca llega a ejecutar código real: el core no arranca. Es el parche grande (~137 líneas, en dos tandas). |
| `modules/jt053260/hdl/jt053260_channel.v` | El decodificador ADPCM arranca un byte antes de lo debido y toma los nibbles al revés. Las voces salen distorsionadas. |
| `modules/jtframe/hdl/video/jtframe_draw.v`, `.../ram/jtframe_obj_buffer.v`, `.../sdram/jtframe_ram_rq.v` | Ajustes menores del camino de sprites y de la petición de ROM. |

En total, **15 ficheros de `modules/jtframe` y 1 de `modules/jt053260`** de nuestro árbol difieren de
su origen. El resto de diferencias son sondas de simulación (`ifdef SIMULATION`) y no afectan a lo que
se sintetiza.

Aparte, el ajuste de geometría CRT (`modules/jtframe/hdl/video/rmonic79/crt_adjust.sv`) es obra de
**rmonic79**, integrada en `jtframe_mister.sv`; tampoco viene en el jtframe de origen.

Lo que **sí** viaja con este repositorio es la compensación de nivel del PCM: no toca el módulo
compartido, vive en nuestro `cores/ssriders/cfg/mem.yaml` (`pre` del canal PCM).
