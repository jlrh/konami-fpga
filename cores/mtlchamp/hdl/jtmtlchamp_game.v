/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module jtmtlchamp_game(
    `include "jtframe_game_ports.inc"
);

/* verilator tracing_off */
wire        cpu_we, rmrd, vdtac, dma_bsy, snd_irq, pair_we;
wire        objsys_cs, pcu_cs, objrom_cs, objreg_cs, obj46_cs, alpha_cs,
            tilereg_cs, tilereg_b_cs, ccu_cs, vram_cs, romrd_cs, pal_cs;
wire [15:0] oram_dout, vram_dout, pal_dout, objrom_dout;
wire [ 7:0] ccu_dout, pair_dout, st_main, st_video, st_snd, st_rd;

wire [ 7:0] obj_nofin, obj_worst, obj_drcut, obj_startmax, obj_stallmax;
wire [ 8:0] hdump, vdump, vrender, vrender1;

wire [10:0] obj_list_addr;
wire [15:0] obj_list_dout;
wire [63:0] kx46_dbg;
wire [127:0] kx47_dbg;

wire        obj_dma_en    = kx46_dbg[44];
wire        obj_desc_sort = kx47_dbg[100];

wire [ 9:0] obj_scan_addr;
wire [15:0] obj_scan_even, obj_scan_odd;
wire [15:0] obj_xoffset16 = { kx46_dbg[7:0], kx46_dbg[15:8] };
wire [15:0] obj_yoffset16 = { kx46_dbg[23:16], kx46_dbg[31:24] };
wire        obj_ghf = kx46_dbg[40], obj_gvf = kx46_dbg[41];

assign ram_addr   = main_addr[15:1];

assign ram_we     = cpu_we & ram_cs;

assign debug_view = debug_bus==8'd0 ? 8'd0 :
                    debug_bus[7:6]==2'd1 ? (debug_bus[5:2]==4'd0 ? pair_dout : st_rd) :
                    debug_bus[7:6]==2'd2 ? st_snd    :

                    debug_bus[7:6]==2'd3 ? (debug_bus[5:2]==4'd1 ? obj_nofin    :
                                            debug_bus[5:2]==4'd2 ? obj_worst    :
                                            debug_bus[5:2]==4'd3 ? obj_drcut    :

                                            debug_bus[5:2]==4'd4 ? obj_startmax :
                                            debug_bus[5:2]==4'd5 ? obj_stallmax : st_video) :
                    st_main;
assign dip_flip   = 1'b0;

assign ccu_dout    =  8'd0;
assign vdtac       = 1'b1;

assign ioctl_din  = 8'd0;

/* verilator tracing_off */
mtlchamp_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .LVBL           ( LVBL          ),
    .vdump          ( vdump         ),

    .main_addr      ( main_addr     ),
    .ram_dsn        ( ram_dsn       ),
    .cpu_dout       ( ram_din       ),
    .cpu_we         ( cpu_we        ),
    .rom_cs         ( main_cs       ),
    .ram_cs         ( ram_cs        ),
    .rom_data       ( main_data     ),
    .ram_dout       ( ram_data      ),
    .rom_ok         ( main_ok       ),
    .ram_ok         ( ram_ok        ),

    .objsys_cs      ( objsys_cs     ),
    .pcu_cs         ( pcu_cs        ),
    .objrom_cs      ( objrom_cs     ),
    .objreg_cs      ( objreg_cs     ),
    .obj46_cs       ( obj46_cs      ),
    .alpha_cs       ( alpha_cs      ),
    .tilereg_cs     ( tilereg_cs    ),
    .tilereg_b_cs   ( tilereg_b_cs  ),
    .ccu_cs         ( ccu_cs        ),
    .vram_cs        ( vram_cs       ),
    .romrd_cs       ( romrd_cs      ),
    .pal_cs         ( pal_cs        ),
    .rmrd           ( rmrd          ),
    .oram_dout      ( oram_dout     ),
    .vram_dout      ( vram_dout     ),
    .pal_dout       ( pal_dout      ),
    .ccu_dout       ( ccu_dout      ),
    .objrom_dout    ( objrom_dout   ),
    .vdtac          ( vdtac         ),
    .dma_bsy        ( dma_bsy       ),
    .obj_irqen      ( obj_dma_en    ),

    .pair_we        ( pair_we       ),
    .pair_dout      ( pair_dout     ),
    .sndon          ( snd_irq       ),

    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),

    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .joystick3      ( joystick3     ),
    .joystick4      ( joystick4     ),
    .cab_1p         ( cab_1p        ),
    .coin           ( coin          ),
    .service        ( service       ),
    .dipsw          ( dipsw[3:0]    ),
    .dip_pause      ( dip_pause     ),
    .dip_test       ( dip_test      ),
    .st_dout        ( st_main       ),
    .st_rd          ( st_rd         ),
    .debug_bus      ( debug_bus     )
);

/* verilator tracing_off */
mtlchamp_sound u_sound(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .cen_8          ( cen_8         ),
    .cen_pcm        ( cen_pcm       ),

    .main_addr      ( main_addr[4:1] ),
    .main_dout      ( ram_din[7:0]  ),
    .pair_we        ( pair_we       ),
    .pair_dout      ( pair_dout     ),
    .sndon          ( snd_irq       ),

    .rom_addr       ( snd_addr      ),
    .rom_cs         ( snd_cs        ),
    .rom_data       ( snd_data      ),
    .rom_ok         ( snd_ok        ),

    .pcm_addr       ( pcm_addr      ),
    .pcm_cs         ( pcm_cs        ),
    .pcm_data       ( pcm_data      ),
    .pcm_ok         ( pcm_ok        ),

    .pcm_l          ( pcm_l         ),
    .pcm_r          ( pcm_r         ),
    .debug_bus      ( debug_bus     ),
    .st_dout        ( st_snd        )
);

/* verilator tracing_off */
mtlchamp_k055673 u_obj(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .objsys_cs      ( objsys_cs     ),
    .objreg_cs      ( objreg_cs     ),
    .obj46_cs       ( obj46_cs      ),
    .objrom_cs      ( objrom_cs     ),
    .main_addr      ( main_addr[15:1] ),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( ram_din       ),
    .cpu_we         ( cpu_we        ),
    .oram_dout      ( oram_dout     ),
    .objrom_dout    ( objrom_dout   ),
    .list_addr      ( obj_list_addr ),
    .list_dout      ( obj_list_dout ),
    .kx46_dbg       ( kx46_dbg      ),
    .kx47_dbg       ( kx47_dbg      )
);

/* verilator tracing_off */

mtlchamp_obj_dma u_obj_dma(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .dma_en         ( obj_dma_en    ),
    .desc_sort      ( obj_desc_sort ),
    .hs             ( HS            ),
    .lvbl           ( LVBL          ),
    .list_addr      ( obj_list_addr ),
    .list_din       ( obj_list_dout ),
    .dma_bsy        ( dma_bsy       ),
    .scan_addr      ( obj_scan_addr ),
    .scan_even      ( obj_scan_even ),
    .scan_odd       ( obj_scan_odd  )
);

wire [15:0] obj_scan_code;
wire [ 3:0] obj_scan_ysub;
wire        obj_scan_vflip, obj_scan_hflip;
wire [15:0] obj_fetch_code;
wire [ 3:0] obj_fetch_ysub;
wire        obj_fetch_vflip, obj_fetch_hflip;
wire        obj_fetch_start, obj_fetch_busy, obj_fetch_rowok;
wire [79:0] obj_fetch_rowpen;

wire [ 9:0] obj_hpos;
wire [11:0] obj_hzoom;
wire        obj_hz_keep;
wire [ 9:0] obj_attr;
wire [ 1:0] obj_shd;
wire        obj_dr_start, obj_dr_busy;
wire [ 9:0] obj_buf_addr;
wire        obj_buf_we;
wire [20:0] obj_buf_din;

/* verilator tracing_off */

mtlchamp_obj_scan u_obj_scan(
    .rst            ( rst               ),
    .clk            ( clk               ),
    .done           (                   ),
    .code           ( obj_scan_code     ),
    .attr           ( obj_attr          ),
    .hflip          ( obj_scan_hflip    ),
    .vflip          ( obj_scan_vflip    ),
    .hpos           ( obj_hpos          ),
    .ysub           ( obj_scan_ysub     ),
    .hzoom          ( obj_hzoom         ),
    .hz_keep        ( obj_hz_keep       ),
    .hdump          ( hdump             ),
    .vdump          ( vdump             ),

    .voffset        ( 10'd277           ),
    .hs             ( HS                ),
    .scan_even      ( obj_scan_even     ),
    .scan_odd       ( obj_scan_odd      ),
    .xoffset        ( obj_xoffset16[9:0] ),
    .yoffset        ( obj_yoffset16[9:0] ),
    .ghf            ( obj_ghf           ),
    .gvf            ( obj_gvf           ),
    .scan_addr      ( obj_scan_addr     ),
    .shd            ( obj_shd           ),
    .dr_start       ( obj_dr_start      ),
    .dr_busy        ( obj_dr_busy       ),
    .dbg_nofin      ( obj_nofin         ),
    .dbg_worst      ( obj_worst         ),
    .dbg_drcut      ( obj_drcut         ),
    .dbg_startmax   ( obj_startmax      ),
    .dbg_stallmax   ( obj_stallmax      ),
    .debug_bus      ( debug_bus         )
);

/* verilator tracing_off */

mtlchamp_obj_draw u_obj_draw(
    .rst            ( rst               ),
    .clk            ( clk               ),
    .draw           ( obj_dr_start      ),
    .busy           ( obj_dr_busy       ),
    .hpos           ( obj_hpos          ),
    .hzoom          ( obj_hzoom         ),
    .hz_keep        ( obj_hz_keep       ),
    .attr           ( obj_attr          ),
    .shd            ( obj_shd           ),

    .code           ( obj_scan_code     ),
    .ysub           ( obj_scan_ysub     ),
    .vflip          ( obj_scan_vflip    ),
    .hflip          ( obj_scan_hflip    ),
    .fetch_code     ( obj_fetch_code    ),
    .fetch_ysub     ( obj_fetch_ysub    ),
    .fetch_vflip    ( obj_fetch_vflip   ),
    .fetch_hflip    ( obj_fetch_hflip   ),
    .fetch_start    ( obj_fetch_start   ),

    .fetch_busy     ( obj_fetch_busy    ),
    .row_ok         ( obj_fetch_rowok   ),
    .row_pen        ( obj_fetch_rowpen  ),
    .buf_addr       ( obj_buf_addr      ),
    .buf_we         ( obj_buf_we        ),
    .buf_din        ( obj_buf_din       )
);

/* verilator tracing_off */

mtlchamp_obj_fetch2 u_obj_fetch(
    .rst            ( rst               ),
    .clk            ( clk               ),
    .start          ( obj_fetch_start   ),
    .busy           ( obj_fetch_busy    ),
    .envuelo        (                   ),
    .row_ok         ( obj_fetch_rowok   ),
    .code           ( obj_fetch_code    ),
    .ysub           ( obj_fetch_ysub    ),
    .vflip          ( obj_fetch_vflip   ),
    .hflip          ( obj_fetch_hflip   ),
    .row_pen        ( obj_fetch_rowpen  ),
    .obj_addr       ( obj_addr          ),
    .obj_cs         ( obj_cs            ),
    .obj_data       ( obj_data          ),
    .obj_ok         ( obj_ok            ),

    .objb_addr      ( objb_addr         ),
    .objb_cs        ( objb_cs           ),
    .objb_data      ( objb_data         ),
    .objb_ok        ( objb_ok           ),
    .objx_addr      ( objx_addr         ),
    .objx_cs        ( objx_cs           ),
    .objx_data      ( objx_data         ),
    .objx_ok        ( objx_ok           ),

    .objc_addr      ( objc_addr         ),
    .objc_cs        ( objc_cs           ),
    .objc_data      ( objc_data         ),
    .objc_ok        ( objc_ok           ),
    .objd_addr      ( objd_addr         ),
    .objd_cs        ( objd_cs           ),
    .objd_data      ( objd_data         ),
    .objd_ok        ( objd_ok           ),
    .objxb_addr     ( objxb_addr        ),
    .objxb_cs       ( objxb_cs          ),
    .objxb_data     ( objxb_data        ),
    .objxb_ok       ( objxb_ok          )
);

/* verilator tracing_off */
mtlchamp_video u_video(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),

    .lhbl           ( LHBL          ),
    .lvbl           ( LVBL          ),
    .hs             ( HS            ),
    .vs             ( VS            ),
    .hdump          ( hdump         ),
    .vdump          ( vdump         ),
    .vrender        ( vrender       ),
    .vrender1       ( vrender1      ),

    .cpu_addr       ( main_addr[12:1] ),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( ram_din       ),
    .cpu_we         ( cpu_we        ),
    .vram_cs        ( vram_cs       ),
    .tilereg_cs     ( tilereg_cs    ),
    .tilereg_b_cs   ( tilereg_b_cs  ),
    .pal_cs         ( pal_cs        ),
    .alpha_cs       ( alpha_cs      ),
    .pcu_cs         ( pcu_cs        ),
    .vram_dout      ( vram_dout     ),
    .pal_dout       ( pal_dout      ),

    .scr_addr       ( scr_addr      ),
    .scr_cs         ( scr_cs        ),
    .scr_data       ( scr_data      ),
    .scr_ok         ( scr_ok        ),
    .scrx_addr      ( scrx_addr     ),
    .scrx_cs        ( scrx_cs       ),
    .scrx_data      ( scrx_data     ),
    .scrx_ok        ( scrx_ok       ),

    .scrb_addr      ( scrb_addr     ),
    .scrb_cs        ( scrb_cs       ),
    .scrb_data      ( scrb_data     ),
    .scrb_ok        ( scrb_ok       ),
    .scrxb_addr     ( scrxb_addr    ),
    .scrxb_cs       ( scrxb_cs      ),
    .scrxb_data     ( scrxb_data    ),
    .scrxb_ok       ( scrxb_ok      ),

    .obj_buf_addr   ( obj_buf_addr  ),
    .obj_buf_we     ( obj_buf_we    ),
    .obj_buf_din    ( obj_buf_din   ),

    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),

    .gfx_en         ( gfx_en        ),
    .debug_bus      ( debug_bus     ),
    .st_dout        ( st_video      ),

    .dbg_lyrf       (               ),
    .dbg_lyra       (               ),
    .dbg_lyrb       (               ),
    .dbg_lyrc       (               ),
    .dbg_mixa       (               ),
    .dbg_mixb       (               ),
    .dbg_mixc       (               ),
    .dbg_obj_pen    (               ),
    .dbg_obj_color  (               ),
    .dbg_obj_pri    (               )
);

endmodule
