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

Both the **`k052109`** tilemap and the **K053244/K053245 sprite chain** (`k053244.sv`,
`k053244_scan.sv`, `k053244_dma.v`, `k053244_mmr.v`) are **written for this core** against MAME's device
model rather than adapted from an existing implementation. The tilemap is driven through a single memory
window here, unlike the K056832 of the other two cores; only its scan-address generator and MMR bank are
ported from `jt052109`. In the sprite chain the priority-rejection rule is modelled as the *value* MAME
calls `z_rejection` instead of a per-game flag, the buffer DMA is an explicit three-phase state machine
whose clear pass is what implements MAME's `sortedlist[] = -1`, and the 256-entry zoom table is
**generated from its formula** — `min(511, round(2048/n))`, the reciprocal MAME writes as
`(0x400000 + z/2)/z` — instead of being tabulated. Everything targets the K053244/K053245 only: there is
no unexercised K053246/K053247 path. The video path is checked scene by scene against a Python golden
model derived from MAME.

> ⚠️ Known issue: `H-Size` in MiSTer's CRT Adjust menu splits the picture into three bands. Leave it at 0.

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

Core layout (same for every core in this repo):
```
cores/<core>/
├── hdl/   Core Verilog
├── cfg/   macros.def, mem.yaml, files.yaml, mame2mra.toml
└── mra/   .mra definition (how to assemble the ROMs)
```

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

Tanto el tilemap **`k052109`** como la **cadena de sprites K053244/K053245** (`k053244.sv`,
`k053244_scan.sv`, `k053244_dma.v`, `k053244_mmr.v`) están **escritos para este core** contra el modelo
de dispositivo de MAME, no adaptados de una implementación existente. El tilemap se maneja aquí por una
ventana de memoria única, a diferencia del K056832 de los otros dos cores; de `jt052109` solo se porta
su generador de direcciones de scan y el banco MMR. En la cadena de sprites, la regla de rechazo por
prioridad se modela como el *valor* que MAME llama `z_rejection` en vez de como una bandera por juego,
el DMA del buffer es una máquina de estados explícita cuya fase de borrado es lo que implementa el
`sortedlist[] = -1` de MAME, y la tabla de zoom de 256 entradas se **genera desde su fórmula**
—`min(511, round(2048/n))`, el recíproco que MAME escribe como `(0x400000 + z/2)/z`— en vez de estar
tabulada. Todo apunta al K053244/K053245 y solo a él: no hay camino K053246/K053247 sin ejercitar. El
camino de vídeo se comprueba escena a escena contra un modelo golden en Python derivado de MAME.

> ⚠️ Pega conocida: el `H-Size` del menú CRT Adjust de MiSTer parte la imagen en tres bandas. Déjalo a 0.

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

Estructura del core (igual para todos los cores de este repo):
```
cores/<core>/
├── hdl/   Verilog del core
├── cfg/   macros.def, mem.yaml, files.yaml, mame2mra.toml
└── mra/   definición .mra (cómo ensamblar las ROMs)
```

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
| jtframe — framework de compilacion y modulos comunes: jtframe_toggle/edge/counter, video (vtimer, jtframe_obj.yaml, linebuf), cpu (m68k, z80), sdram (dwnld), ram (dual_nvram16) | [https://github.com/jotego/jtframe](https://github.com/jotego/jtframe) | `modules/jtframe` |
| simson — jtcolmix_053251.v -- el K053251 (mezclador de prioridad). La cadena de sprites YA NO viene de aqui: se reescribio en hdl/ en la sesion 94 | [https://github.com/jotego/jtcores](https://github.com/jotego/jtcores) | `cores/simson` |
| jt51 — YM2151 (sonido) | [https://github.com/jotego/jt51](https://github.com/jotego/jt51) | `modules/jt51` |
| jt053260 — K053260 (PCM) | [https://github.com/jotego/jtcores](https://github.com/jotego/jtcores) | `modules/jt053260` |
| jteeprom — jt5911.sv -- EEPROM en serie de ajustes | [https://github.com/jotego/jteeprom](https://github.com/jotego/jteeprom) | `modules/jteeprom` |

> Bloque generado por `omf_release`. Edítalo en la receta del core, no aquí.
<!-- /omf_release:dependencias:ssriders -->
