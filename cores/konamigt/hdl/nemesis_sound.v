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

module nemesis_sound(
	input         i_clk,
	input         i_cen3p5,
	input         i_cen1p7,
	input         i_cen_clk_div,
	input         i_rst,

	input  [ 7:0] i_main_db,
	input         i_data_n,
	input         i_sound_on_n,

	input         i_cpu_start,
	output        o_z80_cs,
	output [13:0] o_z80_addr,
	input  [ 7:0] i_z80_data,
	input         i_z80_ok,

	output [ 7:0] o_wav1_addr,
	output [ 7:0] o_wav1_vol_addr,
	output [ 7:0] o_wav2_addr,
	output [ 7:0] o_wav2_vol_addr,
	input  [ 3:0] i_wav1_data,
	input  [ 7:0] i_wav1_vol_data,
	input  [ 3:0] i_wav2_data,
	input  [ 7:0] i_wav2_vol_data,

	output [15:0] o_sound,

	input         i_prom1_on,
	input         i_prom2_on,
	input         i_ay7_on,
	input         i_ay8_on,
	input  [ 7:0] i_vol_prom,
	input  [ 7:0] i_vol_ay7,
	input  [ 7:0] i_vol_ay8
);

wire        cen14;
wire        cen_k5289;
wire        cen_z80;
wire        cen_div_256;
reg  [ 7:0] r_clk_div_cnt;
reg  [ 7:0] r_ay8_ioa_in;

wire        cpu_rst_n, cpu_int_n, cpu_rfsh_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n;
wire [15:0] cpu_addr;

reg  [ 7:0] cpu_data_in;
wire [ 7:0] cpu_data_out, cpu_rom_data, cpu_ram_data,
            ay7_data, ay8_data, data_ff_out;

reg         r_rom_CE_n, r_ram_CS, r_k5289_ld1, r_k5289_ld2, r_k5289_tg1, r_k5289_tg2,
            r_ay7_sel_n, r_ay8_sel_n, r_filter_ff_clk, r_data_OC_n;

wire [ 7:0] prom1_addr, prom2_addr;
wire [ 3:0] prom1_data, prom2_data;

wire [ 7:0] prom1_snd, prom2_snd;

wire [ 7:0] ay7_ioa_out, ay7_iob_out;
wire        ay7_bc1, ay7_bdir, ay8_bc1, ay8_bdir;

wire [ 9:0] ay7_sound, ay8_sound;

wire        ay7_filter_on, ay8_filter_on;

assign cen_k5289   = i_cen3p5;
assign cen_z80     = i_cen1p7;
assign cen_div_256 = i_cen_clk_div;

assign cpu_rst_n = ~i_rst;

wire [15:0] full_audio;

unsigned_mixer #(
	.W0   ( 14 ),
	.W1   ( 14 ),
	.W2   ( 14 ),
	.W3   ( 14 ),
	.WOUT ( 16 )
) u_mixer (
    .rst   ( i_rst        ),
    .clk   ( i_clk        ),
    .cen   ( cen_k5289    ),

    .ch0   ( { {6{1'b0}}, prom1_snd } ),
    .ch1   ( { {6{1'b0}}, prom2_snd } ),
    .ch2   ( { {4{1'b0}}, ay7_sound } ),
    .ch3   ( { {4{1'b0}}, ay8_sound } ),

    .gain0 ( i_prom1_on ? i_vol_prom : 8'd0 ),
    .gain1 ( i_prom2_on ? i_vol_prom : 8'd0 ),
    .gain2 ( i_ay7_on ? i_vol_ay7    : 8'd0 ),
    .gain3 ( i_ay8_on ? i_vol_ay8    : 8'd0 ),

	.mixed ( full_audio   ),
	.peak  (  )
);

assign o_sound = full_audio[15:0];

always @(*) begin
	reg rfsh_not_mreq, u11c_g2b_n;

	rfsh_not_mreq   = cpu_rfsh_n & ~cpu_mreq_n;
	r_rom_CE_n      = ! ( rfsh_not_mreq && cpu_addr[15:14] == 2'b00  );
	r_ram_CS        = ! ( rfsh_not_mreq && cpu_addr[15:13] == 3'b010 );
	r_k5289_ld1     = ! ( rfsh_not_mreq && cpu_addr[15:13] == 3'b101 );
	r_k5289_ld2     = ! ( rfsh_not_mreq && cpu_addr[15:13] == 3'b110 );
	u11c_g2b_n      = ! ( rfsh_not_mreq && cpu_addr[15:13] == 3'b111 );

	r_data_OC_n     = ! ( ~u11c_g2b_n && cpu_addr[2:0] == 3'b001 );
	r_k5289_tg1     = ! ( ~u11c_g2b_n && cpu_addr[2:0] == 3'b011 );
	r_k5289_tg2     = ! ( ~u11c_g2b_n && cpu_addr[2:0] == 3'b100 );
	r_ay7_sel_n     = ! ( ~u11c_g2b_n && cpu_addr[2:0] == 3'b101 );
	r_ay8_sel_n     = ! ( ~u11c_g2b_n && cpu_addr[2:0] == 3'b110 );
	r_filter_ff_clk = ! ( ~u11c_g2b_n && cpu_addr[2:0] == 3'b111 );
end

always @(*) begin
	case( 1'b1 )
		~r_rom_CE_n:             cpu_data_in <= cpu_rom_data;
		~r_ram_CS && ~cpu_rd_n:  cpu_data_in <= cpu_ram_data;
		~ay7_bdir && ay7_bc1:    cpu_data_in <= ay7_data;
		~ay8_bdir && ay8_bc1:    cpu_data_in <= ay8_data;
		~r_data_OC_n:            cpu_data_in <= data_ff_out;
		default:                 cpu_data_in <= 8'hff;
	endcase
end

wire cen_z80_wait, cpu_busak_n;

T80s u_audio_cpu(
	.RFSH_n  ( cpu_rfsh_n   ),
	.MREQ_n  ( cpu_mreq_n   ),
	.INT_n   ( cpu_int_n    ),
	.IORQ_n  ( cpu_iorq_n   ),
	.RESET_n ( cpu_rst_n    ),

	.NMI_n   ( 1'b1         ),
	.BUSRQ_n ( 1'b1         ),
	.WAIT_n  ( 1'b1         ),
	.BUSAK_n ( cpu_busak_n  ),

	.CLK     ( i_clk        ),
	.CEN     ( cen_z80_wait ),

	.RD_n    ( cpu_rd_n     ),
	.WR_n    ( cpu_wr_n     ),

	.A       ( cpu_addr     ),
	.DI      ( cpu_data_in  ),
	.DOUT    ( cpu_data_out )
);

jtframe_z80wait #(1) u_wait(
	.rst_n      ( cpu_rst_n    ),
	.clk        ( i_clk        ),
	.cen_in     ( cen_z80      ),
	.cen_out    ( cen_z80_wait ),
	.gate       (              ),
	.iorq_n     ( cpu_iorq_n   ),
	.mreq_n     ( cpu_mreq_n   ),
	.busak_n    ( cpu_busak_n  ),

	.dev_busy   ( 1'b0         ),

	.rom_cs     ( ~r_rom_CE_n  ),
	.rom_ok     ( i_z80_ok     )
);

assign o_z80_cs = ~r_rom_CE_n;
assign o_z80_addr = cpu_addr[13:0];
assign cpu_rom_data = i_z80_data;

jtframe_ram #(
	.AW( 11 ),
	.DW(  8 )
)
u_audio_cpu_ram(
	.clk  ( i_clk                    ),
	.cen  ( cen_z80_wait             ),
	.addr ( cpu_addr[10:0]           ),
	.data ( cpu_data_out             ),
	.we   ( ~r_ram_CS & ~cpu_wr_n    ),
	.q    ( cpu_ram_data             )
);

always @( posedge i_clk ) if( cen_div_256 ) begin
	r_clk_div_cnt <= r_clk_div_cnt + 8'd1;

	r_ay8_ioa_in  <= { 4'b0, r_clk_div_cnt[7:4] };
end

K005289 u_k5289(
	.i_RST_n     ( cpu_rst_n       ),
	.i_CLK       ( i_clk           ),
	.i_CEN       ( cen_k5289       ),
	.i_LD1       ( r_k5289_ld1     ),
	.i_TG1       ( r_k5289_tg1     ),
	.i_LD2       ( r_k5289_ld2     ),
	.i_TG2       ( r_k5289_tg2     ),
	.i_COUNTER   ( cpu_addr[11:0]  ),
	.o_Q1        ( prom1_addr[4:0] ),
	.o_Q2        ( prom2_addr[4:0] )
);

assign o_wav1_addr = { ay7_ioa_out[7:5], prom1_addr[4:0] };
assign prom1_data  = i_wav1_data;

assign o_wav2_addr = { ay7_iob_out[7:5], prom2_addr[4:0] };
assign prom2_data  = i_wav2_data;

assign o_wav1_vol_addr = { ay7_ioa_out[3:0], prom1_data };
assign o_wav2_vol_addr = { ay7_iob_out[3:0], prom2_data };
assign prom1_snd       = i_wav1_vol_data;
assign prom2_snd       = i_wav2_vol_data;

assign ay7_bdir = ~|{ r_ay7_sel_n, cpu_addr[ 9] };
assign ay7_bc1  = ~|{ r_ay7_sel_n, cpu_addr[10] };
assign ay8_bdir = ~|{ r_ay8_sel_n, cpu_addr[ 7] };
assign ay8_bc1  = ~|{ r_ay8_sel_n, cpu_addr[ 8] };

jt49_bus #( .COMP( 2'b01 ) ) u_ay_7 (
	.rst_n   ( cpu_rst_n    ),
	.clk     ( i_clk        ),
	.clk_en  ( cen_z80      ),
	.bdir    ( ay7_bdir     ),
	.bc1     ( ay7_bc1      ),
	.din     ( cpu_data_out ),
	.sel     ( 1'b1         ),
	.dout    ( ay7_data     ),
	.sound   ( ay7_sound    ),
	.A       (              ),
	.B       (              ),
	.C       (              ),
	.sample  (              ),
	.IOA_in  ( 8'b0         ),
	.IOA_out ( ay7_ioa_out  ),
	.IOB_in  ( 8'b0         ),
	.IOB_out ( ay7_iob_out  )
);

jt49_bus #( .COMP( 2'b01 ) ) u_ay_8 (
	.rst_n   ( cpu_rst_n    ),
	.clk     ( i_clk        ),
	.clk_en  ( cen_z80      ),
	.bdir    ( ay8_bdir     ),
	.bc1     ( ay8_bc1      ),
	.din     ( cpu_data_out ),
	.sel     ( 1'b1         ),
	.dout    ( ay8_data     ),
	.sound   ( ay8_sound    ),
	.A       (              ),
	.B       (              ),
	.C       (              ),
	.sample  (              ),
	.IOA_in  ( r_ay8_ioa_in ),
	.IOA_out (              ),
	.IOB_in  ( 8'b0         ),
	.IOB_out (              )
);

jtframe_ff u_sound_on_ff(
	.rst     ( i_rst                       ),
	.clk     ( i_clk                       ),
	.cen     ( 1'b1                        ),
	.sigedge ( i_sound_on_n                ),
	.set     ( 1'b0                        ),
	.clr     ( ~&{ cpu_rst_n, cpu_iorq_n } ),
	.din     ( 1'b1                        ),
	.q       (                             ),
	.qn      ( cpu_int_n                   )
);

bus_ff #( .W( 2 ) ) u_ay_filter_ff(
	.rst     ( i_rst           ),
	.clk     ( i_clk           ),
	.trig    ( r_filter_ff_clk ),
	.d       ( { cpu_addr[12], cpu_addr[11]   } ),
	.q       ( { ay8_filter_on, ay7_filter_on } ),
	.q_n     (                 )
);

bus_ff #( .W( 8 ) ) u_data_ff(
	.rst     ( i_rst       ),
	.clk     ( i_clk       ),
	.trig    ( i_data_n    ),
	.d       ( i_main_db   ),
	.q       ( data_ff_out ),
	.q_n     (             )
);

endmodule
