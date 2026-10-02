module jthotchase_game(
    `include "jtframe_game_ports.inc"
);

wire [13:1] mbus_addr, sbus_addr;
wire [15:0] mbus_dout, sbus_dout, pal_dout, spr_dout, road_dout, msh_dout, ssh_dout;
wire [ 7:0] psac1_dout, psac2_dout;
wire [ 1:0] pal_we, spr_we, msh_we, road_we, ssh_we;
wire        psac1_we, psac2_we, psac1_rwe, psac2_rwe;
wire [ 7:0] snd_latch, st_main;
wire        sub_rstn, sub_int, snd_on, snd_rstn, snd_ack, video_on, start_lamp;
wire [ 8:0] vdump, hdump;
wire [ 7:0] steer, accel;
wire        shift;

`ifdef HC_SCENE
wire cpu_rst = 1'b1;
wire vid_on  = 1'b1;
`else
wire cpu_rst = rst;
wire vid_on  = video_on;
`endif

assign dip_flip   = 1'b0;
assign debug_view = st_main;

wire       brake, optical;
wire [6:0] opt_cnt;
jthotchase_ctrl u_ctrl(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .LVBL       ( LVBL              ),
    .joystick1  ( joystick1[6:0]    ),
    .joyana_l1  ( joyana_l1         ),
    .joyana_r1  ( joyana_r1         ),
    .ctrl_type  ( status[25:24]     ),
    .steer_mode ( status[27:26]     ),
    .ramp_spd   ( status[29:28]     ),
    .steer      ( steer             ),
    .accel      ( accel             ),
    .brake      ( brake             ),
    .shift      ( shift             ),
    .optical    ( optical           ),
    .opt_cnt    ( opt_cnt           )
);

jthotchase_main u_main(
    .rst        ( cpu_rst       ),
    .clk        ( clk           ),
    .LVBL       ( LVBL          ),
    .vdump      ( vdump         ),
    .rom_addr   ( main_addr     ),
    .rom_cs     ( main_cs       ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    .bus_addr   ( mbus_addr     ),
    .bus_dout   ( mbus_dout     ),
    .pal_we     ( pal_we        ),
    .spr_we     ( spr_we        ),
    .sh_we      ( msh_we        ),
    .psac1_we   ( psac1_we      ),
    .psac2_we   ( psac2_we      ),
    .psac1_rwe  ( psac1_rwe     ),
    .psac2_rwe  ( psac2_rwe     ),
    .pal_dout   ( pal_dout      ),
    .spr_dout   ( spr_dout      ),
    .sh_dout    ( msh_dout      ),
    .psac1_dout ( psac1_dout    ),
    .psac2_dout ( psac2_dout    ),
    .sub_rstn   ( sub_rstn      ),
    .sub_int    ( sub_int       ),
    .snd_latch  ( snd_latch     ),
    .snd_on     ( snd_on        ),
    .snd_rstn   ( snd_rstn      ),
    .snd_ack    ( snd_ack       ),
    .video_on   ( video_on      ),
    .start_lamp ( start_lamp    ),
    .coin       ( ~coin[1:0]    ),
    .service    ( ~service      ),
    .start1     ( ~cab_1p[0]    ),
    .shift      ( shift         ),
    .brake      ( brake         ),
    .dip_test   ( ~dip_test     ),
    .accel      ( accel         ),
    .steer      ( steer         ),
    .opt_cnt    ( opt_cnt       ),
    .dipsw      ( { dipsw[15], ~optical, dipsw[13:0] } ),
    .dip_pause  ( dip_pause     ),
    .st_dout    ( st_main       )
);

jtframe_dual_ram16 #(.AW(13)) u_shared(
    .clk0(clk), .data0(mbus_dout), .addr0(mbus_addr), .we0(msh_we), .q0(msh_dout),
    .clk1(clk), .data1(sbus_dout), .addr1(sbus_addr), .we1(ssh_we), .q1(ssh_dout) );

jthotchase_sub u_sub(
    .rst        ( cpu_rst       ),
    .clk        ( clk           ),
    .sub_rstn   ( sub_rstn      ),
    .sub_int    ( sub_int       ),
    .rom_addr   ( sub_addr      ),
    .rom_cs     (               ),
    .rom_data   ( sub_data      ),
    .rom_ok     ( 1'b1          ),
    .bus_addr   ( sbus_addr     ),
    .bus_dout   ( sbus_dout     ),
    .road_we    ( road_we       ),
    .sh_we      ( ssh_we        ),
    .road_dout  ( road_dout     ),
    .sh_dout    ( ssh_dout      ),
    .dip_pause  ( dip_pause     )
);

jthotchase_sound u_sound(
    .clk        ( clk           ),
    .rst        ( cpu_rst       ),
    .cen_snd    ( cen_snd       ),
    .cen_pcm    ( cen_pcm       ),
    .snd_rstn   ( snd_rstn      ),
    .snd_on     ( snd_on        ),
    .snd_latch  ( snd_latch     ),
    .snd_ack    ( snd_ack       ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm1a_addr ( pcm1a_addr    ), .pcm1a_cs ( pcm1a_cs ), .pcm1a_data ( pcm1a_data ), .pcm1a_ok ( pcm1a_ok ),
    .pcm1b_addr ( pcm1b_addr    ), .pcm1b_cs ( pcm1b_cs ), .pcm1b_data ( pcm1b_data ), .pcm1b_ok ( pcm1b_ok ),
    .pcm2a_addr ( pcm2a_addr    ), .pcm2a_cs ( pcm2a_cs ), .pcm2a_data ( pcm2a_data ), .pcm2a_ok ( pcm2a_ok ),
    .pcm2b_addr ( pcm2b_addr    ), .pcm2b_cs ( pcm2b_cs ), .pcm2b_data ( pcm2b_data ), .pcm2b_ok ( pcm2b_ok ),
    .pcm3a_addr ( pcm3a_addr    ), .pcm3a_cs ( pcm3a_cs ), .pcm3a_data ( pcm3a_data ), .pcm3a_ok ( pcm3a_ok ),
    .pcm3b_addr ( pcm3b_addr    ), .pcm3b_cs ( pcm3b_cs ), .pcm3b_data ( pcm3b_data ), .pcm3b_ok ( pcm3b_ok ),
    .pcm1_l     ( pcm1_l        ), .pcm1_r   ( pcm1_r   ),
    .pcm2_l     ( pcm2_l        ), .pcm2_r   ( pcm2_r   ),
    .pcm3_l     ( pcm3_l        ), .pcm3_r   ( pcm3_r   )
);

jthotchase_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .pxl2_cen   ( pxl2_cen      ),
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .HS         ( HS            ),
    .VS         ( VS            ),
    .vdump      ( vdump         ),
    .hdump      ( hdump         ),
    .video_on   ( vid_on        ),
    .mbus_addr  ( mbus_addr     ),
    .mbus_dout  ( mbus_dout     ),
    .pal_we     ( pal_we        ),
    .spr_we     ( spr_we        ),
    .psac1_we   ( psac1_we      ),
    .psac2_we   ( psac2_we      ),
    .psac1_rwe  ( psac1_rwe     ),
    .psac2_rwe  ( psac2_rwe     ),
    .pal_dout   ( pal_dout      ),
    .spr_dout   ( spr_dout      ),
    .psac1_dout ( psac1_dout    ),
    .psac2_dout ( psac2_dout    ),
    .sbus_addr  ( sbus_addr[11:1] ),
    .sbus_dout  ( sbus_dout     ),
    .road_we    ( road_we       ),
    .road_dout  ( road_dout     ),
    .psac1_addr ( psac1_addr    ),
    .psac1_data ( psac1_data    ),
    .psac2_addr ( psac2_addr    ),
    .psac2_data ( psac2_data    ),
    .road_addr  ( road_addr     ),
    .road_cs    ( road_cs       ),
    .road_data  ( road_data     ),
    .road_ok    ( road_ok       ),
    .spr_addr   ( spr_addr      ),
    .spr_cs     ( spr_cs        ),
    .spr_data   ( spr_data      ),
    .spr_ok     ( spr_ok        ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    .gfx_en     ( gfx_en        ),
    .debug_bus  ( debug_bus     )
);

wire [21:0] dw_addr;
wire [ 7:0] dw_data;
jthotchase_dwnld u_dwnld(
    .prog_addr  ( prog_addr[21:0] ),
    .prog_ba    ( prog_ba       ),
    .prog_data  ( prog_data     ),
    .post_addr  ( dw_addr       ),
    .post_data  ( dw_data       )
);
always @* begin post_addr = dw_addr; post_data = dw_data; end

endmodule
