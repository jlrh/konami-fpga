# konami-fpga

🇬🇧 English (below) · [🇪🇸 Español](#español)

FPGA recreations of **Konami** arcade boards, built on the **JTFRAME** framework (GPLv3). MiSTer target.

> ℹ️ Independent project — **NOT** an official jotego core. Built on his GPLv3 JTFRAME framework.

## Cores

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
Or build from source (`cores/cowboys/`). See [`BUILD.md`](BUILD.md).

> ℹ️ Naming: the PCM chip keeps its real silicon name (`k054539`, no `jt`); the GAMETOP is
> `jtcowboys_game` (memgen imposes the `jt`).

## Build

This repo contains **only the core code** (`cores/cowboys/`). The framework and third-party cores
(jtframe, jt51) are **not included** — jtframe provides them. Quick version:

1. Clone [jtcores](https://github.com/jotego/jtcores) (brings jtframe + modules).
2. Copy this repo's `cores/cowboys/` into your jtcores checkout.
3. Build: `jtcore cowboys -mister -c`.

📋 **Step-by-step in [`BUILD.md`](BUILD.md).**

Core layout:
```
cores/cowboys/
├── hdl/   Core Verilog (jtcowboys_* modules + k054539 PCM chip + jtcowboys_game GAMETOP + *.hex tables)
├── cfg/   macros.def, mem.yaml, files.yaml, mame2mra.toml
└── mra/   .mra definition (how to assemble the ROMs)
```

## ROMs

**Not included** (copyrighted material). Everyone provides the original **moomesa** ROMs of their own
board. The `.mra` describes how to assemble them; every ROM (program, sound, PCM samples, tiles,
sprites) is loaded at runtime, so the `.rbf` carries no copyrighted data.

## Credits

- **JTFRAME**, **jt51** — the GPLv3 frameworks this core is built on
- **MAME** — hardware reference (`moo.cpp` driver, `k054539.cpp` sound chip)
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
dato con copyright**. O compila desde fuente (`cores/cowboys/`). Ver [`BUILD.md`](BUILD.md).

> ℹ️ Nomenclatura: el chip PCM conserva su nombre real de silicio (`k054539`, sin `jt`); el GAMETOP es
> `jtcowboys_game` (memgen impone el `jt`).

## Construir

Este repo contiene **solo el código del core** (`cores/cowboys/`). El framework y los cores de terceros
(jtframe, jt51) **no se incluyen** — los aporta jtframe. Versión rápida:

1. Clona [jtcores](https://github.com/jotego/jtcores) (trae jtframe + módulos).
2. Copia `cores/cowboys/` de este repo dentro de tu checkout de jtcores.
3. Compila: `jtcore cowboys -mister -c`.

📋 **Pasos detallados en [`BUILD.md`](BUILD.md).**

Estructura del core:
```
cores/cowboys/
├── hdl/   Verilog del core (módulos jtcowboys_* + chip PCM k054539 + GAMETOP jtcowboys_game + tablas *.hex)
├── cfg/   macros.def, mem.yaml, files.yaml, mame2mra.toml
└── mra/   definición .mra (cómo ensamblar las ROMs)
```

## ROMs

**No se incluyen** (material con copyright). Cada cual aporta las ROMs originales de **moomesa** de su
placa. El `.mra` describe cómo ensamblarlas; cada ROM (programa, sonido, samples PCM, tiles, sprites) se
carga en runtime, así que el `.rbf` no lleva ningún dato con copyright.

## Créditos

- **JTFRAME**, **jt51** — los frameworks GPLv3 sobre los que se construye este core
- **MAME** — referencia de hardware (driver `moo.cpp`, chip de sonido `k054539.cpp`)
- **Furrtek** — ingeniería inversa del silicio del K054539

## Agradecimientos

- A **Sorgelig** y todo el proyecto y comunidad **MiSTer FPGA**.
- A la **comunidad MAME**, por el trabajo de preservación e ingeniería inversa sin el cual este core no
  sería posible.
- Y a **Anthropic**, por **Claude**.

## Licencia

**GPLv3** (ver [`LICENSE`](LICENSE)) — obligado por las dependencias JTFRAME / jt51; sus avisos de
copyright se conservan en las fuentes.
