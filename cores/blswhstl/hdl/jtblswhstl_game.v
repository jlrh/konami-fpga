module jtblswhstl_game(
    `include "jtframe_game_ports.inc"
);

wire        rom_cs, oram_cs, objreg_cs, pal_cs, tile_cs,
            pcu_cs, k054000_cs, watchdog_cs,
            sndirq, snd_wrn, cpu_we, vdtac, dma_bsy, tile_irqn, flip, rst8;
wire [15:0] cpu_dout, oram_dout, objreg_dout, pal_dout, tile_dout;
wire        rmrd, rombank;
wire [ 7:0] k054000_dout;
wire [ 7:0] snd_dout, snd2main, st_main, st_video;
wire [22:2] lyro_addr_v;
wire [ 7:0] red_v, green_v, blue_v;
wire [13:1] oram_addr;
wire [ 1:0] oram_we;
wire [15:0] oram_din;

assign ram_addr = main_addr[13:1];
assign ram_we   = cpu_we & ram_cs;
assign ram_din  = cpu_dout;

assign obj_addr = lyro_addr_v[19:2];

assign red   = red_v  [7:3];
assign green = green_v[7:3];
assign blue  = blue_v [7:3];

function [13:1] conv13( input [13:1] a );
    conv13 = { a[6:5], a[1], a[13:7], a[4:2] };
endfunction
assign oram_addr = conv13( main_addr[13:1] );
assign oram_we   = {2{oram_cs & cpu_we}} & ~ram_dsn;
assign oram_din  = cpu_dout;

jtk054000 u_k054000(
    .rst    ( rst               ),
    .clk    ( clk               ),
    .cs     ( k054000_cs        ),
    .addr   ( main_addr[5:1]    ),
    .we     ( cpu_we & ~ram_dsn[0] ),
    .din    ( cpu_dout[7:0]     ),
    .dout   ( k054000_dout      )
);

assign debug_view = debug_bus[6] ? st_video : st_main;

wire [3:0] gfx_en_eff = gfx_en;

blswhstl_main u_main(
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
    .k054000_cs     ( k054000_cs    ),
    .watchdog_cs    ( watchdog_cs   ),

    .snd_wrn        ( snd_wrn       ),
    .snd_dout       ( snd_dout      ),
    .snd2main       ( snd2main      ),
    .sndirq         ( sndirq        ),

    .oram_dout      ( oram_dout     ),
    .objreg_dout    ( oram_dout     ),
    .tile_dout      ( tile_dout     ),
    .k054000_dout   ( k054000_dout  ),
    .pal_dout       ( pal_dout      ),
    .vdtac          ( vdtac         ),

    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),

    .rmrd           ( rmrd          ),
    .tile_rombank   ( rombank       ),

    .tile_irqn      ( tile_irqn     ),

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

blswhstl_video u_video(
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
    .objsys_cs      ( oram_cs       ),
    .objreg_cs      ( objreg_cs     ),

    .objreg_byte    ( 1'b1          ),
    .objcha_n       ( 1'b1          ),

    .vdtac          ( vdtac         ),
    .tile_cs        ( tile_cs       ),
    .rst8           ( rst8          ),

    .rmrd           ( rmrd          ),
    .rombank        ( rombank       ),

    .objdx          ( 9'd2          ),
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

blswhstl_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),

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

    .pcm_l      ( pcm_r         ),
    .pcm_r      ( pcm_l         ),

    .snd_en     ( snd_en        ),
    .debug_bus  ( debug_bus     ),
    .st_dout    (               )
);

endmodule
