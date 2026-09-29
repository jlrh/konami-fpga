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
wire [20:2] scr_addr_v;
wire [22:2] lyro_addr_v;
wire [ 7:0] red_v, green_v, blue_v;
wire [13:1] oram_addr;
wire [ 1:0] oram_we;
wire        eram_cs;
wire [15:0] eram_dout;
wire [ 1:0] eram_we;

assign debug_view = st_main;

assign ram_addr = main_addr[14:1];
assign ram_we   = cpu_we & ram_cs;
assign ram_din  = cpu_dout;

assign scr_addr = scr_addr_v[19:2];
assign obj_addr = lyro_addr_v[21:2];

assign red   = red_v  [7:3];
assign green = green_v[7:3];
assign blue  = blue_v [7:3];

assign oram_we   = {2{oram_cs & cpu_we}} & ~ram_dsn;
assign oram_addr = main_addr[13:1];

assign eram_we   = {2{eram_cs & cpu_we}} & ~ram_dsn;

jtframe_ram16 #(.AW(10)) u_eram(
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
    .irq_en         ( 1'b1          ),

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

    .snd_wrn        ( snd_wrn       ),
    .snd_dout       ( snd_dout      ),
    .snd2main       ( snd2main      ),
    .sndon          ( sndon         ),

    .oram_dout      ( oram_dout     ),
    .eram_dout      ( eram_dout     ),
    .objreg_dout    ( oram_dout     ),
    .vram_dout      ( vram_dout     ),
    .pal_dout       ( pal_dout      ),
    .vdtac          ( vdtac         ),

    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),

    .tilebank       ( tilebank      ),
    .spritebank     ( spritebank    ),

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

    .oram_addr      ( oram_addr     ),
    .oram_we        ( oram_we       ),

    .cpu_addr       ( main_addr[16:1]),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),

    .pcu_cs         ( pcu_cs        ),
    .alpha_cs       ( 1'b0          ),
    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),
    .tilesys_dout   ( vram_dout     ),

    .dma_bsy        ( dma_bsy       ),
    .objsys_dout    ( oram_dout     ),
    .objsys_cs      ( oram_cs       ),
    .objreg_cs      ( objreg_cs     ),
    .objreg_byte    ( objreg_byte   ),
    .objcha_n       ( 1'b1          ),

    .vdtac          ( vdtac         ),
    .tilesys_cs     ( vram_cs       ),

    .tilereg_cs     ( tilereg_cs    ),
    .rst8           ( rst8          ),

    .rmrd           ( romrd_cs      ),
    .tilebank       ( tilebank      ),
    .spritebank     ( spritebank    ),
    .objdx          ( 9'd124        ),
    .objdy          ( 10'h3ff       ),
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
    .cen_6      ( cen_6         ),
    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .cen_pcm    ( cen_pcm       ),

    .main_dout  ( snd_dout      ),
    .main_din   ( snd2main      ),
    .main_wrn   ( snd_wrn       ),
    .main_addr  ( main_addr[2:1]),
    .snd_irq    ( sndon         ),

    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),

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
