/*  This file is part of JTCORES (fork COWBOYS / Moo Mesa). GPLv3.

    cowboys_video — integra el tilemap K056832 (cowboys_k056832, validado 0.00% vs golden) con
    los sprites (cowboys_obj: FORK PROPIO desde simson, ses.24 - ver cabecera del fichero) y el colmix (K053251 + K054338 alpha).

    Arquitectura del tilemap = estilo rungun (Camino A): el modulo K056832 lleva su PROPIO vtimer
    (fuente de timing del core) + VRAM interna paginada + 1 bus ROM SERIAL (scr) que multiplexa las 4
    capas. Sustituye a jtaliens_scroll (que era el K052109 de X-Men, chip distinto).

    PENDIENTE (validacion por escenas / Fase siguiente):
      - Empaquetado EXACTO de pixel hacia el K053251 en colmix (ci = f(colnib,pen)) — juez: sim==golden.
      - Alpha K054338 (geiser) — delta extra en colmix.
      - Carga por escena: la VRAM/regs del modulo son internos; para restore-ioctl habra que exponerlos
        como BRAM jtframe (como rungun) o cargar por el bus CPU en el testbench de escena.
      - Timing HW: el vtimer usa HTOTAL=456 (limite 9 bits); para MiSTer real revisar HJUMP/CRTC K053252.
      - Lectura CPU 16-bit (tilesys_dout) y separacion vram_cs(0x1a0000)/reg_cs(0x0c0000) en main (Fase 1).
*/
module cowboys_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    // Base Video (las genera el vtimer del K056832)
    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    // Observabilidad para el harness de validacion (cowboys_vfull lo INSTANCIA: sesion 16). En
    // produccion se dejan ABIERTOS -> no cambian el comportamiento (son taps del framebuffer y del
    // pixel de sprite). Eliminan la COPIA que derivaba en silencio (orama, EDGE_TRIGGER): las 2 caras
    // del C-06 de las sesiones 12-14.
    output     [ 8:0] hdump,
    output     [ 8:0] vdump,
    output     [ 8:0] lyro_pxl_o,   // pixel de sprite (dbg_spr en el tb)

    output            tile_irqn,
    output            tile_nmin,

    // Object DMA
    input      [13:1] oram_addr,
    input      [ 1:0] oram_we,
    // CPU interface
    input      [16:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    input             pcu_cs,
    input             alpha_cs,     // K054338 regs 0x0ca000
    input             pal_cs,
    output     [15:0] pal_dout,
    output     [15:0] tilesys_dout,

    output            dma_bsy,
    output     [15:0] objsys_dout,
    input             objsys_cs,
    input             objreg_cs,
    input             objcha_n,

    output reg        vdtac,
    input             tilesys_cs,   // VRAM window 0x1a0000
    input             tilereg_cs,   // K056832 regs 0x0c0000
    output            rst8,

    // control
    input             rmrd,
    output            flip,

    // Tile ROM (K056832) — 1 bus serial DW32
    output     [20:2] scr_addr,
    output            scr_cs,
    input      [31:0] scr_data,
    input             scr_ok,

    // Sprite ROM — [22:2] (21 bits word addr) = 8MB completos. Antes [21:2] truncaba rom_addr[22]
    // (bug: los sprites de code alto, moomesa 0xf6xx, leian la mitad equivocada -> transparentes).
    output     [22:2] lyro_addr,
    output            lyro_cs,
    input             lyro_ok,
    input      [31:0] lyro_data,

    // Color
    input      [ 2:0] dim,
    input             dimmod,
    input             dimpol,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    // Debug
    input      [15:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout
);

wire [ 8:0] vrender, vrender1, lyro_pxl;   // hdump/vdump/lyro_pxl_o ya son PUERTOS (observabilidad)
assign lyro_pxl_o = lyro_pxl;
wire [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl, dump_obj, obj_mmr;
wire        lyra_mix, lyrb_mix, lyrc_mix;   // flag de mezcla por tile (attr[2]) - ses.24
wire [ 4:0] lyro_pri;
wire [ 1:0] shadow;
wire [ 3:0] obj_amsb = 4'd0;   // TODO: dump ioctl de sprites (venia de jtriders_dump, eliminado)
wire [15:0] tile_din;
wire [18:0] rom_addr;
wire [ 1:0] rom_lyr;
wire        rom_cs, cpu_weg;
wire [ 3:0] ommra;
wire [13:1] orama;
wire [ 1:0] orama_we;

assign cpu_weg     = cpu_we && cpu_dsn!=2'b11;
assign flip        = 1'b0;
assign tile_nmin   = 1'b1;
assign rst8        = 1'b0;
assign st_dout     = 8'd0;
assign tilesys_dout= tile_din;         // lectura CPU 16-bit (ram_word_r): la VRAM del K056832 es de words
// scr_addr[20:2] (19 bits, word DW32) = rom_addr[18:0] (word) directo
assign scr_addr    = rom_addr;
assign scr_cs      = rom_cs;

always @(posedge clk) vdtac <= 1'b1;   // TODO Fase 1: dtack real de la ventana de tiles

/* verilator tracing_on */
// ---------------- TILEMAP K056832 (validado) ----------------
cowboys_k056832 u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .vs         ( vs        ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),

    // CPU (68000, bus 16b)
    .vram_cs    ( tilesys_cs),
    .reg_cs     ( tilereg_cs),
    .cpu_we     ( cpu_weg   ),
    .cpu_addr   (cpu_addr[12:1]),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( tile_din  ),

    // ROM de tiles (1 bus serial)
    .rom_addr   ( rom_addr  ),
    .rom_lyr    ( rom_lyr   ),
    .rom_cs     ( rom_cs    ),
    .rom_data   ( scr_data  ),
    .rom_ok     ( scr_ok    ),

    // pixel out (4 capas)
    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyrc_pxl   ( lyrc_pxl  ),
    .lyra_mix   ( lyra_mix  ),
    .lyrb_mix   ( lyrb_mix  ),
    .lyrc_mix   ( lyrc_mix  ),

    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

assign tile_irqn = 1'b1;   // TODO Fase 1: IRQ4 vblank del K056832/CRTC

/* verilator tracing_on */
assign ommra = {cpu_addr[3:1],cpu_dsn[1]};

// MODELO DE OBJRAM (sesion 13). moomesa reparte 256 slots de sprite con paso 0x100 sobre los 64 kB de
// 0x190000 (moo.cpp:416 `object_dma`: `src += 0x80` words, y solo las 8 primeras words de cada slot
// importan). El K053246 escanea su RAM externa con paso 8 words (`k053246_dma.v:126-137`: lee [3:1]=0..6
// y salta al siguiente bloque de 16 B). Son DOS espacios de direcciones distintos, y la conversion entre
// ambos es exactamente `slot N word w:  juego = N*0x80+w   <->  chip = N*8+w`.
// ⭐ ESTO NO ES UNA HIPOTESIS: es lo que `ver/cowboys/tb_vfull.cpp:90-92` lleva 8 sesiones haciendo en C++
// sobre el dump del oraculo (`src=N*0x80+w` -> `dst=N*8+w`) para dar `vfull 1800` = 0.0000% pixel-exacto.
// El tb hacia la conversion FUERA del RTL, asi que el core real se quedo sin ella.
//   juego (word) = {N[7:0], 4'd0, w[2:0]} = cpu_addr[15:1]   ->   N=cpu_addr[15:8], w=cpu_addr[3:1]
// Las words con cpu_addr[7:4]!=0 NO pertenecen a ninguna entrada: no se escriben (si se escribieran,
// aliasearian sobre la word 0 del slot y machacarian el bit de activo).
// El test de sprite RAM del POST (0x4a18e) SIGUE PASANDO: escribe y RELEE cada long EN EL ACTO con
// patrones UNIFORMES (0 / 0xffffff), asi que la word aliaseada ya contiene ese mismo patron. (Es la misma
// razon por la que pasaba con el aliasing 4:1 de antes — ese test no prueba NADA sobre el layout: §sesion 12.)
// Destino: NO hace falta la compactacion de `object_dma`. MAME no ordena en el DMA, ordena AL DIBUJAR
// (`k053246_k053247_k055673.cpp:324-374`, `sortedlist` por el byte de prioridad); `k053246_dma` hace esa
// misma ordenacion en el DMA via LUT (`dma_bufa <= {sort_24x,3'd0}`) = como el chip real. Neto: identico.
// RAMW=13 -> el DMA barre words 0..4095 (entradas 0..511); las 256..511 nunca se escriben => 0 => bit15=0
// => descartadas. Por eso RAMW se queda en 13 y no hace falta RAM extra.
assign orama    = { 2'd0, cpu_addr[15:8], cpu_addr[3:1] };
assign orama_we = oram_we & {2{cpu_addr[7:4]==4'd0}};

// SONDA (sesion 12): saca el `cfg` REAL de dentro de `k053246_mmr` sin tocar nada compartido.
// `cowboys_obj` -> `st_addr = ioctl_ram ? ioctl_addr : debug_bus` y `k053246_mmr: 5: st_dout <= cfg`,
// que sale por `dump_reg` (= `obj_mmr`). Forzando debug_bus=5 en sim, `obj_mmr` ES el cfg del registro.
// VERIFICADO que es inerte para el render: el UNICO uso de debug_bus aguas abajo (`k053246_scan.sv:215`)
// esta COMENTADO. Aun asi hay que re-correr vfull/vmix: la sonda es de sim, pero el mux no.
wire [7:0] obj_dbg;
`ifdef SIMULATION
assign obj_dbg = 8'd5;
`else
assign obj_dbg = debug_bus;
`endif

`ifdef SIMULATION
// SONDA (sesion 12): que ve EXACTAMENTE el k053246_mmr en una escritura de registro.
// Ojo: el tb de video NUNCA ejercita este camino — `k053246_mmr.v:51` hace `mmr_init[5][4]=1`,
// o sea que en sim el mmr CARGA cfg de un dump y fuerza dma_en=1. Por eso `vfull` da sprites
// pixel-exactos con el DMA "funcionando" y el boot real puede tener este camino ROTO sin que
// ninguna regresion de video lo cace. (Mismo patron que el pxl_cen UNDRIVEN de la sesion 5.)
// El mmr latchea con: cs && cpu_we, case(cpu_addr[2:1])==2, !cpu_dsn[0] -> cfg <= cpu_dout[7:0].
// MEDIDO sesion 12: SI latchea (`dsn=10 dout=3030 -> LATCHEA cfg`) => dma_en=1 dentro del modulo.
// Luego el fallo esta en el TRIGGER del DMA: dma_en && (lvbl_sh==2'b10 && hs_pos), que depende
// de `hs` y `lvbl` — las señales que el tb de video INYECTA y el core real debe GENERAR.
always @(posedge clk) if( objreg_cs && cpu_we ) begin
    $display("OBJREG_WR ommra=%b (addr[2:1]=%0d) dsn=%b dout=%04x -> %s",
        ommra, ommra[2:1], cpu_dsn, cpu_dout,
        (ommra[2:1]==2'd2 && !cpu_dsn[0]) ? "LATCHEA cfg" : "no toca cfg");
end

// ¿Pulsan `hs` y `lvbl` en el CORE REAL? El DMA necesita hs_pos (flanco de HS muestreado a pxl2_cen)
// y ver lvbl 1->0. Si hs no pulsa, lvbl_sh nunca vale 2'b10 y el DMA NO ARRANCA NUNCA.
reg hs_l, lvbl_l2, p2c_seen;
integer n_hs=0, n_lvbl=0, n_p2c=0;
always @(posedge clk) begin
    hs_l <= hs; lvbl_l2 <= lvbl;
    if( pxl2_cen ) n_p2c <= n_p2c+1;
    if( ~hs_l & hs ) n_hs <= n_hs+1;
    if( lvbl_l2 & ~lvbl ) begin
        n_lvbl <= n_lvbl+1;
        $display("VTIMER frame=%0d | hs_pos=%0d pxl2_cen=%0d (por frame) | MMRCFG cfg=%02x dma_en=%b",
            n_lvbl, n_hs, n_p2c, obj_mmr, obj_mmr[4]);
        n_hs <= 0; n_p2c <= 0;
    end
end
`endif

// voffset del K053246/247: moomesa usa el valor SIMSON (0x117), NO el "no-simson" (0x107). Hallado con
// probe single-cell (spr0) — el sweep grueso 0x105..0x10d no lo tocaba. Antes 0xff (heredado, mal).
localparam [9:0] OVOFFSET=10'h117;
// Offset H del obj: el K053246 espera hdump 0x20-based (Konami CRTC); nuestro hdump es 0-based. Calibracion
// de origen CRT (constante). OBJ_HOFF=149 + OVOFFSET=0x117 => sprites PIXEL-EXACTOS vs golden --mode full en
// escenas 600/900/1800 (0 diffs de sprite; solo residuo col-0/pipeline conocido). Validado run_vfull sesion 4.
localparam [8:0] OBJ_HOFF=9'd149;

// ⭐ EDGE_TRIGGER (sesion 12) — el DMA de sprites de moomesa es un ARMADO DE UN SOLO DISPARO.
// Desensamblado del juego (coste 0 sims), protocolo REAL:
//   1) el juego ARMA:            `move.b #$30,$0c2005` (0x20ce/0x2114) o `ori.b #$10,$180013`+publica
//   2) al vblank el HW hace el DMA y, al terminar, pide IRQ4 (`dmaend`)
//   3) el handler de IRQ5 (vector 0x74 -> 0x2482) DESARMA en su PRIMERA instruccion util:
//        2484: andi.b #$ef,$180013   ; limpia bit4
//        248c: move.b $180013,$0c2005 ; publica -> cfg[4]=0
// El trigger por defecto (`dma_en && lvbl_sh==2'b10 && hs_pos`) muestrea ~2 LINEAS (~127us) DESPUES de
// que caiga lvbl; para entonces el 68k YA ha ejecutado el handler de IRQ5 y `dma_en` vale 0 => el DMA
// NO ARRANCA NUNCA => sin flanco de `dma_bsy` no hay IRQ4 => cuelgue en 0x1214. MAME no tiene la carrera
// porque `moo_interrupt` muestrea `k053246_is_irq_enabled()` en el INSTANTE del vblank, antes de la ISR.
// `trigger_at_dmaen = ~dma_en & dmaen_l` (flanco de BAJADA) modela el protocolo tal cual.
// PRECEDENTE: `rungun` (Konami, cerrado) hace EXACTAMENTE esto en `jtrungun_video.v:94`.
// Ojo al `ifndef`: con NOMAIN (los tb de video vmix/vfull) NO hay CPU que desarme y `k053246_mmr.v:51`
// fuerza `mmr_init[5][4]=1` fijo => con EDGE_TRIGGER=1 el flanco no llegaria NUNCA y los sprites
// DESAPARECERIAN del tb. Por eso el trigger viejo se queda para NOMAIN. (Y por eso `vfull`=0.0000%
// convivia con el DMA real muerto: el tb NO puede ver este bug — el C-06 de la sesion 12.)
localparam EDGE_TRIGGER = `ifndef NOMAIN 1 `else 0 `endif;

cowboys_obj #(.RAMW(13),.SHADOW(1),.EDGE_TRIGGER(EDGE_TRIGGER)) u_obj(   // FORK PROPIO (ses.24)
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),
    .simson     ( 1'b0      ),
    .ln_done    (           ),

    .voffset    ( OVOFFSET  ),
    .hs         ( hs        ),
    .lvbl       ( lvbl      ),
    .hdump      ( hdump + OBJ_HOFF ),
    .vdump      ( vrender   ),   // como simson: el obj usa vrender (linea a preparar), no vdump
    // CPU interface
    .ram_cs     ( objsys_cs ),
    .ram_addr   ( orama     ),
    .ram_din    ( cpu_dout  ),
    .ram_we     ( orama_we  ),
    .cpu_din    (objsys_dout),

    .reg_cs     ( objreg_cs ),
    .mmr_addr   ( ommra     ),
    .mmr_din    ( cpu_dout  ),
    .mmr_we     ( cpu_we    ),
    .mmr_dsn    ( cpu_dsn   ),

    .dma_bsy    ( dma_bsy   ),
    // ROM
    .rom_addr   ( lyro_addr ),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     ( lyro_cs   ),
    .objcha_n   ( objcha_n  ),
    // pixel output
    .pxl        ( lyro_pxl  ),
    .shd        ( shadow    ),
    .prio       ( lyro_pri  ),
    // Debug
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( {obj_amsb[1:0],ioctl_addr[11:0]} ),
    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( obj_dbg   )   // sonda cfg: =5 en sim, debug_bus en HW (ver arriba)
);

/* verilator tracing_on */
cowboys_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),

    // CPU interface (paleta 0x1c0000, prio K053251 0x0cc000)
    .cpu_addr   (cpu_addr[12:1]),
    .cpu_we     ( cpu_weg   ),
    .cpu_din    ( pal_dout  ),
    .cpu_d8     ( cpu_dout[7:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .pal_cs     ( pal_cs    ),
    .pcu_cs     ( pcu_cs    ),
    .alpha_cs   ( alpha_cs  ),

    // Final pixels (4 capas de tile 8b {colnib,pen} + sprites)
    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyrc_pxl   ( lyrc_pxl  ),
    .lyra_mix   ( lyra_mix  ),
    .lyrb_mix   ( lyrb_mix  ),
    .lyrc_mix   ( lyrc_mix  ),
    .lyro_pxl   ( lyro_pxl  ),   // 9b sprites -> ci1
    .lyro_pri   ( lyro_pri  ),

    .dimmod     ( dimmod    ),
    .dimpol     ( dimpol    ),
    .dim        ( dim       ),
    .shadow     ( shadow    ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      ),

    // Debug
    .ioctl_addr ( ioctl_addr[11:0]),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( ioctl_din ),
    .dump_mmr   (           ),

    .debug_bus  ( debug_bus )
);

endmodule
