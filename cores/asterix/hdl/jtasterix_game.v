/*  This file is part of JTCORES. GPLv3.

    jtasterix_game — top del core (contrato jtframe). FASE 1 (re-wire, 2026-07-19):
    conecta jtasterix_main (mapa 68k de asterix) con el pipeline de video (base cowboys, a CALIBRAR
    en Fase 2) y el sonido (stub, Fase 3). Los buses SDRAM: main=prog, ram=work, snd/pcm=Z80/K053260,
    scr=tiles K056832, obj=sprites K053244/45.

    ⚠ PUENTES PROVISIONALES (Fase 2/3), marcados con [F2]/[F3]:
      - video = jtasterix_video de cowboys SIN adaptar (K053246/7 via jtsimson_obj). El delta K053245,
        los offsets/shift-177/tilebank del K056832, el colmix (K053251) y COLORW 8->5 son Fase 2.
      - sound = stub mudo; jt053260 + Z80 + handshake (boot-gate) son Fase 3.
*/
module jtasterix_game(
    `include "jtframe_game_ports.inc"
);

/* verilator tracing_off */
wire        rom_cs, oram_cs, objreg_cs, objreg_byte, pal_cs, vram_cs,
            tilereg_cs, tilereg_b_cs, romrd_cs, pcu_cs, spritebank_cs, prot_cs,
            sndon, tilebank, snd_wrn, cpu_we, vdtac, dma_bsy, tile_irqn, flip, rst8;
wire [15:0] cpu_dout, oram_dout, vram_dout, pal_dout, spritebank;
wire [ 7:0] snd_dout, snd2main, st_main;
wire [20:2] scr_addr_v;    // el video da [20:2] (moomesa 2MB); asterix scr = [19:2] (1MB)
wire [22:2] lyro_addr_v;   // el video da [22:2] (moomesa 8MB); asterix obj = [21:2] (4MB)
wire [ 7:0] red_v, green_v, blue_v;   // video da 8b/canal; asterix xBGR555 -> 5b (recorte [F2])
wire [13:1] oram_addr;
wire [ 1:0] oram_we;
wire        eram_cs;
wire [15:0] eram_dout;
wire [ 1:0] eram_we;

assign debug_view = st_main;
// work RAM (bus 'ram'): direccion/we/din los deriva el top; cs/dsn los da main
assign ram_addr = main_addr[14:1];
assign ram_we   = cpu_we & ram_cs;
assign ram_din  = cpu_dout;
// slicing de buses gfx a los anchos de asterix
assign scr_addr = scr_addr_v[19:2];
assign obj_addr = lyro_addr_v[21:2];
// COLORW 5: recorte de los 5 MSB (aprox; el colmix real xBGR555 es [F2])
assign red   = red_v  [7:3];
assign green = green_v[7:3];
assign blue  = blue_v [7:3];
// sprite-RAM DMA write (K053245 @0x180000) — mapeo aproximado [F2]
assign oram_we   = {2{oram_cs & cpu_we}} & ~ram_dsn;
assign oram_addr = main_addr[13:1];
// RAM extra 0x180800-180FFF (2 KB) — `map(0x180800,0x180fff).ram()` en asterix.cpp:300. NO es un
// mirror del spr-RAM: el test de RAM del POST barre 0x180000-0x180FFF entero y sin esta RAM el
// patron incremental no se relee -> D7!=0 -> cuelgue en 0x5030. Va en BRAM (2 KB, no toca la SDRAM).
assign eram_we   = {2{eram_cs & cpu_we}} & ~ram_dsn;

jtframe_ram16 #(.AW(10)) u_eram(       // addr [10:1] = 1K words = 2 KB
    .clk    ( clk               ),
    .data   ( cpu_dout          ),
    .addr   ( main_addr[10:1]   ),
    .we     ( eram_we           ),
    .q      ( eram_dout         )
);

/* verilator tracing_off */
jtasterix_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .LVBL           ( LVBL          ),
    .irq_en         ( 1'b1          ),   // [F2] real = K056832 is_irq_enabled(0)
    // bus 68k
    .main_addr      ( main_addr     ),
    .rom_data       ( main_data     ),
    .rom_cs         ( main_cs       ),
    .rom_ok         ( main_ok       ),
    .ram_dout       ( ram_data      ),
    .ram_cs         ( ram_cs        ),
    .ram_ok         ( ram_ok        ),
    .ram_dsn        ( ram_dsn       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),
    // chip-selects
    .oram_cs        ( oram_cs       ),
    .eram_cs        ( eram_cs       ),
    .objreg_cs      ( objreg_cs     ),
    .objreg_byte    ( objreg_byte   ),
    .pal_cs         ( pal_cs        ),
    .vram_cs        ( vram_cs       ),
    .tilereg_cs     ( tilereg_cs    ),
    .tilereg_b_cs   ( tilereg_b_cs  ),
    .romrd_cs       ( romrd_cs      ),
    .pcu_cs         ( pcu_cs        ),
    .spritebank_cs  ( spritebank_cs ),
    .prot_cs        ( prot_cs       ),
    // sonido
    .snd_wrn        ( snd_wrn       ),
    .snd_dout       ( snd_dout      ),
    .snd2main       ( snd2main      ),
    .sndon          ( sndon         ),
    // datos de periféricos
    .oram_dout      ( oram_dout     ),
    .eram_dout      ( eram_dout     ),
    .objreg_dout    ( oram_dout     ),   // [F2] K053244 reg read = parte de objsys_dout
    .vram_dout      ( vram_dout     ),
    .pal_dout       ( pal_dout      ),
    .vdtac          ( vdtac         ),
    // EEPROM
    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),
    // control2 -> video
    .tilebank       ( tilebank      ),
    .spritebank     ( spritebank    ),
    // cabina
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .cab_1p         ( cab_1p        ),
    .coin           ( coin          ),
    .service        ( {4{service}}  ),
    .dip_pause      ( dip_pause     ),
    .dip_test       ( dip_test      ),
    .st_dout        ( st_main       ),
    .debug_bus      ( debug_bus     )
);

/* verilator tracing_on */
jtasterix_video u_video(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .pxl2_cen       ( pxl2_cen      ),

    .lhbl           ( LHBL          ),
    .lvbl           ( LVBL          ),
    .hs             ( HS            ),
    .vs             ( VS            ),
    .hdump          (               ),
    .vdump          (               ),
    .lyro_pxl_o     (               ),

    .tile_irqn      ( tile_irqn     ),
    .tile_nmin      (               ),

    // sprite-RAM DMA
    .oram_addr      ( oram_addr     ),
    .oram_we        ( oram_we       ),
    // CPU
    .cpu_addr       ( main_addr[16:1]),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),

    .pcu_cs         ( pcu_cs        ),
    .alpha_cs       ( 1'b0          ),   // asterix no tiene K054338
    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),
    .tilesys_dout   ( vram_dout     ),

    .dma_bsy        ( dma_bsy       ),
    .objsys_dout    ( oram_dout     ),
    .objsys_cs      ( oram_cs       ),
    .objreg_cs      ( objreg_cs     ),
    .objreg_byte    ( objreg_byte   ),   // ventana 0x300000 -> indice = cpu_addr[4:1] (ses.26)
    .objcha_n       ( 1'b1          ),

    .vdtac          ( vdtac         ),
    .tilesys_cs     ( vram_cs       ),
    // SOLO word_w (0x440000-0x44003f). ⚠ NO meter aqui tilereg_b_cs (0x380700-0x380707 = b_word_w):
    // son OTRO banco de registros (m_regsb) y el indice sale de A[5:1], asi que 0x380701/3/5/7
    // CLOBBERABAN mmr[0..3] — y el POST escribe ahi ya en 0x408/0x4a6/0x4b6/0x4de (0x40,0x55,0x61,0x00)
    // y el juego repite en cada frame. mmr[3][7:6] es `fbits`, o sea que corrompia el layout de tiles.
    // m_regsb solo lo usa `mw_rom_word_r` (K053936), que asterix NO usa (usa old_rom_word_r) -> se
    // ignora la ventana entera. Es write-only en el mapa, no hay lectura que devolver.
    .tilereg_cs     ( tilereg_cs    ),
    .rst8           ( rst8          ),

    .rmrd           ( romrd_cs      ),
    .tilebank       ( tilebank      ),
    .spritebank     ( spritebank    ),
    .objdx          ( 9'd124        ),   // K053245: offsets CALIBRADOS vs golden (vfull, sesion B2)
    .objdy          ( 10'h3ff       ),   // = -1
    .flip           ( flip          ),

    .scr_addr       ( scr_addr_v    ),
    .scr_cs         ( scr_cs        ),
    .scr_data       ( scr_data      ),
    .scr_ok         ( scr_ok        ),

    .lyro_addr      ( lyro_addr_v   ),
    .lyro_cs        ( obj_cs        ),
    .lyro_ok        ( obj_ok        ),
    .lyro_data      ( obj_data      ),

    .dim            ( 3'b0          ),
    .dimmod         ( 1'b0          ),
    .dimpol         ( 1'b0          ),

    .red            ( red_v         ),
    .green          ( green_v       ),
    .blue           ( blue_v        ),

    .ioctl_addr     ( ioctl_addr[15:0] ),
    .ioctl_ram      ( ioctl_ram     ),
    .ioctl_din      ( ioctl_din     ),
    .gfx_en         ( gfx_en        ),
    .debug_bus      ( debug_bus     ),
    .st_dout        (               )
);

/* verilator tracing_on */
jtasterix_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_6      ( cen_6         ),   // Z80 6MHz (24/4)
    .cen_fm     ( cen_fm        ),   // YM2151 4MHz (32/8)
    .cen_fm2    ( cen_fm2       ),
    .cen_pcm    ( cen_pcm       ),   // K053260 4MHz (32/8)

    .main_dout  ( snd_dout      ),
    .main_din   ( snd2main      ),
    .main_wrn   ( snd_wrn       ),
    .main_addr  ( main_addr[2:1]),
    .snd_irq    ( sndon         ),

    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),

    // 4 buses de ROM PCM (jt053260: 1 por canal, todos al mismo banco de 2MB)
    .pcma_addr  ( pcma_addr     ), .pcma_cs( pcma_cs ), .pcma_data( pcma_data ), .pcma_ok( pcma_ok ),
    .pcmb_addr  ( pcmb_addr     ), .pcmb_cs( pcmb_cs ), .pcmb_data( pcmb_data ), .pcmb_ok( pcmb_ok ),
    .pcmc_addr  ( pcmc_addr     ), .pcmc_cs( pcmc_cs ), .pcmc_data( pcmc_data ), .pcmc_ok( pcmc_ok ),
    .pcmd_addr  ( pcmd_addr     ), .pcmd_cs( pcmd_cs ), .pcmd_data( pcmd_data ), .pcmd_ok( pcmd_ok ),

    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm_l      ( pcm_l         ),
    .pcm_r      ( pcm_r         ),

    .snd_en     ( snd_en        ),
    .debug_bus  ( debug_bus     ),
    .st_dout    (               )
);

endmodule
