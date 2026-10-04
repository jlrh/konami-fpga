/*
	This file is derived from JTFRAME.
	JTFRAME program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	JTFRAME program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

	Author: Jose Tejada Gomez. Twitter: @topapate
	Author: Olivier Scherler.  Twitter: @oscherler
	Version: 1.0
	Date: 15-02-2022
*/

`default_nettype none

module gx400_cen(
	input      i_clk,
	input      i_vsync60,

	output     o_cen12,
	output     o_cen6,
	output     o_cen6b,
	output     o_clk6,
	output     o_cen9,
	output     o_cen3p5,
	output     o_cen1p7,
	output     o_cen_audio_clk_div
);

localparam        WC     = 10;

jtframe_frac_cen #( .W(2) ) u_cpucen(
	.clk        ( i_clk      ),
	.n          ( 10'd24     ),
	.m          ( 10'd128    ),
	.cen        ( o_cen9     ),
	.cenb       (            )
);

wire [9:0] m_video = i_vsync60 ? 10'd131 : 10'd128;

jtframe_frac_cen #( .W(2) ) u_videocen(
	.clk        ( i_clk               ),
	.n          ( 10'd32              ),
	.m          ( m_video             ),
	.cen        ( { o_cen6, o_cen12 } ),
	.cenb       (                     )
);

reg [2:0] clk6_holder = 3'b0;

always @( posedge i_clk ) begin
	if( o_cen6 ) begin
		clk6_holder <= 3'b0;
	end else begin
		clk6_holder <= clk6_holder + 3'b1;
	end
end

assign o_clk6 = ~( clk6_holder > 3'd4 );
assign o_cen6b = clk6_holder == 3'd4;

wire [6:0] audio_cens;

jtframe_frac_cen #( .W(7), .WC(12) ) u_audiocen(
	.clk        ( i_clk      ),
	.n          ( 12'd67     ),
	.m          ( 12'd920    ),

	.cen        ( audio_cens ),
	.cenb       (            )
);

assign o_cen3p5 = audio_cens[0];
assign o_cen1p7 = audio_cens[1];
assign o_cen_audio_clk_div = audio_cens[6];

endmodule
