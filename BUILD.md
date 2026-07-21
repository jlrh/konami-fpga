# Building the core (reproducible) — Moo Mesa

🇬🇧 English (below) · [🇪🇸 Español](#compilar-el-core-reproducible--moo-mesa)

Steps to rebuild the `.rbf` from scratch. **No patch is required**: every game ROM is loaded at
**runtime** from the `.mra`, so the bitstream is distributable as-is. Tested for MiSTer.

## Requirements
- A [**jtcores**](https://github.com/jotego/jtcores) checkout (brings jtframe + jt51 as modules) and its
  toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (the version your MiSTer board needs).
- Your **moomesa** ROMs (not included) — see [`README.md`](README.md).

## Steps

1. **Place the core** inside jtcores:
   ```
   cp -r cores/moomesa  <jtcores>/cores/moomesa
   ```

2. **Build** (generate + compile):
   ```
   cd <jtcores> && source setprj.sh
   jtcore moomesa -mister -c
   ```
   This generates `<jtcores>/cores/moomesa/mister/` (Quartus project + the memgen GAMETOP
   `jtmoomesa_game_sdram.v`) and compiles it. The result is the `.rbf` under `mister/output_files/`.

## The K054539 (PCM sound)

The PCM sound chip is `k054539` — **written from scratch** (there is no `jt539` in jtframe; it is a
private module). It is validated **bit-exact** against a MAME-derived C++ reference. Its **generated**
Q16 volume/pan tables (`voltab.hex`, `pantab.hex`) and a zero-init table (`rram_zero.hex`) are loaded via
`$readmemh` and enter synthesis — they are **math/zeros, not game data**, so the bitstream stays clean.
The PCM **samples** (and all other game ROMs) are loaded at runtime from the `.mra`.

> **Video power-up:** the core forces `ALLOW_POWER_UP_DONT_CARE OFF` in its `.qsf` so the unreset video
> pipeline flops power up at 0 (clean black on load) instead of showing vertical bars. Verify the setup
> slack stays positive after any change.

## Legal / distribution
- This repo's **code** is GPLv3 and contains no ROMs.
- The **`.rbf` in [`releases/`](releases/)** was built with these steps: no game ROM is inside → it is
  **distributable**. The **ROMs** are provided by each user.

---

# Compilar el core (reproducible) — Moo Mesa

🇪🇸 Español · [🇬🇧 English ↑](#building-the-core-reproducible--moo-mesa)

Pasos para reconstruir el `.rbf` desde cero. **No hace falta ningún parche**: cada ROM del juego se carga
en **runtime** desde el `.mra`, así que el bitstream es distribuible tal cual. Probado para MiSTer.

## Requisitos
- Un checkout de [**jtcores**](https://github.com/jotego/jtcores) (trae jtframe + jt51 como módulos) y su
  toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (la versión que pida tu placa MiSTer).
- Tus ROMs de **moomesa** (no se incluyen) — ver [`README.md`](README.md).

## Pasos

1. **Coloca el core** dentro de jtcores:
   ```
   cp -r cores/moomesa  <jtcores>/cores/moomesa
   ```

2. **Compila** (genera + compila):
   ```
   cd <jtcores> && source setprj.sh
   jtcore moomesa -mister -c
   ```
   Esto genera `<jtcores>/cores/moomesa/mister/` (proyecto Quartus + el GAMETOP de memgen
   `jtmoomesa_game_sdram.v`) y lo compila. El resultado es el `.rbf` en `mister/output_files/`.

## El K054539 (sonido PCM)

El chip de sonido PCM es `k054539` — **escrito desde cero** (no existe `jt539` en jtframe; es un módulo
privado). Está validado **bit-exacto** contra una referencia C++ derivada de MAME. Sus tablas Q16 de
volumen/pan **generadas** (`voltab.hex`, `pantab.hex`) y una tabla de ceros (`rram_zero.hex`) se cargan
con `$readmemh` y entran en síntesis — son **matemáticas/ceros, no datos del juego**, así que el
bitstream queda limpio. Los **samples** PCM (y el resto de ROMs) se cargan en runtime desde el `.mra`.

> **Power-up de vídeo:** el core fuerza `ALLOW_POWER_UP_DONT_CARE OFF` en su `.qsf` para que los flops del
> pipeline de vídeo sin reset arranquen a 0 (negro limpio al cargar) en vez de mostrar barras verticales.
> Comprueba que el slack de setup sigue positivo tras cualquier cambio.

## Legalidad / distribución
- El **código** de este repo es GPLv3 y no contiene ROMs.
- El **`.rbf` de [`releases/`](releases/)** se compiló con estos pasos: ninguna ROM del juego va dentro →
  es **distribuible**. Las **ROMs** las aporta cada usuario.
