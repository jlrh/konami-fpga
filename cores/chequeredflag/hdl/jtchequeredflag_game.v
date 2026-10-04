/*  This file is part of the Chequered Flag core for MiSTer.
    GPLv3. Estructura adaptada de jtajax_game.v (jotego, GPLv3). */

module jtchequeredflag_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] cpu_addr;
wire [ 7:0] cpu_dout, obj_dout, psac1_dout, psac2_dout, pal_dout, vreg, snd_latch, snd_latch2;
wire        vid_ovr, cpu_cen, cpu_we, irq_n, nmi_n, snd_irq, readroms, vid_ok, start_lamp,
            obj_cs, vr1_cs, vr2_cs, pal_cs, psac1_io, psac2_io;
wire [ 7:0] wheel, pedal;
wire        brake, shift_hi;

assign ram_din    = cpu_dout;

`ifdef SIMULATION
assign debug_view = { vid_ovr, vreg[6:0] };
`else
assign debug_view = 8'd0;
`endif

ff_drivectrl #(
    .CENTER     ( 8'h7F ),
    .LIM        ( 8'h1E ),
    .ANA_MUL    ( 8'd33 ),
    .ANA_DZ     ( 8'd4  ),
    .STEP_UNIT  ( 8'd1  ),
    .GAS_REST   ( 8'h3C ),
    .GAS_FULL   ( 8'h90 ),
    .GAS_DZ     ( 8'd8  ),
    .BRK_TH     ( 8'h40 ),
    .BOOT_FRAMES( 10'd0 )
) u_drive(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .LVBL       ( LVBL          ),
    .joystick1  ( joystick1[6:0] ),
    .joyana_l1  ( joyana_l1     ),
    .joyana_r1  ( joyana_r1     ),
    .ctrl_type  ( status[25:24] ),
    .steer_mode ( status[27:26]==2'd3 ? 2'd0 : status[27:26] ),
    .ramp_spd   ( status[29:28] ),
    .steer      ( wheel         ),
    .accel      ( pedal         ),
    .brake      ( brake         ),
    .brk_mag    (               ),
    .shift      ( shift_hi      ),
    .optical    (               ),
    .opt_cnt    (               )
);

jtchequeredflag_main u_main(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_ref    ( cen24         ),
    .cpu_cen    ( cpu_cen       ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_we     ( cpu_we        ),
    .cpu_addr   ( cpu_addr      ),
    .rom_addr   ( main_addr     ),
    .rom_data   ( main_data     ),
    .rom_cs     ( main_cs       ),
    .rom_ok     ( main_ok       ),
    .ram_addr   ( ram_addr      ),
    .ram_we     ( ram_we        ),
    .ram_dout   ( ram_dout      ),
    .irq_n      ( irq_n         ),
    .nmi_n      ( nmi_n         ),
    .obj_cs     ( obj_cs        ),
    .vr1_cs     ( vr1_cs        ),
    .vr2_cs     ( vr2_cs        ),
    .pal_cs     ( pal_cs        ),
    .psac1_io   ( psac1_io      ),
    .psac2_io   ( psac2_io      ),
    .obj_dout   ( obj_dout      ),
    .psac1_dout ( psac1_dout    ),
    .psac2_dout ( psac2_dout    ),
    .pal_dout   ( pal_dout      ),
    .vid_ok     ( vid_ok        ),
    .readroms   ( readroms      ),
    .vreg       ( vreg          ),
    .snd_latch  ( snd_latch     ),
    .snd_latch2 ( snd_latch2    ),
    .snd_irq    ( snd_irq       ),
    .cab_1p     ( cab_1p        ),
    .coin       ( coin          ),
    .service    ( service       ),
    .dip_test   ( dip_test      ),
    .brake      ( brake         ),
    .shift_hi   ( shift_hi      ),
    .wheel      ( wheel         ),
    .pedal      ( pedal         ),
    .start_lamp ( start_lamp    ),
    .dipsw      ( dipsw[19:0]   ),
    .dip_pause  ( dip_pause     )
);

jtchequeredflag_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .snd_latch  ( snd_latch     ),
    .snd_latch2 ( snd_latch2    ),
    .snd_irq    ( snd_irq       ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcma_addr  ( pcma_addr     ),
    .pcmb_addr  ( pcmb_addr     ),
    .pcma_dout  ( pcma_data     ),
    .pcmb_dout  ( pcmb_data     ),
    .pcma_cs    ( pcma_cs       ),
    .pcmb_cs    ( pcmb_cs       ),
    .pcma_ok    ( pcma_ok       ),
    .pcmb_ok    ( pcmb_ok       ),
    .pcm2a_addr ( pcm2a_addr    ),
    .pcm2b_addr ( pcm2b_addr    ),
    .pcm2a_dout ( pcm2a_data    ),
    .pcm2b_dout ( pcm2b_data    ),
    .pcm2a_cs   ( pcm2a_cs      ),
    .pcm2b_cs   ( pcm2b_cs      ),
    .pcm2a_ok   ( pcm2a_ok      ),
    .pcm2b_ok   ( pcm2b_ok      ),
    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm1_l     ( pcm1_l        ),
    .pcm1_r     ( pcm1_r        ),
    .pcm2_l     ( pcm2_l        ),
    .pcm2_r     ( pcm2_r        ),
    .debug_bus  ( debug_bus     )
);

jtchequeredflag_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .pxl2_cen   ( pxl2_cen      ),
    .cen24      ( cen24         ),
    .flip       ( dip_flip      ),
    .lhbl       ( LHBL          ),
    .lvbl       ( LVBL          ),
    .hs         ( HS            ),
    .vs         ( VS            ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_we     ( cpu_we        ),
    .obj_cs     ( obj_cs        ),
    .vr1_cs     ( vr1_cs        ),
    .vr2_cs     ( vr2_cs        ),
    .pal_cs     ( pal_cs        ),
    .psac1_io   ( psac1_io      ),
    .psac2_io   ( psac2_io      ),
    .readroms   ( readroms      ),
    .vreg       ( vreg          ),
    .obj_dout   ( obj_dout      ),
    .psac1_dout ( psac1_dout    ),
    .psac2_dout ( psac2_dout    ),
    .pal_dout   ( pal_dout      ),
    .vid_ok     ( vid_ok        ),
    .irq_n      ( irq_n         ),
    .nmi_n      ( nmi_n         ),
    .lyro_addr  ( lyro_addr     ),
    .lyro_cs    ( lyro_cs       ),
    .lyro_ok    ( lyro_ok       ),
    .lyro_data  ( lyro_data     ),
    .psac2a_addr( psac2a_addr   ),
    .psac2a_cs  ( psac2a_cs     ),
    .psac2a_ok  ( psac2a_ok     ),
    .psac2a_data( psac2a_data   ),
    .psac2b_addr( psac2b_addr   ),
    .psac2b_cs  ( psac2b_cs     ),
    .psac2b_ok  ( psac2b_ok     ),
    .psac2b_data( psac2b_data   ),
    .psac1_addr ( psac1_addr    ),
    .psac1_data ( psac1_data    ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    .gfx_en     ( gfx_en        ),
    .debug_bus  ( debug_bus     ),
    .ovr        ( vid_ovr       )
);

endmodule
