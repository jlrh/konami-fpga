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

module K005292
(
	input               i_MCLK,
	input               i_CEN6,
	input               i_RST_n,

	input               i_VFLP,
	input               i_HFLP,
	input               i_INTER,
	input               i_288_256,

	output              o_VBLANK_xx_n,
	output              o_VBLANK_n,
	output              o_HBLANK_n,
	input               i_DMA_n,

	output              o_CSYNC_n,
	output              o_VSYNC_n,

	output       [8:0]  o_256H_1H,
	output       [7:0]  o_128H_1H_x,

	output              o_1H_n,

	output              o_VCLK,

	output       [7:0]  o_128V_1V,
	output              o_256V,
	output       [7:0]  o_128V_1V_x,

	input               i_ORINC,
	output       [7:0]  o_OBJ_CNTR
);

`define H_CNT_RESET 9'd128
`define V_CNT_RESET 9'd248

reg [8:0]     r_H_cnt = `H_CNT_RESET;
reg [8:0]     r_V_cnt = `V_CNT_RESET;

always @(posedge i_MCLK) begin
	if( ~i_RST_n ) begin
		r_H_cnt <= `H_CNT_RESET;
	end else if( i_CEN6 ) begin
		if( r_H_cnt[8:0] < 9'd511 ) begin
			r_H_cnt <= r_H_cnt + 9'd1;
		end else begin

			r_H_cnt[8:0] <= `H_CNT_RESET;
		end
	end
end

assign o_256H_1H[8:0] = r_H_cnt[8:0];

assign o_128H_1H_x[7:0] = {8{i_HFLP}} ^ r_H_cnt[7:0];

assign o_1H_n     = ~r_H_cnt[0];
assign o_HBLANK_n = r_H_cnt[8];

wire vclk_ff_d = &{ ~o_256H_1H[8], ~o_256H_1H[6], o_256H_1H[5] };

wire vclk, vclk_n;

bus_ff #( .W( 1 ) ) u_vclk_ff(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_MCLK       ),
	.trig    ( o_256H_1H[4] ),
	.d       ( vclk_ff_d    ),
	.q       ( vclk         ),
	.q_n     ( vclk_n       )
);

assign o_VCLK    = vclk;
assign o_CSYNC_n = &{ vclk_n, o_VSYNC_n };

reg vclk_prev, vclk_cen;

always @( posedge i_MCLK ) begin
	if( ~i_RST_n ) begin
		vclk_prev <= 1'b1;
	end else begin
		vclk_prev <= vclk;
		vclk_cen <= vclk && ~vclk_prev;
	end
end

wire gen_vblank_n = ( r_V_cnt <= 9'd494 && r_V_cnt >= 9'd271 );

reg r_VBLANK_n = 1'b1;
reg r_VBLANK_xx_n = 1'b1;

always @( posedge i_MCLK ) begin
	if( ~i_RST_n ) begin
		r_V_cnt <=  `V_CNT_RESET;
	end else if( vclk_cen ) begin
		if( r_V_cnt[8:0] < 9'd511 ) begin
			r_V_cnt <= r_V_cnt + 9'd1;
			r_VBLANK_n <= gen_vblank_n;
			r_VBLANK_xx_n <= gen_vblank_n;
		end else begin

			r_V_cnt[8:0] <= `V_CNT_RESET;

			r_VBLANK_xx_n <= 1'b1;
		end
	end
end

assign o_VBLANK_n = r_VBLANK_n;
assign o_VBLANK_xx_n = r_VBLANK_xx_n;

assign o_128V_1V[7:0] = r_V_cnt[7:0];

assign o_128V_1V_x[7:0] = {8{i_VFLP}} ^ r_V_cnt[7:0];

assign o_VSYNC_n = r_V_cnt[8];

wire w_256v, w_256v_n;

bus_ff #( .W( 1 ) ) u_256v_ff2(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_MCLK       ),
	.trig    ( ~r_VBLANK_n  ),
	.d       ( w_256v_n     ),
	.q       ( w_256v       ),
	.q_n     ( w_256v_n     )
);

assign o_256V = w_256v;

reg       orinc_prev;
reg [7:0] obj_cnt = 8'd0;

always @( posedge i_MCLK ) begin
	if( ~i_RST_n | ~i_DMA_n ) begin
		orinc_prev <= 1'b1;
		obj_cnt <= 8'd0;
	end else if( ~i_ORINC & orinc_prev ) begin
		obj_cnt <= obj_cnt + 4'd1;
	end

	orinc_prev <= i_ORINC;
end

assign o_OBJ_CNTR = obj_cnt;

endmodule
