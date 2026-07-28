# Building the cores (reproducible)

🇬🇧 English (below) · [🇪🇸 Español](#compilar-los-cores-reproducible)

Steps to rebuild any `.rbf` in this repo from scratch. **No patch is required**: every game ROM is
loaded at **runtime** from the `.mra`, so each bitstream is distributable as-is. Tested for MiSTer.

## Requirements (all cores)
- A [**jtcores**](https://github.com/jotego/jtcores) checkout (brings jtframe + jt51 as modules) and its
  toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (the version your MiSTer board needs).
- Your own ROMs for the game (not included) — see [`README.md`](README.md).

## Asterix

1. **Place the core** inside jtcores:
   ```
   cp -r cores/asterix  <jtcores>/cores/asterix
   ```
2. **Build** (generate + compile):
   ```
   cd <jtcores> && source setprj.sh
   jtcore asterix -mister -c
   ```
   This generates `<jtcores>/cores/asterix/mister/` (Quartus project + the memgen GAMETOP
   `jtasterix_game_sdram.v`) and compiles it. The result is the `.rbf` under `mister/output_files/`.

**The K053260 (PCM sound)** is not written from scratch: `jt053260` already exists as a validated module
in the common jtframe tree, so this core just instances it (unlike Moo Mesa's `k054539`, below). The
core-specific sound work is the Z80 memory map and the 68000↔Z80↔K053260 boot-gate handshake
(`jtasterix_sound.v`).

**The palette blitter** (`jtasterix_main.v`) is a bus-master ROM→palette copier recreated as HLE, and it
gates the whole boot sequence: the 68000 will not proceed past POST until the Z80+K053260 handshake
completes, so a broken sound path shows up as "the game doesn't boot", not just "no sound".

## Moo Mesa

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

**The K054539 (PCM sound)** is `k054539` — **written from scratch** (there is no `jt539` in jtframe; it
is a private module). It is validated **bit-exact** against a MAME-derived C++ reference. Its
**generated** Q16 volume/pan tables (`voltab.hex`, `pantab.hex`) and a zero-init table
(`rram_zero.hex`) are loaded via `$readmemh` and enter synthesis — they are **math/zeros, not game
data**, so the bitstream stays clean. The PCM **samples** (and all other game ROMs) are loaded at
runtime from the `.mra`.

> **Video power-up:** the core forces `ALLOW_POWER_UP_DONT_CARE OFF` in its `.qsf` so the unreset video
> pipeline flops power up at 0 (clean black on load) instead of showing vertical bars. Verify the setup
> slack stays positive after any change.

## Legal / distribution
- This repo's **code** is GPLv3 and contains no ROMs.
- Every **`.rbf` in [`releases/`](releases/)** was built with these steps: no game ROM is inside → each
  is **distributable**. The **ROMs** are provided by each user.

---

# Compilar los cores (reproducible)

🇪🇸 Español · [🇬🇧 English ↑](#building-the-cores-reproducible)

Pasos para reconstruir cualquier `.rbf` de este repo desde cero. **No hace falta ningún parche**: cada
ROM del juego se carga en **runtime** desde el `.mra`, así que cada bitstream es distribuible tal cual.
Probado para MiSTer.

## Requisitos (todos los cores)
- Un checkout de [**jtcores**](https://github.com/jotego/jtcores) (trae jtframe + jt51 como módulos) y su
  toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (la versión que pida tu placa MiSTer).
- Tus propias ROMs del juego (no se incluyen) — ver [`README.md`](README.md).

## Asterix

1. **Coloca el core** dentro de jtcores:
   ```
   cp -r cores/asterix  <jtcores>/cores/asterix
   ```
2. **Compila** (genera + compila):
   ```
   cd <jtcores> && source setprj.sh
   jtcore asterix -mister -c
   ```
   Esto genera `<jtcores>/cores/asterix/mister/` (proyecto Quartus + el GAMETOP de memgen
   `jtasterix_game_sdram.v`) y lo compila. El resultado es el `.rbf` en `mister/output_files/`.

**El K053260 (sonido PCM)** no se escribe desde cero: `jt053260` ya existe como módulo validado en el
árbol común de jtframe, así que este core simplemente lo instancia (a diferencia del `k054539` de Moo
Mesa, más abajo). El trabajo propio de sonido es el mapa de memoria del Z80 y el handshake de boot-gate
68000↔Z80↔K053260 (`jtasterix_sound.v`).

**El blitter de paleta** (`jtasterix_main.v`) es un copiador ROM→paleta por bus-master recreado por HLE,
y condiciona toda la secuencia de arranque: el 68000 no pasa del POST hasta que el handshake Z80+K053260
se completa, así que un camino de sonido roto se manifiesta como "el juego no arranca", no solo como
"no hay sonido".

## Moo Mesa

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

**El K054539 (sonido PCM)** es `k054539` — **escrito desde cero** (no existe `jt539` en jtframe; es un
módulo privado). Está validado **bit-exacto** contra una referencia C++ derivada de MAME. Sus tablas Q16
de volumen/pan **generadas** (`voltab.hex`, `pantab.hex`) y una tabla de ceros (`rram_zero.hex`) se cargan
con `$readmemh` y entran en síntesis — son **matemáticas/ceros, no datos del juego**, así que el
bitstream queda limpio. Los **samples** PCM (y el resto de ROMs) se cargan en runtime desde el `.mra`.

> **Power-up de vídeo:** el core fuerza `ALLOW_POWER_UP_DONT_CARE OFF` en su `.qsf` para que los flops del
> pipeline de vídeo sin reset arranquen a 0 (negro limpio al cargar) en vez de mostrar barras verticales.
> Comprueba que el slack de setup sigue positivo tras cualquier cambio.

## Legalidad / distribución
- El **código** de este repo es GPLv3 y no contiene ROMs.
- Cada **`.rbf` de [`releases/`](releases/)** se compiló con estos pasos: ninguna ROM del juego va dentro
  → es **distribuible**. Las **ROMs** las aporta cada usuario.
