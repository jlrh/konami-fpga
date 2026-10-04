/*

FPGA compatible core of arcade hardware by LMN-san, OScherler, Raki.

This core is available for hardware compatible with MiSTer.
Other FPGA systems may be supported by the time you read this.
This work is not mantained by the MiSTer project. Please contact the
core authors for issues and updates.

(c) LMN-san, OScherler, Raki 2020–2023.

Support the authors:

       Raki: https://www.patreon.com/ikamusume
    LMN-san: https://ko-fi.com/lmnsan
  OScherler: https://ko-fi.com/oscherler

The authors do not endorse or participate in illegal distribution
of copyrighted material. This work can be used with legally
obtained ROM dumps of games or with homebrew software for
the arcade platform.

This file license is GNU GPLv3.
You can read the whole license file at http://www.gnu.org/licenses/

*/

`default_nettype none
`timescale 1ns/1ps

module GX400A_VIDEO
(
	input               i_MCLK,
	input               i_RESET,

	input               i_cen6,
	input               i_cen6b,
	input               i_clk6,

	input               i_HFLIP,
	input               i_VFLIP,
	input               i_INTER_NON,
	input               i_288_256,

	output              o_HS,
	output              o_VS,
	output              o_HBL,
	output              o_VBL,

	output     [10:0]   o_pal_addr,

	output              o_1h_n,
	output              o_2h,
	output              o_256v,

	input      [15:1]   i_addr,
	input      [15:0]   i_data_bus_in,
	output reg [15:0]   o_data_bus_out,

	input               i_uds_n,
	input               i_lds_n,
	input               i_RnW,
	input               i_chacs_n,
	input               i_objram_n,
	input               i_vcs1,
	input               i_vcs2,
	input               i_vzcs
);

`ifndef NOVIDEO

wire          w_clk_6MHz;

wire          w_VBL_n, w_VBL_xx_n, w_HBL_n, w_HS_n, w_VS_n, w_BLK;

wire          w_256h, w_128h, w_64h, w_32h, w_16h, w_8h, w_4h, w_2h, w_1h, w_1h_n;
wire          w_128h_x, w_64h_x, w_32h_x, w_16h_x, w_8h_x, w_4h_x, w_2h_x, w_1h_x;
wire          vclk, w_256v, w_128v, w_64v, w_32v, w_16v, w_8v, w_4v, w_2v, w_1v;
wire          w_128v_x, w_64v_x, w_32v_x, w_16v_x, w_8v_x, w_4v_x, w_2v_x, w_1v_x;
wire          w_128ha, w_1hf, w_256h_n, w_256h_x;

wire          chacs1, chacs2;

wire [7:0]    scroll_ram_cpu_dout, scroll_ram_gfx_dout,
              objram_cpu_dout, objram_gfx_dout,
              video_ram1_lo_cpu_dout, video_ram1_lo_gfx_dout,
              video_ram1_hi_cpu_dout, video_ram1_hi_gfx_dout,
              video_ram2_cpu_dout, video_ram2_gfx_dout,
              charram_1_lo_cpu_dout, charram_1_lo_gfx_dout,
              charram_1_hi_cpu_dout, charram_1_hi_gfx_dout,
              charram_2_lo_cpu_dout, charram_2_lo_gfx_dout,
              charram_2_hi_cpu_dout, charram_2_hi_gfx_dout;

reg  [10:0]   scrollram_gfx_addr;
wire [10:0]   objram_gfx_addr;
wire [11:0]   vram_gfx_addr;
wire [ 2:0]   tile_va;
wire          tile_shift_a1, tile_shift_a2, tile_shift_b, vhff, vvff;

wire [15:2]   charram_gfx_addr, vca, oca;
wire [ 3:0]   tile_pr;
wire [ 6:0]   tile_color;

wire          dma_n, orinc, obj_wr, obj_clr, cha_ov, wrtime2,
              xa7, xb7, obj_pixel_latch, oc_latch, obj_xpos_d0, obj_latch_a_d2;
wire [ 7:0]   obj_cntr, obj_buff_a_din, obj_buff_a_dout, obj_buff_b_din, obj_buff_b_dout;
wire [15:0]   obj_buff_a_addr, obj_buff_b_addr;
wire [ 2:0]   ora;

wire cen6, cen6b, clk6;
reg  cen6_dly, cen6_dly2;

assign cen6  = i_cen6;
assign cen6b = i_cen6b;
assign clk6  = i_clk6;

always @( posedge i_MCLK ) begin
	cen6_dly  <= cen6;
	cen6_dly2 <= cen6_dly;
end

assign w_clk_6MHz = cen6;

assign o_HS = ~w_HS_n;
assign o_VS = ~w_VS_n;

assign o_HBL = w_BLK;
assign o_VBL = ~w_VBL_n;

wire CSYNC_n;

wire orinc_mod;

assign orinc_mod = orinc & ~&obj_cntr[7:4];

K005292 u_5292(
	.i_MCLK        ( i_MCLK     ),
	.i_CEN6        ( w_clk_6MHz ),
	.i_RST_n       ( ~i_RESET   ),

	.i_VFLP        ( i_VFLIP    ),
	.i_HFLP        ( i_HFLIP    ),
	.i_INTER       ( 1'b0       ),
	.i_288_256     ( 1'b0       ),

	.i_DMA_n       ( dma_n      ),
	.i_ORINC       ( orinc_mod  ),

	.o_VBLANK_xx_n ( w_VBL_xx_n ),
	.o_VBLANK_n    ( w_VBL_n    ),
	.o_HBLANK_n    ( w_HBL_n    ),
	.o_CSYNC_n     ( CSYNC_n    ),
	.o_VSYNC_n     ( w_VS_n     ),

	.o_256H_1H     ( { w_256h,   w_128h,  w_64h,   w_32h,   w_16h,  w_8h,   w_4h,   w_2h,   w_1h } ),
	.o_128H_1H_x   ( { w_128h_x, w_64h_x, w_32h_x, w_16h_x, w_8h_x, w_4h_x, w_2h_x, w_1h_x       } ),
	.o_1H_n        ( w_1h_n     ),

	.o_VCLK        ( vclk       ),
	.o_128V_1V     ( { w_128v,   w_64v,   w_32v,   w_16v,   w_8v,   w_4v,   w_2v,   w_1v         } ),
	.o_128V_1V_x   ( { w_128v_x, w_64v_x, w_32v_x, w_16v_x, w_8v_x, w_4v_x, w_2v_x, w_1v_x       } ),
	.o_256V        ( w_256v     ),

	.o_OBJ_CNTR    ( obj_cntr   )
);

assign o_1h_n = w_1h_n;

`ifdef SIMULATION

wire [8:0] X_POS;
wire [7:0] Y_POS;

assign X_POS = { 1'b0, w_128h, w_64h, w_32h, w_16h, w_8h, w_4h, w_2h, w_1h };
assign Y_POS = { w_128v, w_64v, w_32v, w_16v, w_8v, w_4v, w_2v, w_1v };

reg  wait_hbl, frame_start, draw_start;

assign frame_start = X_POS == 9'd0 && Y_POS == 8'd16;

always @( posedge o_VBL )
	wait_hbl <= 1'b1;

always @( posedge w_BLK ) begin
	if( wait_hbl ) begin
		draw_start <= 1'b1;
		wait_hbl <= 1'b0;
	end else begin
		draw_start <= 1'b0;
	end
end

wire        db_vram_vvff       = video_ram1_hi_gfx_dout[3];
wire [10:0] db_vram_char_index = { video_ram1_hi_gfx_dout[2:0], video_ram1_lo_gfx_dout };

`endif

assign o_2h     = w_2h;
assign o_256v   = w_256v;

assign w_256h_n = ~w_256h;

assign w_256h_x = ~w_256h ^ i_HFLIP;

assign w_128ha  = ( w_256h && w_128h ) || (w_256h_n && w_32h );

reg w_2hd, w_4hd;

always @( posedge i_MCLK ) begin
	w_2hd <= w_2h;
	w_4hd <= w_4h;
end

assign w_1hf = w_1h_n;

wire blank_16h, blank_4h, blank_clk_n;

jtframe_ff u_19h_left_ff(
	.rst     ( i_RESET                   ),
	.clk     ( i_MCLK                    ),
	.cen     ( 1'b1                      ),
	.sigedge ( w_16h                     ),
	.set     ( 1'b0                      ),
	.clr     ( 1'b0                      ),
	.din     ( ~&{ w_VBL_xx_n, w_HBL_n } ),
	.q       ( blank_16h                 ),
	.qn      (                           )
);

jtframe_ff u_19h_right_ff(
	.rst     ( i_RESET                   ),
	.clk     ( i_MCLK                    ),
	.cen     ( 1'b1                      ),
	.sigedge ( ~champx                   ),
	.set     ( 1'b0                      ),
	.clr     ( 1'b0                      ),
	.din     ( blank_16h                 ),
	.q       ( obj_wr                    ),
	.qn      ( obj_clr                   )
);

jtframe_ff u_17a_top_ff(
	.rst     ( i_RESET ),
	.clk     ( i_MCLK  ),
	.cen     ( 1'b1    ),
	.sigedge ( w_4h    ),
	.set     ( 1'b0    ),
	.clr     ( 1'b0    ),
	.din     ( CSYNC_n ),
	.q       ( w_HS_n  ),
	.qn      (         )
);

jtframe_sh #( .W( 1 ), .L( 22 ) )
u_blk_dly(
	.clk    ( i_MCLK     ),
	.clk_en ( w_clk_6MHz ),
	.din    ( w_HBL_n    ),
	.drop   ( w_BLK      )
);

always @(*) begin
	case( { ~vclk } )
		1'b0:   scrollram_gfx_addr <= { 1'b0, w_4hd, w_2h, w_128v_x, w_64v_x, w_32v_x, w_16v_x, w_8v_x, w_4v_x, w_2v_x, w_1v_x };
		1'b1:   scrollram_gfx_addr <= { {4{1'b1}}, w_4hd, w_256h_x, w_128h_x, w_64h_x, w_32h_x, w_16h_x, w_8h_x };
	endcase
end

K005291 u_5291(
	.i_MCLK               ( i_MCLK              ),

	.i_HFLIP              ( i_HFLIP             ),
	.i_VFLIP              ( i_VFLIP             ),
	.i_VCLK               ( vclk                ),
	.i_HCNTR_BUS          ( { w_64h, w_32h, w_16h, w_8h, w_4h, w_2h, w_1h }         ),
	.i_VCNTR_BUS          ( { w_128v, w_64v, w_32v, w_16v, w_8v, w_4v, w_2v, w_1v } ),
    .i_256H_n             ( ~w_256h             ),
    .i_128HA              ( w_128ha             ),

	.i_CPU_ADDR_BUS       ( i_addr[12:1]        ),
	.i_SCROLL_DATA_BUS    ( scroll_ram_gfx_dout ),

	.o_TILE_LINE_ADDR_BUS ( tile_va             ),
	.o_VRAM_ADDR_BUS      ( vram_gfx_addr       ),
	.o_SHIFT_A1           ( tile_shift_a1       ),
	.o_SHIFT_A2           ( tile_shift_a2       ),
	.o_SHIFT_B            ( tile_shift_b        )
);

wire [10:0] vram1_latched_dout;
wire [ 6:0] vram2_latched_dout;

wire w_2h_n = ~w_2h;

bus_ff #( .W( 12 ) )
u_tile_addr_ff(
	.rst     ( i_RESET         ),
	.clk     ( i_MCLK          ),
	.trig    ( w_2h_n          ),
	.d       ( { video_ram1_hi_gfx_dout[3:0], video_ram1_lo_gfx_dout } ),
	.q       ( { vvff, vram1_latched_dout                            } ),
	.q_n     (                 )
);

assign tile_pr    = video_ram1_hi_gfx_dout[7:4];
assign vhff       = video_ram2_gfx_dout[7];
assign tile_color = video_ram2_gfx_dout[6:0];

assign vca = { vram1_latched_dout, {3{vvff}} ^ tile_va };

bus_ff #( .W( 14 ) )
u_oca_ras_cas_ff(
	.rst     ( i_RESET        ),
	.clk     ( i_MCLK         ),
	.trig    ( champx2        ),
	.d       ( { cha_ov ? vca : oca } ),
	.q       ( charram_gfx_addr[15:2] ),
	.q_n     (                )
);

wire       tm_a_hflip, tm_b_hflip, aff, bff,
           tm_a_shift_L_n, tm_a_shift_R_n, tm_b_shift_L_n, tm_b_shift_R_n,
           tm_a_px_trans, tm_b_px_trans;
wire [3:0] tm_a_px_data, tm_b_px_data;

wire [0:3] A, B, C, D, E, F, G, H;

assign A[0:3] = charram_1_hi_gfx_dout[7:4];
assign B[0:3] = charram_1_hi_gfx_dout[3:0];
assign C[0:3] = charram_1_lo_gfx_dout[7:4];
assign D[0:3] = charram_1_lo_gfx_dout[3:0];
assign E[0:3] = charram_2_hi_gfx_dout[7:4];
assign F[0:3] = charram_2_hi_gfx_dout[3:0];
assign G[0:3] = charram_2_lo_gfx_dout[7:4];
assign H[0:3] = charram_2_lo_gfx_dout[3:0];

assign aff = tm_a_hflip ^ i_HFLIP;
assign bff = tm_b_hflip ^ i_HFLIP;

reg asl, asr, bsl, bsr;

always @( posedge i_MCLK ) begin
	asl <= |{  aff, ~tile_shift_a1 };
	asr <= |{ ~aff, ~tile_shift_a1 };
	bsl <= |{  bff, ~tile_shift_b };
	bsr <= |{ ~bff, ~tile_shift_b };
end

assign tm_a_shift_L_n = asl;
assign tm_a_shift_R_n = asr;
assign tm_b_shift_L_n = bsl;
assign tm_b_shift_R_n = bsr;

K005290 u_5290
(
	.i_MCLK          ( i_MCLK                     ),
	.i_RST           ( i_RESET                    ),
	.i_CLK_px6       ( w_clk_6MHz                 ),
	.i_AFF           ( aff                        ),
	.i_BFF           ( bff                        ),
	.i_9E_pin3       ( tm_a_shift_L_n             ),
	.i_9E_pin11      ( tm_a_shift_R_n             ),
	.i_9E_pin6       ( tm_b_shift_L_n             ),
	.i_9E_pin8       ( tm_b_shift_R_n             ),
	.i_A             ( A[0:3]                     ),
	.i_B             ( B[0:3]                     ),
	.i_C             ( C[0:3]                     ),
	.i_D             ( D[0:3]                     ),
	.i_E             ( E[0:3]                     ),
	.i_F             ( F[0:3]                     ),
	.i_G             ( G[0:3]                     ),
	.i_H             ( H[0:3]                     ),
	.i_2HD           ( w_2hd                      ),
	.i_4HD_n         ( ~w_4hd                     ),
	.o_TM_A_px_trans ( tm_a_px_trans              ),
	.o_TM_A_pixels   ( tm_a_px_data               ),
	.o_TM_B_px_trans ( tm_b_px_trans              ),
	.o_TM_B_pixels   ( tm_b_px_data               )
);

wire  w_4hd_n, w_4hd_clkd, w_2hd_clkd, shift_a1_clkd, shift_a2_clkd, shift_b_clkd;

assign w_4hd_clkd    = ~&{ ~w_4hd, w_2hd };

assign w_2hd_clkd    = ~&{  w_4hd, w_2hd };

assign shift_a1_clkd = |{ tile_shift_a1, clk6 };
assign shift_a2_clkd = |{ tile_shift_a2, clk6 };
assign shift_b_clkd  = |{ tile_shift_b,  clk6 };

wire [15:0] obj_px_data = { obj_buff_b_dout_dly, obj_buff_a_dout_dly };

K005293 u_5293(
	.i_RST            ( i_RESET                     ),
	.i_CLK            ( i_MCLK                      ),
	.i_CEN6           ( w_clk_6MHz                  ),
	.i_SHIFT_A1_CLKD  ( shift_a1_clkd               ),
	.i_SHIFT_A2_CLKD  ( shift_a2_clkd               ),
	.i_SHIFT_B_CLKD   ( shift_b_clkd                ),
	.i_2HD_CLKD       ( w_2hd_clkd                  ),
	.i_4HD_CLKD       ( w_4hd_clkd                  ),
	.o_TM_A_HFLIP     ( tm_a_hflip                  ),
	.o_TM_B_HFLIP     ( tm_b_hflip                  ),
	.i_TM_A_PX_DATA   ( tm_a_px_data                ),
	.i_TM_A_PX_TRANS  ( tm_a_px_trans               ),
	.i_TM_B_PX_DATA   ( tm_b_px_data                ),
	.i_TM_B_PX_TRANS  ( tm_b_px_trans               ),
	.i_HFLIP          ( i_HFLIP                     ),
	.i_TILE_PRIORITY  ( tile_pr                     ),
	.i_VHFF           ( vhff                        ),
	.i_VRAM2_DATA     ( tile_color                  ),
	.i_OBJ_PX_DATA    ( obj_px_data                 ),
	.o_COLOR_RAM_ADDR ( o_pal_addr                  ),
	.i_1H_n           ( w_1h_n                      )
);

wire [ 7:0] obj_pri, obj_table_din, obj_table_dout;
wire [10:0] obj_table_addr;
wire        obj_table_we_n, obj_buf_wr, obj_buf_ras;

assign objram_gfx_addr = { w_8v, w_4v, w_2v, w_1v, w_128h, w_64h, w_32h, w_16h, w_8h, w_4h, w_2hd };

wire champx = ~clk6 | w_1h;

wire champx2;

jtframe_sh #( .W( 1 ), .L( 3 ) )
u_champx2_dly(
	.clk    ( i_MCLK  ),
	.clk_en ( 1'b1    ),
	.din    ( champx  ),
	.drop   ( champx2 )
);

reg  wrtime2_d1, wrtime2_d1_5, wrtime2_d2, clk6_d1, clk6_d2;

wire wrtime2_delay_cen, wrtime2_buf_we_or;

always @( posedge i_MCLK ) begin
	clk6_d1 <= clk6;
	clk6_d2 <= clk6_d1;
end

assign wrtime2_delay_cen = cen6_dly2;
assign wrtime2_buf_we_or = clk6_d2;

always @( posedge i_MCLK ) if( wrtime2_delay_cen ) begin
	wrtime2_d1 <= wrtime2;
	wrtime2_d2 <= wrtime2_d1;
end

always @( posedge i_MCLK ) if( cen6b ) begin
	wrtime2_d1_5 <= wrtime2_d1;
end

wire wrtime2_buf_ras_n;

os_pulse_gen #( .DELAY( 0 ), .DURATION( 4 ) )
wrtime2_buf_ras_n_gen
(
	.clk     ( i_MCLK            ),
	.trig    ( ~wrtime2          ),
	.trig_en ( 1'b1              ),
	.pulse   ( wrtime2_buf_ras_n )
);

wire  obj_buf_ras_n = obj_wr ? wrtime2_buf_ras_n : ~champx;

always @( posedge i_MCLK ) begin
	obj_hl = ~obj_buf_ras_n;
end

wire obj_clr_we, wrtime2_buf_we_n;
wire obj_clr_we_pulse;

os_pulse_gen #( .DELAY( 0 ), .DURATION( 2 ) )
obj_clr_we_gen
(
	.clk     ( i_MCLK            ),
	.trig    ( cen6              ),
	.trig_en ( w_1h              ),
	.pulse   ( obj_clr_we_pulse  )
);

assign obj_clr_we = ~obj_clr_we_pulse;

assign wrtime2_buf_we_n = ~wrtime2_d2 | wrtime2_buf_we_or;

assign obj_buf_wr = obj_wr ? wrtime2_buf_we_n | ~cen6_dly2 : obj_clr_we;

assign dma_n = ~&{ w_128v, w_64v, w_32v, ~w_16v };

wire u19g_clk = |{ w_8h, w_4h, w_2h };

bus_ff #( .W( 8 ) )
u_obj_pri_ff(
	.rst     ( i_RESET                   ),
	.clk     ( i_MCLK                    ),
	.trig    ( u19g_clk                  ),
	.d       ( objram_gfx_dout           ),
	.q       ( obj_pri                   ),
	.q_n     (                           )
);

assign obj_table_addr = dma_n
	? { obj_cntr, ora }
	: { obj_pri, w_8h, w_4h, w_2hd };

assign obj_table_we_n = |{ dma_n, w_1h_n };

bus_ff #( .W( 8 ) )
u_obj_din_ff(
	.rst     ( i_RESET                   ),
	.clk     ( i_MCLK                    ),
	.trig    ( w_1h_n                    ),
	.d       ( objram_gfx_dout           ),
	.q       ( obj_table_din             ),
	.q_n     (                           )
);

jtframe_ram #(
	.AW(11),
	.DW(8)
)
u_obj_table(
	.clk     ( i_MCLK          ),
	.cen     ( 1'b1            ),
	.addr    ( obj_table_addr  ),
	.data    ( obj_table_din   ),
	.we      ( ~obj_table_we_n ),
	.q       ( obj_table_dout  )
);

wire        obj_px_blank_n, obj_buff_cas;
reg         obj_hl;
wire [ 2:0] obj_pix_sel;

K005295 u_5295
(
	.i_EMU_MCLK             ( i_MCLK          ),

	.i_EMU_CLK6MPCEN_n      ( ~cen6           ),

	.i_FLIP                 ( i_HFLIP         ),
	.i_ABS_1H               ( w_1h            ),
	.i_ABS_2H               ( w_2h            ),
	.i_ABS_4H               ( w_4h            ),
	.i_HBLANK_n             ( w_HBL_n         ),
	.i_VBLANK_n             ( w_VBL_n         ),
	.i_VBLANKH_n            ( w_VBL_xx_n      ),
	.i_DMA_n                ( dma_n           ),
	.i_OBJHL                ( obj_hl          ),
	.i_OBJWR                ( obj_wr          ),
	.i_CHAMPX               (                 ),

	.i_OBJDATA              ( obj_table_dout  ),

	.o_ORINC                ( orinc           ),
	.o_ORA                  ( ora             ),
	.o_WRTIME2              ( wrtime2         ),
	.o_XA7                  ( xa7             ),
	.o_XB7                  ( xb7             ),
	.o_PIXELSEL             ( obj_pix_sel     ),
	.o_CHAOV                ( cha_ov          ),
	.o_FA                   ( obj_buff_a_addr ),
	.o_FB                   ( obj_buff_b_addr ),
	.o_OCA                  ( oca             ),
	.o_COLORLATCH_n         ( oc_latch        ),
	.o_XPOS_D0              ( obj_xpos_d0     ),
	.o_LATCH_A_D2           ( obj_latch_a_d2  ),
	.o_CAS                  ( obj_buff_cas    ),
	.o_PIXELLATCH_WAIT_n    ( obj_px_blank_n  )
);

wire [7:0] k5294_da, k5294_db;

assign obj_pixel_latch = clk6 | ~&{ w_1h, w_2h };

reg obj_pixel_latch_dly_1, obj_pixel_latch_dly;

always @( posedge i_MCLK ) begin
	obj_pixel_latch_dly_1 <= obj_pixel_latch;
	obj_pixel_latch_dly   <= obj_pixel_latch_dly_1;
end

K005294 u_5294
(
	.i_EMU_MCLK           ( i_MCLK             ),
	.i_EMU_CLK6MPCEN_n    ( ~cen6          ),

	.i_GFXDATA            ( { A[0:3], B[0:3], C[0:3], D[0:3], E[0:3], F[0:3], G[0:3], H[0:3] } ),
	.i_WRTIME2            (wrtime2             ),
	.i_COLORLATCH_n       (oc_latch            ),
	.i_XPOS_D0            (obj_xpos_d0         ),
	.i_PIXELLATCH_WAIT_n  (obj_px_blank_n  ),
	.i_LATCH_A_D2         (obj_latch_a_d2      ),
	.i_PIXELSEL           (obj_pix_sel         ),

	.i_OC                 (obj_table_dout[4:1] ),

	.i_TILELINELATCH_n    (obj_pixel_latch_dly ),

	.o_DA                 ( k5294_da           ),
	.o_DB                 ( k5294_db           )
);

wire k5294_da_trans, k5294_db_trans, obj_buff_a_s, obj_buff_b_s;

assign k5294_da_trans = ~|k5294_da[3:0];
assign obj_buff_a_s   = xa7 | k5294_da_trans;
assign k5294_db_trans = ~|k5294_db[3:0];
assign obj_buff_b_s   = xb7 | k5294_db_trans;

assign obj_buff_a_din = obj_clr ? 8'h0 : ( obj_buff_a_s ? obj_buff_a_dout_dly : k5294_da );

assign obj_buff_b_din = obj_clr ? 8'h0 : ( obj_buff_b_s ? obj_buff_b_dout_dly : k5294_db );

wire [15:0] obj_buff_a_addr_cas_ed, obj_buff_b_addr_cas_ed;

bus_ff #( .W( 32 ) )
u_obj_buffer_ras_cas_ff(
	.rst     ( i_RESET        ),
	.clk     ( i_MCLK         ),
	.trig    ( obj_buff_cas   ),
	.d       ( { obj_buff_a_addr,        obj_buff_b_addr        } ),
	.q       ( { obj_buff_a_addr_cas_ed, obj_buff_b_addr_cas_ed } ),
	.q_n     (                )
);

jtframe_ram #(
	.DW(  8 ),
	.AW( 16 )
)
obj_buffer_a(
	.clk  ( i_MCLK                 ),
	.cen  ( 1'b1                   ),
	.data ( obj_buff_a_din         ),
	.addr ( obj_buff_a_addr_cas_ed ),
	.we   ( ~obj_buf_wr            ),
	.q    ( obj_buff_a_dout        )
);

jtframe_ram #(
	.DW(  8 ),
	.AW( 16 )
)
obj_buffer_b(
	.clk  ( i_MCLK                 ),
	.cen  ( 1'b1                   ),
	.data ( obj_buff_b_din         ),
	.addr ( obj_buff_b_addr_cas_ed ),
	.we   ( ~obj_buf_wr            ),
	.q    ( obj_buff_b_dout        )
);

reg  [7:0] obj_buff_a_dout_dly_1, obj_buff_b_dout_dly_1, obj_buff_a_dout_dly, obj_buff_b_dout_dly;

always @( posedge i_MCLK ) begin
	{ obj_buff_a_dout_dly_1, obj_buff_b_dout_dly_1 } <= { obj_buff_a_dout,       obj_buff_b_dout       };
	{ obj_buff_a_dout_dly,   obj_buff_b_dout_dly   } <= { obj_buff_a_dout_dly_1, obj_buff_b_dout_dly_1 };
end

always @(*) begin
	case( 1'b0 )
		i_vzcs:     o_data_bus_out <= { 8'h00, scroll_ram_cpu_dout };
		i_objram_n: o_data_bus_out <= { 8'h00, objram_cpu_dout };
		i_vcs1:     o_data_bus_out <= { video_ram1_hi_cpu_dout, video_ram1_lo_cpu_dout };
		i_vcs2:     o_data_bus_out <= { 8'h00, video_ram2_cpu_dout };
		chacs1:     o_data_bus_out <= { charram_1_hi_cpu_dout, charram_1_lo_cpu_dout };
		chacs2:     o_data_bus_out <= { charram_2_hi_cpu_dout, charram_2_lo_cpu_dout };
		default:    o_data_bus_out <= 16'hffff;
	endcase
end

`ifdef SIM_DEMO_SCROLL
fake_scroll_ram  #(
	.AW(11),
	.DW(8),
	.SIMHEXFILE("scrollram.hex")
)
u_scroll_ram(
	.frame   ( mist_test.frame_cnt - 32'd1    ),
`else
jtframe_dual_ram #(
	.AW(11),
	.DW(8),
	.SIMHEXFILE("scrollram.hex")
)
u_scroll_ram(
`endif
	.clk0    ( i_MCLK                         ),
	.addr0   ( i_addr[11:1]                   ),
	.data0   ( i_data_bus_in[ 7:0]            ),
	.we0     ( &{ ~i_vzcs, ~i_RnW, ~i_lds_n } ),
	.q0      ( scroll_ram_cpu_dout            ),

	.clk1    ( i_MCLK                         ),
	.addr1   ( scrollram_gfx_addr             ),
	.data1   (                                ),
	.we1     ( 1'b0                           ),
	.q1      ( scroll_ram_gfx_dout            )
);

jtframe_dual_ram #(
	.AW(11),
	.DW(8),
	.SIMHEXFILE("objram.hex")
)
u_objram(
	.clk0    ( i_MCLK                             ),
	.addr0   ( i_addr[11:1]                       ),
	.data0   ( i_data_bus_in[ 7:0]                ),
	.we0     ( &{ ~i_objram_n, ~i_RnW, ~i_lds_n } ),
	.q0      ( objram_cpu_dout                    ),

	.clk1    ( i_MCLK                             ),
	.addr1   ( objram_gfx_addr                    ),
	.data1   (                                    ),
	.we1     ( 1'b0                               ),
	.q1      ( objram_gfx_dout                    )
);

jtframe_dual_ram #(
	.AW(12),
	.DW(8),
	.SIMHEXFILE("vram1_lo.hex")
)
u_video_ram1_lo(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[12:1]                   ),
	.data0  ( i_data_bus_in[ 7:0]            ),
	.we0    ( &{ ~i_vcs1, ~i_RnW, ~i_lds_n } ),
	.q0     ( video_ram1_lo_cpu_dout         ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( vram_gfx_addr                  ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( video_ram1_lo_gfx_dout         )
);

jtframe_dual_ram #(
	.AW(12),
	.DW(8),
	.SIMHEXFILE("vram1_hi.hex")
)
u_video_ram1_hi(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[12:1]                   ),
	.data0  ( i_data_bus_in[15:8]            ),
	.we0    ( &{ ~i_vcs1, ~i_RnW, ~i_uds_n } ),
	.q0     ( video_ram1_hi_cpu_dout         ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( vram_gfx_addr                  ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( video_ram1_hi_gfx_dout         )
);

jtframe_dual_ram #(
	.AW(12),
	.DW(8),
	.SIMHEXFILE("vram2.hex")
)
u_video_ram2(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[12:1]                   ),
	.data0  ( i_data_bus_in[ 7:0]            ),
	.we0    ( &{ ~i_vcs2, ~i_RnW, ~i_lds_n } ),
	.q0     ( video_ram2_cpu_dout            ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( vram_gfx_addr                  ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( video_ram2_gfx_dout            )
);

assign chacs1    = |{  i_addr[1], i_chacs_n };

assign chacs2    = |{ ~i_addr[1], i_chacs_n };

jtframe_dual_ram #(
	.AW(14),
	.DW(8),
	.SIMHEXFILE("charram1_lo.hex")
)
u_charram_1_lo(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[15:2]                   ),
	.data0  ( i_data_bus_in[ 7:0]            ),
	.we0    ( &{ ~chacs1, ~i_RnW, ~i_lds_n } ),
	.q0     ( charram_1_lo_cpu_dout          ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( charram_gfx_addr[15:2]         ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( charram_1_lo_gfx_dout          )
);

jtframe_dual_ram #(
	.AW(14),
	.DW(8),
	.SIMHEXFILE("charram1_hi.hex")
)
u_charram_1_hi(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[15:2]                   ),
	.data0  ( i_data_bus_in[15:8]            ),
	.we0    ( &{ ~chacs1, ~i_RnW, ~i_uds_n } ),
	.q0     ( charram_1_hi_cpu_dout          ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( charram_gfx_addr[15:2]         ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( charram_1_hi_gfx_dout          )
);

jtframe_dual_ram #(
	.AW(14),
	.DW(8),
	.SIMHEXFILE("charram2_lo.hex")
)
u_charram_2_lo(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[15:2]                   ),
	.data0  ( i_data_bus_in[ 7:0]            ),
	.we0    ( &{ ~chacs2, ~i_RnW, ~i_lds_n } ),
	.q0     ( charram_2_lo_cpu_dout          ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( charram_gfx_addr[15:2]         ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( charram_2_lo_gfx_dout          )
);

jtframe_dual_ram #(
	.AW(14),
	.DW(8),
	.SIMHEXFILE("charram2_hi.hex")
)
u_charram_2_hi(
	.clk0   ( i_MCLK                         ),
	.addr0  ( i_addr[15:2]                   ),
	.data0  ( i_data_bus_in[15:8]            ),
	.we0    ( &{ ~chacs2, ~i_RnW, ~i_uds_n } ),
	.q0     ( charram_2_hi_cpu_dout          ),

	.clk1   ( i_MCLK                         ),
	.addr1  ( charram_gfx_addr[15:2]         ),
	.data1  (                                ),
	.we1    ( 1'b0                           ),
	.q1     ( charram_2_hi_gfx_dout          )
);

`endif

endmodule
