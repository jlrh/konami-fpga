module jtkonamigt_game(
    `include "jtframe_game_ports.inc"
);

localparam [7:0] VOL_PROMS = 8'd104,
                 VOL_AY1   = 8'd138,
                 VOL_AY2   = 8'd102;

wire        cen9, cen6, cen6b, clk6, cen12, cen3p5, cen1p7, cen_audio_clk_div;
wire        hflip, vflip;
wire        chacs_n, objram_n, vcs2, vcs1, vzcs;
wire        video_1h_n, video_2h, video_256v;
wire [15:1] video_addr;
wire [ 7:0] sound_din;
wire [15:0] video_din, video_dout;
wire        main_lds_n, main_uds_n, main_rw_n, sound_on_n, data_n;
wire [10:0] pal_addr;
wire [ 4:0] red5, green5, blue5, red5_blk, green5_blk, blue5_blk;
wire [14:0] rgb_blk;
wire        preLHBL, preLVBL, preLVBL_n;
wire        main_cs_pre, snd_cs_pre;
wire [16:0] main_addr_pre;
wire [ 7:0] wav1_vol_addr, wav2_vol_addr, wav1_vol_data, wav2_vol_data;
wire [15:0] snd_u;
wire [15:0] wheel_word;
wire        shift;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
assign pxl_cen    = cen6;
assign pxl2_cen   = cen12;

gx400_cen u_cen(
    .i_clk               ( clk               ),
    .i_vsync60           ( 1'b0              ),
    .o_cen12             ( cen12             ),
    .o_cen6              ( cen6              ),
    .o_cen6b             ( cen6b             ),
    .o_clk6              ( clk6              ),
    .o_cen9              ( cen9              ),
    .o_cen3p5            ( cen3p5            ),
    .o_cen1p7            ( cen1p7            ),
    .o_cen_audio_clk_div ( cen_audio_clk_div )
);

reg cpu_start;
always @(posedge clk, posedge rst) begin
    if( rst ) cpu_start <= 0;
    else if( snd_ok | main_ok ) cpu_start <= 1;
end

assign main_cs   = main_cs_pre | ~cpu_start;
assign main_addr = main_addr_pre;
assign snd_cs    = snd_cs_pre  | ~cpu_start;

konamigt_wheel u_wheel(
    .rst          ( rst              ),
    .clk          ( clk              ),
    .LVBL         ( LVBL             ),
    .joystick1    ( joystick1[6:0]   ),
    .joyana_l1    ( joyana_l1        ),
    .joyana_r1    ( joyana_r1        ),
    .dial         ( dial_x           ),
    .spin_en      ( status[30]       ),
    .ctrl_type    ( status[25:24]    ),
    .steer_mode   ( status[27:26]    ),
    .ramp_spd     ( status[29:28]    ),
    .wheel_word   ( wheel_word       ),
    .shift        ( shift            )
);

wire [7:0] in0 = { 5'd0, ~service, ~coin[1], ~coin[0] };

wire [7:0] in1 = { 3'd0, shift, 4'd0 };

wire [7:0] dsw3 = { dipsw[23:19], dipsw[18] & dip_test, dipsw[17:16] };

konamigt_main u_main(
    .i_clk          ( clk             ),
    .i_rst          ( rst             ),
    .i_cen9         ( cen9            ),
    .i_vblank       ( preLVBL_n       ),
    .i_256v         ( video_256v      ),
    .i_blk          (                 ),
    .i_cen6         ( cen6            ),
    .i_clk6         ( clk6            ),
    .i_1h_n         ( video_1h_n      ),
    .i_2h           ( video_2h        ),
    .i_vsinc        (                 ),
    .i_sync         (                 ),
    .o_chacs_n      ( chacs_n         ),
    .o_rw_n         ( main_rw_n       ),
    .o_uds_n        ( main_uds_n      ),
    .o_lds_n        ( main_lds_n      ),
    .o_inter_non    (                 ),
    .o_288_256      (                 ),
    .o_vflip        ( vflip           ),
    .o_hflip        ( hflip           ),
    .o_objram_n     ( objram_n        ),
    .o_vcs2         ( vcs2            ),
    .o_vcs1         ( vcs1            ),
    .o_vzcs         ( vzcs            ),
    .o_rom_cs       ( main_cs_pre     ),
    .o_rom_addr     ( main_addr_pre   ),
    .i_rom_data     ( main_data       ),
    .i_rom_ok       ( main_ok         ),
    .o_sound_on_n   ( sound_on_n      ),
    .o_data_n       ( data_n          ),
    .o_sound_db     ( sound_din       ),
    .o_addr         ( video_addr      ),
    .i_cd           ( pal_addr        ),
    .i_data_bus_in  ( video_dout      ),
    .o_data_bus_out ( video_din       ),
    .o_red          ( red5            ),
    .o_green        ( green5          ),
    .o_blue         ( blue5           ),

    .i_dip1         ( dipsw[ 7: 0]    ),
    .i_dip2         ( dipsw[15: 8]    ),
    .i_dip3         ( dsw3            ),
    .i_pause        ( dip_pause       ),
    .i_in0          ( in0             ),
    .i_in1          ( in1             ),
    .i_in2          ( 8'd0            ),
    .i_wheel        ( wheel_word      )
);

jtframe_blank #( .DLY(0), .DW(15) ) u_blank(
    .clk      ( clk                     ),
    .pxl_cen  ( cen6                    ),
    .preLHBL  ( preLHBL                 ),
    .preLVBL  ( preLVBL                 ),
    .LHBL     ( LHBL                    ),
    .LVBL     ( LVBL                    ),
    .preLBL   (                         ),
    .rgb_in   ( { red5, green5, blue5 } ),
    .rgb_out  ( rgb_blk                 )
);
assign { red5_blk, green5_blk, blue5_blk } = rgb_blk;

konamigt_colmix u_colmix(
    .clk       ( clk        ),
    .in_red    ( red5_blk   ),
    .in_green  ( green5_blk ),
    .in_blue   ( blue5_blk  ),
    .out_red   ( red        ),
    .out_green ( green      ),
    .out_blue  ( blue       )
);

assign preLVBL = ~preLVBL_n;

GX400A_VIDEO u_video(
    .i_MCLK         ( clk          ),
    .i_RESET        ( rst          ),
    .i_HFLIP        ( hflip        ),
    .i_VFLIP        ( vflip        ),
    .i_INTER_NON    ( 1'b0         ),
    .i_288_256      ( 1'b0         ),
    .i_cen6         ( cen6         ),
    .i_cen6b        ( cen6b        ),
    .i_clk6         ( clk6         ),
    .o_HS           ( HS           ),
    .o_VS           ( VS           ),
    .o_HBL          ( preLHBL      ),
    .o_VBL          ( preLVBL_n    ),
    .o_1h_n         ( video_1h_n   ),
    .o_2h           ( video_2h     ),
    .o_256v         ( video_256v   ),
    .i_addr         ( video_addr   ),
    .i_data_bus_in  ( video_din    ),
    .o_data_bus_out ( video_dout   ),
    .i_uds_n        ( main_uds_n   ),
    .i_lds_n        ( main_lds_n   ),
    .i_RnW          ( main_rw_n    ),
    .i_chacs_n      ( chacs_n      ),
    .i_objram_n     ( objram_n     ),
    .i_vcs1         ( vcs1         ),
    .i_vcs2         ( vcs2         ),
    .i_vzcs         ( vzcs         ),
    .o_pal_addr     ( pal_addr     )
);

`ifndef NOSOUND
konamigt_wavvol u_wav1_vol( .clk( clk ), .addr( wav1_vol_addr ), .q( wav1_vol_data ) );
konamigt_wavvol u_wav2_vol( .clk( clk ), .addr( wav2_vol_addr ), .q( wav2_vol_data ) );

nemesis_sound u_sound(
    .i_clk            ( clk               ),
    .i_cen3p5         ( cen3p5            ),
    .i_cen1p7         ( cen1p7            ),
    .i_cen_clk_div    ( cen_audio_clk_div ),
    .i_rst            ( rst               ),
    .i_main_db        ( sound_din         ),
    .i_data_n         ( data_n            ),
    .i_sound_on_n     ( sound_on_n        ),
    .i_cpu_start      ( cpu_start         ),
    .o_z80_cs         ( snd_cs_pre        ),
    .o_z80_addr       ( snd_addr          ),
    .i_z80_data       ( snd_data          ),
    .i_z80_ok         ( snd_ok            ),
    .o_wav1_addr      ( wav1_addr         ),
    .o_wav1_vol_addr  ( wav1_vol_addr     ),
    .o_wav2_addr      ( wav2_addr         ),
    .o_wav2_vol_addr  ( wav2_vol_addr     ),
    .i_wav1_data      ( wav1_data         ),
    .i_wav1_vol_data  ( wav1_vol_data     ),
    .i_wav2_data      ( wav2_data         ),
    .i_wav2_vol_data  ( wav2_vol_data     ),
    .o_sound          ( snd_u             ),
    .i_prom1_on       ( 1'b1              ),
    .i_prom2_on       ( 1'b1              ),
    .i_ay7_on         ( 1'b1              ),
    .i_ay8_on         ( 1'b1              ),
    .i_vol_prom       ( VOL_PROMS         ),
    .i_vol_ay7        ( VOL_AY2           ),
    .i_vol_ay8        ( VOL_AY1           )
);

wire signed [16:0] snd_dc;
jt49_dcrm2 #(.sw(17)) u_dcrm(
    .clk    ( clk               ),
    .cen    ( cen_audio_clk_div ),
    .rst    ( rst               ),
    .din    ( { 1'b0, snd_u }   ),
    .dout   ( snd_dc            )
);
assign snd    = snd_dc > 17'sd32767 ? 16'h7fff : snd_dc < -17'sd32768 ? 16'h8000 : snd_dc[15:0];
assign sample = cen_audio_clk_div;
`else
assign snd_cs_pre = 0;
assign snd_addr   = 0;
assign wav1_addr  = 0;
assign wav2_addr  = 0;
assign snd        = 0;
assign sample     = 0;
`endif

endmodule
