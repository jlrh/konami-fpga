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

module konamigt_main
(
	input         i_clk,
	input         i_rst,

	input         i_cen9,
	input         i_vblank,
	input         i_256v,
	input         i_blk,
	input         i_cen6,
	input         i_clk6,
	input         i_1h_n,
	input         i_2h,

	input         i_vsinc,
	input         i_sync,

	output        o_chacs_n,
	output        o_rw_n,
	output        o_uds_n,
	output        o_lds_n,

	output        o_inter_non,
	output        o_288_256,
	output        o_vflip,
	output        o_hflip,
	output        o_objram_n,
	output        o_vcs2,
	output        o_vcs1,
	output        o_vzcs,

	output [16:0] o_rom_addr,
	output        o_rom_cs,
	input  [15:0] i_rom_data,
	input         i_rom_ok,

	output        o_sound_on_n,

	output        o_data_n,

	output [ 7:0] o_sound_db,

	output [15:1] o_addr,

	input  [10:0] i_cd,

	input  [15:0] i_data_bus_in,
	output [15:0] o_data_bus_out,

	output reg [ 4:0] o_red,
	output reg [ 4:0] o_green,
	output reg [ 4:0] o_blue,

	input  [ 7:0] i_dip1,
	input  [ 7:0] i_dip2,
	input  [ 7:0] i_dip3,

	input         i_pause,

	input  [ 7:0] i_in0,
	input  [ 7:0] i_in1,
	input  [ 7:0] i_in2,

	input  [15:0] i_wheel
);

reg         cen9, cen9b;

wire        as_n, lds_n, uds_n, RnW, vpa_n, int16_n, int32_n, u16f_d1, u16f_d2;
reg         DTACKn;
reg  [ 2:0] ipl_n;
wire [23:1] cpu_addr;
wire [15:0] cpu_dout, rom_dout, color;
reg  [15:0] cpu_din;
wire [ 7:0] ram_hi_dout, ram_lo_dout, color_ram_lo_dout, color_ram_hi_dout;
reg  [ 7:0] u11k_out, u13j_out, input_mux_out;

wire        prom_cs_n, ram_cs_n, chara, excs_n, pre_ram_cs_n,
            vzure, vramcs1, vramcs2, objram, color_ram, u11k_g_n, u13j_g_n, data_n,
            afe_n, input_mux_g_n, dip1_g_n, dip2_g_n;
reg         reg_ram_cs;

`ifndef NOMAIN

assign o_chacs_n  = chara;
assign o_vzcs     = vzure;
assign o_vcs1     = vramcs1;
assign o_vcs2     = vramcs2;
assign o_objram_n = objram;

assign o_hflip      = u11k_out[2];
assign o_vflip      = u11k_out[3];
assign o_288_256    = u11k_out[4];
assign o_inter_non  = u11k_out[5];

assign o_rw_n         = RnW;
assign o_uds_n        = uds_n;
assign o_lds_n        = lds_n;
assign o_addr         = cpu_addr[15:1];
assign o_data_bus_out = cpu_dout;

assign o_sound_db   = cpu_dout[7:0];
assign o_data_n     = data_n;
assign o_sound_on_n = u13j_out[2];

wire [1:0]  input_mux_sel;
wire [7:0]  input_mux_a, input_mux_b, input_mux_c, input_mux_d;

assign input_mux_a = i_in0;
assign input_mux_b = i_in1;
assign input_mux_c = i_in2;
assign input_mux_d = i_dip3;

assign input_mux_sel = cpu_addr[2:1];

always @(*) begin
	case( input_mux_sel )
		2'b00: input_mux_out <= input_mux_a;
		2'b01: input_mux_out <= input_mux_b;
		2'b10: input_mux_out <= input_mux_c;
		2'b11: input_mux_out <= input_mux_d;
	endcase
end

nemesis_68k_addr_dec u_addr_dec(
	.i_as_n           ( as_n           ),
	.i_lds_n          ( lds_n          ),
	.i_uds_n          ( uds_n          ),
	.i_cpu_addr       ( cpu_addr       ),

	.o_prom_cs_n      ( prom_cs_n      ),
	.o_chara          ( chara          ),
	.o_excs_n         ( excs_n         ),
	.o_ram_cs_n       ( pre_ram_cs_n   ),
	.o_vzure          ( vzure          ),
	.o_vramcs1        ( vramcs1        ),
	.o_vramcs2        ( vramcs2        ),
	.o_objram         ( objram         ),
	.o_color_ram      ( color_ram      ),
	.o_u11k_g_n       ( u11k_g_n       ),
	.o_u13j_g_n       ( u13j_g_n       ),
	.o_data_n         ( data_n         ),
	.o_afe_n          ( afe_n          ),
	.o_input_mux_g_n  ( input_mux_g_n  ),
	.o_dip1_g_n       ( dip1_g_n       ),
	.o_dip2_g_n       ( dip2_g_n       )
);

`ifdef SDRAM_FIX

wire   UDSWn, LDSWn;
reg    dsn_dly;

assign UDSWn = RnW | uds_n;
assign LDSWn = RnW | lds_n;

assign ram_cs_n = dsn_dly ? reg_ram_cs  : pre_ram_cs_n;

always @(posedge i_clk) if( cen9 ) begin
	reg_ram_cs <= pre_ram_cs_n;
	dsn_dly    <= &{ UDSWn, LDSWn };
end

`else

assign ram_cs_n = pre_ram_cs_n;

`endif

always @(posedge i_clk ) begin
	reg cen9x;

	cen9  <= i_cen9;
	cen9x <= cen9;
	cen9b <= cen9x;
end

wire video_cs_n = &{ objram, vzure, vramcs1, vramcs2, chara };

always @(*) begin
	case( 1'b0 )
		prom_cs_n:      cpu_din = rom_dout;
		ram_cs_n:       cpu_din = { ram_hi_dout, ram_lo_dout };
		color_ram:      cpu_din = { color_ram_hi_dout, color_ram_lo_dout };
		dip1_g_n:       cpu_din = { 8'h00, i_dip1 };
		dip2_g_n:       cpu_din = { 8'h00, i_dip2 };
		input_mux_g_n:  cpu_din = { 8'h00, input_mux_out };
		u11k_g_n:       cpu_din = { 8'h00, u11k_out };
		u13j_g_n:       cpu_din = { 8'h00, u13j_out };
		video_cs_n:     cpu_din = i_data_bus_in;
		excs_n:         cpu_din = i_wheel;
		default:        cpu_din = 16'hffff;
	endcase
end

always @( posedge i_clk ) begin
	if( i_rst )
		u11k_out <= 8'd0;
	else if( ! u11k_g_n )
		u11k_out[ cpu_addr[3:1] ] <= cpu_dout[0];
end

always @( posedge i_clk ) begin
	if( i_rst )
		u13j_out <= 8'd0;
	else if( ! u13j_g_n )
		u13j_out[ cpu_addr[3:1] ] <= cpu_dout[8];
end

wire DTACKn_other, DTACKn_vzure_objram, DTACKn_vram_chara;
wire idt, vzure_objram_cs_n, vram_chara_cs_n, LUDSn, clk6_1h_2h;

assign idt = 1'b1;

assign vzure_objram_cs_n = &{ vzure, objram };
assign vram_chara_cs_n = &{ idt, vramcs1, vramcs2, chara };
assign LUDSn = &{ lds_n, uds_n };

jtframe_ff u_17e_top(
	.rst     ( i_rst        ),
	.clk     ( i_clk        ),
	.cen     ( 1'b1         ),
	.sigedge ( i_clk6       ),
	.set     ( LUDSn        ),
	.clr     ( 1'b0         ),
	.din     ( LUDSn        ),
	.q       ( DTACKn_other ),
	.qn      (              )
);

jtframe_ff u_17e_bottom(
	.rst     ( i_rst               ),
	.clk     ( i_clk               ),
	.cen     ( 1'b1                ),
	.sigedge ( i_1h_n              ),
	.set     ( LUDSn               ),
	.clr     ( 1'b0                ),
	.din     ( LUDSn               ),
	.q       ( DTACKn_vzure_objram ),
	.qn      (                     )
);

assign clk6_1h_2h = ~|{ i_clk6, ~i_1h_n, i_2h };

jtframe_ff u_18f(
	.rst     ( i_rst             ),
	.clk     ( i_clk             ),
	.cen     ( 1'b1              ),
	.sigedge ( clk6_1h_2h        ),
	.set     ( LUDSn             ),
	.clr     ( 1'b0              ),
	.din     ( DTACKn_other      ),
	.q       ( DTACKn_vram_chara ),
	.qn      (                   )
);

always @(*) begin
	case( { prom_cs_n, vzure_objram_cs_n, vram_chara_cs_n } )
		3'b011:  DTACKn <= ( LUDSn | ~i_rom_ok );
		3'b101:  DTACKn <= DTACKn_vzure_objram;
		3'b110:  DTACKn <= DTACKn_vram_chara;
		default: DTACKn <= DTACKn_other;
	endcase
end

assign int16_n = u11k_out[0];
assign int32_n = u11k_out[1];

jtframe_ff u_17f_top(
	.rst     ( i_rst    ),
	.clk     ( i_clk    ),
	.cen     ( 1'b1     ),
	.sigedge ( i_vblank ),
	.set     ( ~int16_n ),
	.clr     ( 1'b0     ),
	.din     ( 1'b0     ),
	.q       ( u16f_d2  ),
	.qn      (          )
);

jtframe_ff u_17f_bottom(
	.rst     ( i_rst    ),
	.clk     ( i_clk    ),
	.cen     ( 1'b1     ),
	.sigedge ( i_256v   ),
	.set     ( ~int32_n ),
	.clr     ( 1'b0     ),
	.din     ( 1'b0     ),
	.q       ( u16f_d1  ),
	.qn      (          )
);

always @(*) begin
	if( ~u16f_d2 & i_pause )
		ipl_n <= 3'b101;
	else if( ~u16f_d1 & i_pause )
		ipl_n <= 3'b110;
	else
		ipl_n <= 3'b111;
end

assign vpa_n = |{ ~cpu_addr[23], as_n };

fx68k u_cpu(
	.clk        ( i_clk       ),
	.extReset   ( i_rst       ),
	.pwrUp      ( i_rst       ),
	.enPhi1     ( cen9        ),
	.enPhi2     ( cen9b       ),
	.HALTn      ( ~i_rst      ),

	.eab        ( cpu_addr    ),
	.iEdb       ( cpu_din     ),
	.oEdb       ( cpu_dout    ),

	.eRWn       ( RnW         ),
	.LDSn       ( lds_n       ),
	.UDSn       ( uds_n       ),
	.ASn        ( as_n        ),
	.VPAn       ( vpa_n       ),

	.BERRn      ( 1'b1        ),

	.BRn        ( 1'b1        ),
	.BGACKn     ( 1'b1        ),

	.DTACKn     ( DTACKn      ),
	.IPL0n      ( ipl_n[0]    ),
	.IPL1n      ( ipl_n[1]    ),
	.IPL2n      ( ipl_n[2]    ),

	.BGn        (             ),
	.FC0        (             ),
	.FC1        (             ),
	.FC2        (             ),
	.oRESETn    (             ),
	.oHALTEDn   (             ),
	.VMAn       (             ),
	.E          (             )
);

assign o_rom_addr = cpu_addr[17:1];
assign o_rom_cs = ~prom_cs_n;
assign rom_dout = i_rom_data;

jtframe_ram #( .AW(14), .DW(8) ) u_ram_lo(
	.clk    ( i_clk                        ),
	.cen    ( 1'b1                         ),
	.addr   ( cpu_addr[14:1]               ),
	.data   ( cpu_dout[ 7:0]               ),
	.we     ( &{ ~ram_cs_n, ~RnW, ~lds_n } ),
	.q      ( ram_lo_dout                  )
);

jtframe_ram #( .AW(14), .DW(8) ) u_ram_hi(
	.clk    ( i_clk                        ),
	.cen    ( 1'b1                         ),
	.addr   ( cpu_addr[14:1]               ),
	.data   ( cpu_dout[15:8]               ),
	.we     ( &{ ~ram_cs_n, ~RnW, ~uds_n } ),
	.q      ( ram_hi_dout                  )
);

`else

assign o_inter_non = 1'b0;
assign o_288_256   = 1'b0;
assign o_vflip     = 1'b0;
assign o_hflip     = 1'b0;
assign o_addr      = 15'h0000;

`endif

always @( posedge i_clk ) if( i_cen6 ) begin
	o_red   <= color[4:0];
	o_green <= color[9:5];
	o_blue  <= color[14:10];
end

jtframe_dual_ram #( .AW(11), .DW(8), .SIMHEXFILE("colorram_lo.hex") ) u_color_ram_lo(
	.clk0    ( i_clk                         ),
	.addr0   ( cpu_addr[11:1]                ),
	.data0   ( cpu_dout[ 7:0]                ),
	.we0     ( &{ ~color_ram, ~RnW, ~lds_n } ),
	.q0      ( color_ram_lo_dout             ),

	.clk1    ( i_clk                         ),
	.addr1   ( i_cd                          ),
	.data1   (                               ),
	.we1     ( 1'b0                          ),
	.q1      ( color[7:0]                    )
);

jtframe_dual_ram #( .AW(11), .DW(8), .SIMHEXFILE("colorram_hi.hex") ) u_color_ram_hi(
	.clk0    ( i_clk                         ),
	.addr0   ( cpu_addr[11:1]                ),
	.data0   ( cpu_dout[15:8]                ),
	.we0     ( &{ ~color_ram, ~RnW, ~uds_n } ),
	.q0      ( color_ram_hi_dout             ),

	.clk1    ( i_clk                         ),
	.addr1   ( i_cd                          ),
	.data1   (                               ),
	.we1     ( 1'b0                          ),
	.q1      ( color[15:8]                   )
);

endmodule
