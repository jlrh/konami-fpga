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

module K005290
(
	input                 i_MCLK,
	input                 i_RST,
	input                 i_CLK_px6,

	input                 i_AFF,
	input                 i_BFF,

	input                 i_9E_pin3,
	input                 i_9E_pin11,
	input                 i_9E_pin6,
	input                 i_9E_pin8,

	input          [0:3]  i_A,
	input          [0:3]  i_B,
	input          [0:3]  i_C,
	input          [0:3]  i_D,
	input          [0:3]  i_E,
	input          [0:3]  i_F,
	input          [0:3]  i_G,
	input          [0:3]  i_H,

	input                 i_2HD,
	input                 i_4HD_n,

	output                o_TM_A_px_trans,
	output         [3:0]  o_TM_A_pixels,

	output                o_TM_B_px_trans,
	output  reg    [3:0]  o_TM_B_pixels
);

wire      TM_A_pixel_latch;
wire      TM_B_pixel_latch;

assign    TM_A_pixel_latch = ~( ~i_4HD_n & i_2HD );
assign    TM_B_pixel_latch = ~(  i_4HD_n & i_2HD );

wire CLK_INTL0, CLK_INTL1;
reg  CLK_INTL2;

assign CLK_INTL0 = i_CLK_px6;
assign CLK_INTL1 = i_CLK_px6;

always @( posedge i_MCLK ) begin
	CLK_INTL2 <= CLK_INTL0;
end

wire [7:0] TM_A_px_bits_0_latched;
wire [7:0] TM_A_px_bits_1_latched;
wire [7:0] TM_A_px_bits_2_latched;
wire [7:0] TM_A_px_bits_3_latched;

bus_ff #( .W( 8 ) ) U1(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_A_pixel_latch       ),
	.d       ( { i_H[0], i_G[0], i_F[0], i_E[0], i_D[0], i_C[0], i_B[0], i_A[0] } ),
	.q       ( TM_A_px_bits_0_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U2U3(
	.D      ( TM_A_px_bits_0_latched    ),
	.S      ( { i_9E_pin11, i_9E_pin3 } ),
	.mclk   ( i_MCLK                    ),
	.cen    ( CLK_INTL0                 ),
	.clr    ( 1'b0                      ),
	.R      ( 1'b0                      ),
	.L      ( 1'b0                      ),
	.Q      ( TM_A_px_bit_0_flipped     )
);

wire [7:0] TM_A_px_bit_0_flipped;

bus_ff #( .W( 8 ) ) U4(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_A_pixel_latch       ),
	.d       ( { i_H[1], i_G[1], i_F[1], i_E[1], i_D[1], i_C[1], i_B[1], i_A[1] } ),
	.q       ( TM_A_px_bits_1_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U5U6(
	.D      ( TM_A_px_bits_1_latched    ),
	.S      ( { i_9E_pin11, i_9E_pin3 } ),
	.mclk   ( i_MCLK                    ),
	.cen    ( CLK_INTL0                 ),
	.clr    ( 1'b0                      ),
	.R      ( 1'b0                      ),
	.L      ( 1'b0                      ),
	.Q      ( TM_A_px_bit_1_flipped     )
);

wire [7:0] TM_A_px_bit_1_flipped;

bus_ff #( .W( 8 ) ) U7(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_A_pixel_latch       ),
	.d       ( { i_H[2], i_G[2], i_F[2], i_E[2], i_D[2], i_C[2], i_B[2], i_A[2] } ),
	.q       ( TM_A_px_bits_2_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U8U9(
	.D      ( TM_A_px_bits_2_latched    ),
	.S      ( { i_9E_pin11, i_9E_pin3 } ),
	.mclk   ( i_MCLK                    ),
	.cen    ( CLK_INTL0                 ),
	.clr    ( 1'b0                      ),
	.R      ( 1'b0                      ),
	.L      ( 1'b0                      ),
	.Q      ( TM_A_px_bit_2_flipped     )
);

wire [7:0] TM_A_px_bit_2_flipped;

bus_ff #( .W( 8 ) ) U10(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_A_pixel_latch       ),
	.d       ( { i_H[3], i_G[3], i_F[3], i_E[3], i_D[3], i_C[3], i_B[3], i_A[3] } ),
	.q       ( TM_A_px_bits_3_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U11U12(
	.D      ( TM_A_px_bits_3_latched    ),
	.S      ( { i_9E_pin11, i_9E_pin3 } ),
	.mclk   ( i_MCLK                    ),
	.cen    ( CLK_INTL0                 ),
	.clr    ( 1'b0                      ),
	.R      ( 1'b0                      ),
	.L      ( 1'b0                      ),
	.Q      ( TM_A_px_bit_3_flipped     )
);

wire [7:0] TM_A_px_bit_3_flipped;

`ifdef SIMULATION

wire [0:3] db_TM_A_px_0_latched = { TM_A_px_bits_0_latched[0], TM_A_px_bits_1_latched[0], TM_A_px_bits_2_latched[0], TM_A_px_bits_3_latched[0] };
wire [0:3] db_TM_A_px_7_latched = { TM_A_px_bits_0_latched[7], TM_A_px_bits_1_latched[7], TM_A_px_bits_2_latched[7], TM_A_px_bits_3_latched[7] };

`endif

reg [3:0] TM_A_px_early;

always @( posedge i_MCLK ) begin
	case( i_AFF )

		1'b0:   TM_A_px_early <= { TM_A_px_bit_0_flipped[0], TM_A_px_bit_1_flipped[0], TM_A_px_bit_2_flipped[0], TM_A_px_bit_3_flipped[0] };
		1'b1:   TM_A_px_early <= { TM_A_px_bit_0_flipped[7], TM_A_px_bit_1_flipped[7], TM_A_px_bit_2_flipped[7], TM_A_px_bit_3_flipped[7] };
	endcase
end

`ifdef SIMULATION
	wire [3:0] u13_a = { TM_A_px_bit_0_flipped[0], TM_A_px_bit_1_flipped[0], TM_A_px_bit_2_flipped[0], TM_A_px_bit_3_flipped[0] };
	wire [3:0] u13_b = { TM_A_px_bit_0_flipped[7], TM_A_px_bit_1_flipped[7], TM_A_px_bit_2_flipped[7], TM_A_px_bit_3_flipped[7] };
`endif

lmn74194_nbit #( .N( 4 ) )
U14
(
	.D      ( 4'b1111           ),
	.S      ( 2'b01             ),
	.mclk   ( i_MCLK            ),
	.cen    ( CLK_INTL2         ),
	.clr    ( 1'b0              ),
	.R      ( TM_A_px_early[0]  ),
	.L      ( 1'b1              ),
	.Q      ( TM_A_px_0_delayed )
);

wire [3:0] TM_A_px_0_delayed;

lmn74194_nbit #( .N( 4 ) )
U15
(
	.D      ( 4'b1111           ),
	.S      ( 2'b01             ),
	.mclk   ( i_MCLK            ),
	.cen    ( CLK_INTL2         ),
	.clr    ( 1'b0              ),
	.R      ( TM_A_px_early[1]  ),
	.L      ( 1'b1              ),
	.Q      ( TM_A_px_1_delayed )
);

wire [3:0] TM_A_px_1_delayed;

lmn74194_nbit #( .N( 4 ) )
U34
(
	.D      ( 4'b1111           ),
	.S      ( 2'b01             ),
	.mclk   ( i_MCLK            ),
	.cen    ( CLK_INTL2         ),
	.clr    ( 1'b0              ),
	.R      ( TM_A_px_early[2]  ),
	.L      ( 1'b1              ),
	.Q      ( TM_A_px_2_delayed )
);

wire [3:0] TM_A_px_2_delayed;

lmn74194_nbit #( .N( 4 ) )
U16
(
	.D      ( 4'b1111           ),
	.S      ( 2'b01             ),
	.mclk   ( i_MCLK            ),
	.cen    ( CLK_INTL2         ),
	.clr    ( 1'b0              ),
	.R      ( TM_A_px_early[3]  ),
	.L      ( 1'b1              ),
	.Q      ( TM_A_px_3_delayed )
);

wire [3:0] TM_A_px_3_delayed;

assign o_TM_A_pixels = { TM_A_px_3_delayed[3], TM_A_px_2_delayed[3], TM_A_px_1_delayed[3], TM_A_px_0_delayed[3] };

assign o_TM_A_px_trans = (o_TM_A_pixels == 4'b0)  ?  1'b0 : 1'b1;

wire [7:0] TM_B_px_bits_0_latched;
wire [7:0] TM_B_px_bits_1_latched;
wire [7:0] TM_B_px_bits_2_latched;
wire [7:0] TM_B_px_bits_3_latched;

bus_ff #( .W( 8 ) ) U17(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_B_pixel_latch       ),
	.d       ( { i_H[0], i_G[0], i_F[0], i_E[0], i_D[0], i_C[0], i_B[0], i_A[0] } ),
	.q       ( TM_B_px_bits_0_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U18U19(
	.D      ( TM_B_px_bits_0_latched   ),
	.S      ( { i_9E_pin8, i_9E_pin6 } ),
	.mclk   ( i_MCLK                   ),
	.cen    ( CLK_INTL1                ),
	.clr    ( 1'b0                     ),
	.R      ( 1'b0                     ),
	.L      ( 1'b0                     ),
	.Q      ( TM_B_px_bit_0_flipped    )
);

wire [7:0] TM_B_px_bit_0_flipped;

bus_ff #( .W( 8 ) ) U20(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_B_pixel_latch       ),
	.d       ( { i_H[1], i_G[1], i_F[1], i_E[1], i_D[1], i_C[1], i_B[1], i_A[1] } ),
	.q       ( TM_B_px_bits_1_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U21U22(
	.D      ( TM_B_px_bits_1_latched    ),
	.S      ( { i_9E_pin8 , i_9E_pin6 } ),
	.mclk   ( i_MCLK                    ),
	.cen    ( CLK_INTL1                 ),
	.clr    ( 1'b0                      ),
	.R      ( 1'b0                      ),
	.L      ( 1'b0                      ),
	.Q      ( TM_B_px_bit_1_flipped     )
);

wire [7:0] TM_B_px_bit_1_flipped;

bus_ff #( .W( 8 ) ) U23(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_B_pixel_latch       ),
	.d       ( { i_H[2], i_G[2], i_F[2], i_E[2], i_D[2], i_C[2], i_B[2], i_A[2] } ),
	.q       ( TM_B_px_bits_2_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U24U25(
	.D      ( TM_B_px_bits_2_latched   ),
	.S      ( { i_9E_pin8, i_9E_pin6 } ),
	.mclk   ( i_MCLK                   ),
	.cen    ( CLK_INTL1                ),
	.clr    ( 1'b0                     ),
	.R      ( 1'b0                     ),
	.L      ( 1'b0                     ),
	.Q      ( TM_B_px_bit_2_flipped    )
);

wire [7:0] TM_B_px_bit_2_flipped;

bus_ff #( .W( 8 ) ) U26(
	.rst     ( i_RST                  ),
	.clk     ( i_MCLK                 ),
	.trig    ( TM_B_pixel_latch       ),
	.d       ( { i_H[3], i_G[3], i_F[3], i_E[3], i_D[3], i_C[3], i_B[3], i_A[3] } ),
	.q       ( TM_B_px_bits_3_latched ),
	.q_n     (                        )
);

lmn74194_nbit #( .N( 8 ) )
U27U28(
	.D      ( TM_B_px_bits_3_latched   ),
	.S      ( { i_9E_pin8, i_9E_pin6 } ),
	.mclk   ( i_MCLK                   ),
	.cen    ( CLK_INTL1                ),
	.clr    ( 1'b0                     ),
	.R      ( 1'b0                     ),
	.L      ( 1'b0                     ),
	.Q      ( TM_B_px_bit_3_flipped    )
);

wire [7:0] TM_B_px_bit_3_flipped;

`ifdef SIMULATION

wire [0:3] db_TM_B_px_0_latched = { TM_B_px_bits_0_latched[0], TM_B_px_bits_1_latched[0], TM_B_px_bits_2_latched[0], TM_B_px_bits_3_latched[0] };
wire [0:3] db_TM_B_px_7_latched = { TM_B_px_bits_0_latched[7], TM_B_px_bits_1_latched[7], TM_B_px_bits_2_latched[7], TM_B_px_bits_3_latched[7] };

`endif

always @( posedge i_MCLK ) begin
	case( i_BFF )

		1'b0:   o_TM_B_pixels <= { TM_B_px_bit_0_flipped[0], TM_B_px_bit_1_flipped[0], TM_B_px_bit_2_flipped[0], TM_B_px_bit_3_flipped[0] };
		1'b1:   o_TM_B_pixels <= { TM_B_px_bit_0_flipped[7], TM_B_px_bit_1_flipped[7], TM_B_px_bit_2_flipped[7], TM_B_px_bit_3_flipped[7] };
	endcase
end

assign o_TM_B_px_trans = (o_TM_B_pixels == 4'b0)  ?  1'b0 : 1'b1;

endmodule
