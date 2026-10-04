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

module K005289
(
	input               i_RST_n,
	input               i_CLK,
	input               i_CEN,

	input               i_LD1,
	input               i_TG1,

	input               i_LD2,
	input               i_TG2,

	input     [11:0]    i_COUNTER,

	output     [4:0]    o_Q1,
	output     [4:0]    o_Q2
);

wire      [11:0]    addrLD1, addrTG1, addrLD2, addrTG2;

reg	      [16:0]    r_count1, r_count2;

bus_ff #( .W( 12 ) ) ch1_ld_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_LD1       ),
	.d       ( i_COUNTER    ),
	.q       ( addrLD1      ),
	.q_n     (              )
);

bus_ff #( .W( 12 ) ) ch1_tg_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_TG1       ),
	.d       ( addrLD1      ),
	.q       ( addrTG1      ),
	.q_n     (              )
);

bus_ff #( .W( 12 ) ) ch2_ld_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_LD2       ),
	.d       ( i_COUNTER    ),
	.q       ( addrLD2      ),
	.q_n     (              )
);

bus_ff #( .W( 12 ) ) ch2_tg_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_TG2       ),
	.d       ( addrLD2      ),
	.q       ( addrTG2      ),
	.q_n     (              )
);

reg [6:0] cen_cnt;

always @( posedge i_CLK ) begin
	if (~i_RST_n) begin
		r_count1 <=  17'd0;
		r_count2 <=  17'd0;
		cen_cnt  <=  7'd0;
	end else if (i_CEN) begin
		cen_cnt <= cen_cnt + 7'd1;

		if(r_count1[11:0] == 12'hFFF) begin
			r_count1 <= r_count1 + 17'd1;
			r_count1[11:0] <= addrTG1 + 12'd1;
		end else begin
			r_count1 <= r_count1 + 17'd1;
		end

		if(r_count2[11:0] == 12'hFFF) begin
			r_count2 <= r_count2 + 17'd1;
			r_count2[11:0] <= addrTG2 + 12'd1;
		end else begin
			r_count2 <= r_count2 + 17'd1;
		end
	end
end

assign o_Q1 = r_count1[16:12];
assign o_Q2 = r_count2[16:12];

endmodule
