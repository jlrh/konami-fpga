/*  This file is part of JTCORES (fork COWBOYS / Moo Mesa). GPLv3.

    jtasterix_video — integra el tilemap K056832 (jtasterix_k056832, validado 0.00% vs golden) con
    los sprites (jtsimson_obj, reuso xmen/simson) y el colmix (K053251 + K054338 alpha).

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
module jtasterix_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    // Base Video (las genera el vtimer del K056832)
    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    // Observabilidad para el harness de validacion (jtasterix_vfull lo INSTANCIA: sesion 16). En
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
    input             objreg_byte,  // 1 = ventana 0x300000 (umask 00ff): el indice es cpu_addr[4:1]
    input             objcha_n,

    output reg        vdtac,
    input             tilesys_cs,   // VRAM window 0x1a0000
    input             tilereg_cs,   // K056832 regs 0x0c0000
    output            rst8,

    // control
    input             rmrd,
    input             tilebank,     // control2 bit5 (m_cur_tile_bank) -> K056832 get_lookup
    input      [15:0] spritebank,   // 0x380400 (reset_spritebank) -> code de sprite (K053245)
    input      [ 8:0] objdx,        // sweep de calibración: offset H del obj (hdump+objdx)
    input      [ 9:0] objdy,        // sweep de calibración: offset V del obj (vdump+objdy)
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
jtasterix_k056832 u_scroll(
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
    .cpu_dsn    ( cpu_dsn   ),
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

    .tilebank   ( tilebank  ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

assign tile_irqn = 1'b1;   // TODO Fase 1: IRQ4 vblank del K056832/CRTC

/* verilator tracing_on */
// ---------------- SPRITES K053244/K053245 (jtasterix_obj, B2) ----------------
// mmr_addr = índice de registro-byte del K053244 (0:xoff_hi 1:xoff_lo 2:yoff_hi
// 3:yoff_lo 5:cfg[bit4=dma_en] 6:update_buffer); el mmr en modo k44_en no usa dsn como
// byte-enable, sólo para el índice. El tb (y el main) direccionan los 8 regs-byte por aquí.
//
// 🐞 SESION 26 — EL CHIP ESTA MAPEADO DOS VECES Y EL INDICE NO ES EL MISMO EN LAS DOS VENTANAS.
// `asterix.cpp:298/301`:
//   0x200000-0x20000F  bus de 16 bits, handlers de BYTE  -> offset = {A[3:1], A0}, y A0 = UDSn
//                      (byte PAR = UDS = offset par). Indice = {cpu_addr[3:1], cpu_dsn[1]}.
//   0x300000-0x30001F  `.umask16(0x00ff)` -> SOLO bytes IMPARES, 16 offsets. Indice = cpu_addr[4:1].
// Aquí sólo estaba la primera forma, así que TODO lo que el juego escribe por 0x300000 caía en el
// registro 2N+1. Medido con `tools/mame_objregtap.lua` (60 s de attract): los regs 0, 1 y 4 llegan
// SOLO por 0x300000, o sea que xoffset entero (0xFF96 = -106) se perdía y quedaba en 0x00FF (+255)
// => 361 px de error => TODOS los sprites fuera de pantalla por la derecha. Y el reg 3, escrito por
// 0x300006, aterrizaba en el índice 7 (= clear_buffer / dma_trig espurio).
// `objreg_byte` (jtasterix_main.v:288) ya distinguía las dos ventanas y NO LO USABA NADIE.
assign ommra    = objreg_byte ? cpu_addr[4:1] : {cpu_addr[3:1], cpu_dsn[1]};
// spr-RAM K053245 = 0x800 B = 0x400 words, PLANA (8 words/sprite, m_buffer). NADA del
// stride 0x100 de moomesa: el K053245 tiene su propia spr-RAM contigua en 0x180000.
assign orama    = cpu_addr[13:1];
assign orama_we = oram_we;

`ifdef SIMULATION
// SONDA SESION 29 (c) — la paleta de sprites ya se probo EXACTA a MAME (pal_900/1200.hex, ver
// jtasterix_colmix.v). El defecto de los personajes con colores apagados en frame_01173.png tiene que
// venir de OTRO sitio: OBJ RAM (spr-RAM, 0x400 words, K053245) o del "code_bank"/spritebank de
// jtasterix_obj.v (unico delta de asterix vs jtriders_obj, sin validar contra MAME todavia). Traza
// CADA escritura a spr-RAM (frame local + indice de word + dato) para diff directo contra el golden
// `debug/asterix/dumps/spr_1200.hex` (1024 lineas = 1024 words, volcado de m_spriteram de MAME).
integer vs_frame = 0;
reg     vs_lvbl_l = 0;
always @(posedge clk) begin
    vs_lvbl_l <= lvbl;
    if( lvbl && !vs_lvbl_l ) vs_frame <= vs_frame + 1;
end
always @(posedge clk) if( objsys_cs && cpu_we && |orama_we )
    $display("OBJRAM-W: frame=%0d idx=%0d(0x%03x) data=%04x we=%02x", vs_frame, orama, orama, cpu_dout, orama_we);
`endif

wire       obj_shd;   // K053245: shadow de 1 bit -> shd_in[0] del colmix (053251)

jtasterix_obj #(.RAMW(13),.SHADOW(1)) u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),

    .hs         ( hs        ),
    .lvbl       ( lvbl      ),
    .hdump      ( hdump + objdx ),          // offset H de calibración (sweep desde el tb)
    .vdump      ( vrender + objdy[8:0] ),   // offset V de calibración
    .spritebank ( spritebank ),

    // CPU interface (spr-RAM plana + regs K053244)
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
    // ROM (obj 4MB, [21:2])
    .rom_addr   ( lyro_addr[21:2] ),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     ( lyro_cs   ),
    .objcha_n   ( objcha_n  ),
    // pixel output
    .pxl        ( lyro_pxl  ),
    .shd        ( obj_shd   ),
    .prio       ( lyro_pri  ),
    // Debug
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( {obj_amsb[1:0],ioctl_addr[11:0]} ),
    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

assign lyro_addr[22]= 1'b0;      // obj = 4MB -> bit22 siempre 0
assign shadow       = {1'b0, obj_shd};

/* verilator tracing_on */
jtasterix_colmix u_colmix(
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
