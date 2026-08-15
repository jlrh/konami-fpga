/*  ssriders — top del core, contrato jtframe.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module jtssriders_game(
    `include "jtframe_game_ports.inc"
);

/* verilator tracing_off */
wire        rom_cs, oram_cs, objreg_cs, pal_cs, tile_cs,
            pcu_cs, prot_cs, watchdog_cs, ram1c05_cs,
            sndirq, snd_wrn, cpu_we, vdtac, dma_bsy, tile_irqn, flip, rst8;
wire [15:0] cpu_dout, oram_dout, objreg_dout, pal_dout, tile_dout;
wire [ 2:0] dim_v;
wire [ 1:0] dim_c;
wire        rmrd, objtest_bank;
wire [ 7:0] snd_dout, snd2main, st_main, st_video;
wire [22:2] lyro_addr_v;
wire [ 7:0] red_v, green_v, blue_v;
wire [13:1] oram_addr;
wire [ 1:0] oram_we;
wire [15:0] ram1c05_dout;
wire [ 1:0] ram1c05_we;

wire        oram_cs_v;
wire [15:0] oram_din;
wire        prot_brn, prot_bgackn, prot_bgn;
wire [15:0] prot_dout;

assign debug_view = debug_bus[6] ? st_video : st_main;

assign ram_addr = main_addr[13:1];
assign ram_we   = cpu_we & ram_cs;
assign ram_din  = cpu_dout;

assign obj_addr = lyro_addr_v[20:2];

assign red   = red_v  [7:3];
assign green = green_v[7:3];
assign blue  = blue_v [7:3];

assign ram1c05_we = {2{ram1c05_cs & cpu_we}} & ~ram_dsn;

jtframe_ram16 #(.AW(6)) u_ram1c05(
    .clk    ( clk               ),
    .data   ( cpu_dout          ),
    .addr   ( main_addr[6:1]    ),
    .we     ( ram1c05_we        ),
    .q      ( ram1c05_dout      )
);

/* verilator tracing_off */
ssriders_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .LVBL           ( LVBL          ),

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
    .objreg_cs      ( objreg_cs     ),
    .pal_cs         ( pal_cs        ),
    .tile_cs        ( tile_cs       ),
    .pcu_cs         ( pcu_cs        ),
    .prot_cs        ( prot_cs       ),
    .watchdog_cs    ( watchdog_cs   ),
    .ram1c05_cs     ( ram1c05_cs    ),

    .prot_brn       ( prot_brn      ),
    .prot_bgackn    ( prot_bgackn   ),
    .BGn            ( prot_bgn      ),
    .prot_dout      ( prot_dout     ),

    .snd_wrn        ( snd_wrn       ),
    .snd_dout       ( snd_dout      ),
    .snd2main       ( snd2main      ),
    .sndirq         ( sndirq        ),

    .oram_dout      ( oram_dout     ),
    .objreg_dout    ( oram_dout     ),
    .tile_dout      ( tile_dout     ),
    .ram1c05_dout   ( ram1c05_dout  ),
    .pal_dout       ( pal_dout      ),
    .vdtac          ( vdtac         ),

    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),

    .rmrd           ( rmrd          ),
    .dim_v          ( dim_v         ),
    .dim_c          ( dim_c         ),
    .objtest_bank   ( objtest_bank  ),

    .tile_irqn      ( tile_irqn     ),

    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .joystick3      ( joystick3     ),
    .joystick4      ( joystick4     ),
    .cab_1p         ( cab_1p        ),
    .coin           ( coin          ),
    .service        ( {4{service}}  ),
    .dip_pause      ( dip_pause     ),
    .dip_test       ( dip_test      ),
    .st_dout        ( st_main       ),
    .debug_bus      ( debug_bus     )
);

/* verilator tracing_off */

ssriders_prot u_prot(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_16     ( cen_16        ),
    .cen_8      ( cen_8         ),

    .cs         ( prot_cs       ),
    .addr       ( main_addr[13:1] ),
    .dsn        ( ram_dsn       ),
    .din        ( cpu_dout      ),
    .dout       ( prot_dout     ),
    .cpu_we     ( cpu_we        ),

    .ram_we     ( ram_we        ),

    .objsys_cs  ( oram_cs       ),
    .oram_cs    ( oram_cs_v     ),
    .oram_addr  ( oram_addr     ),
    .oram_din   ( oram_din      ),
    .oram_dout  ( oram_dout     ),
    .oram_we    ( oram_we       ),

    .irqn       (               ),
    .BRn        ( prot_brn      ),
    .BGn        ( prot_bgn      ),
    .BGACKn     ( prot_bgackn   ),

    .debug_bus  ( debug_bus     )
);

wire [3:0] gfx_en_eff = gfx_en;

/* verilator tracing_on */
ssriders_video u_video(
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
    .oram_din       ( oram_din      ),

    .cpu_addr       ( main_addr[16:1]),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),

    .pcu_cs         ( pcu_cs        ),
    .alpha_cs       ( 1'b0          ),
    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),
    .tile_dout      ( tile_dout     ),

    .dma_bsy        ( dma_bsy       ),
    .objsys_dout    ( oram_dout     ),
    .objsys_cs      ( oram_cs_v     ),
    .objreg_cs      ( objreg_cs     ),

    .objreg_byte    ( 1'b1          ),
    .objcha_n       ( 1'b1          ),

    .vdtac          ( vdtac         ),
    .tile_cs        ( tile_cs       ),
    .rst8           ( rst8          ),

    .rmrd           ( rmrd          ),

    .objdx          ( 9'd18         ),
    .objdy          ( 10'd0         ),
    .flip           ( flip          ),

    .lyrf_addr      ( lyrf_addr     ),
    .lyra_addr      ( lyra_addr     ),
    .lyrb_addr      ( lyrb_addr     ),
    .lyrf_cs        ( lyrf_cs       ),
    .lyra_cs        ( lyra_cs       ),
    .lyrb_cs        ( lyrb_cs       ),
    .lyrf_data      ( lyrf_data     ),
    .lyra_data      ( lyra_data     ),
    .lyrb_data      ( lyrb_data     ),
    .lyrf_ok        ( lyrf_ok       ),
    .lyra_ok        ( lyra_ok       ),
    .lyrb_ok        ( lyrb_ok       ),

    .lyro_addr      ( lyro_addr_v   ),
    .lyro_cs        ( obj_cs        ),
    .lyro_ok        ( obj_ok        ),
    .lyro_data      ( obj_data      ),

    .dim            ( dim_v         ),
    .dimmod         ( dim_c[0]      ),
    .dimpol         ( dim_c[1]      ),

    .red            ( red_v         ),
    .green          ( green_v       ),
    .blue           ( blue_v        ),

    .ioctl_addr     ( ioctl_addr[15:0] ),
    .ioctl_ram      ( ioctl_ram     ),
    .ioctl_din      ( ioctl_din     ),
    .gfx_en         ( gfx_en_eff    ),
    .debug_bus      ( debug_bus     ),
    .st_dout        ( st_video      )
);

/* verilator tracing_on */
ssriders_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_8      ( cen_8         ),
    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .cen_pcm    ( cen_pcm       ),

    .main_dout  ( snd_dout      ),
    .main_din   ( snd2main      ),
    .main_wrn   ( snd_wrn       ),
    .main_addr  ( main_addr[2:1]),
    .snd_irq    ( sndirq        ),

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
