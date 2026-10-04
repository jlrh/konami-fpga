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

module gx400_priority_handler
(
	input      [3:0]  i_TM_A_PR,
	input      [1:0]  i_TM_B_PR,
	input      [3:0]  i_OBJ_COLOR,
	input             i_TM_A_PX_TRANS,
	input             i_TM_B_PX_TRANS,

	output            o_S0_n,
	output            o_S1_n
);

wire       obj_px_trans = |{ i_OBJ_COLOR };

reg  [4:0] tm_mode;
reg  [1:0] tm_select;

`define TMM_A        5'd0
`define TMM_A_B      5'd1
`define TMM_A_B_O    5'd2
`define TMM_A_BMO    5'd3
`define TMM_A_O1     5'd4
`define TMM_A_O2     5'd5
`define TMM_A_O_B    5'd6
`define TMM_B        5'd7
`define TMM_B_A      5'd8
`define TMM_B_A_O    5'd9
`define TMM_B_O      5'd10
`define TMM_B_O_A    5'd11
`define TMM_O        5'd12
`define TMM_O_A      5'd13
`define TMM_O_A_B    5'd14
`define TMM_O_B      5'd15
`define TMM_O_B_A    5'd16
`define TMM_A_BMO_B  5'd17
`define TMM_APB_O    5'd18
`define TMM_APB_O_A  5'd19
`define TMM_B_AMO    5'd20
`define TMM_B_AMO_A  5'd21
`define TMM_BPA_O    5'd22
`define TMM_BPA_O_B  5'd23
`define TMM_O_APB    5'd24
`define TMM_O_BPA    5'd25

always @(*) begin
	casez( { i_TM_B_PR[1:0], i_TM_A_PR[3:0] } )

		6'b??0101:  tm_mode = `TMM_A;
		6'b?11101:  tm_mode = `TMM_A_B;
		6'b?11111:  tm_mode = `TMM_A_B_O;
		6'b001101:  tm_mode = `TMM_A_BMO;
		6'b??0111:  tm_mode = `TMM_A_O1;
		6'b001111:  tm_mode = `TMM_A_O2;
		6'b101111:  tm_mode = `TMM_A_O_B;
		6'b0100??:  tm_mode = `TMM_B;
		6'b0110?1:  tm_mode = `TMM_B_A;
		6'b1110?1:  tm_mode = `TMM_B_A_O;
		6'b1100??:  tm_mode = `TMM_B_O;
		6'b111000:  tm_mode = `TMM_B_O;
		6'b111010:  tm_mode = `TMM_B_O_A;
		6'b0000??:  tm_mode = `TMM_O;
		6'b001?00:  tm_mode = `TMM_O;
		6'b??0100:  tm_mode = `TMM_O;
		6'b??0110:  tm_mode = `TMM_O_A;
		6'b001110:  tm_mode = `TMM_O_A;
		6'b101110:  tm_mode = `TMM_O_A_B;
		6'b1000??:  tm_mode = `TMM_O_B;
		6'b101000:  tm_mode = `TMM_O_B;
		6'b101010:  tm_mode = `TMM_O_B_A;
		6'b101101:  tm_mode = `TMM_A_BMO_B;
		6'b?11100:  tm_mode = `TMM_APB_O;
		6'b?11110:  tm_mode = `TMM_APB_O_A;
		6'b011000:  tm_mode = `TMM_B_AMO;
		6'b011010:  tm_mode = `TMM_B_AMO_A;
		6'b0010?1:  tm_mode = `TMM_BPA_O;
		6'b1010?1:  tm_mode = `TMM_BPA_O_B;
		6'b101100:  tm_mode = `TMM_O_APB;
		6'b001010:  tm_mode = `TMM_O_BPA;
	endcase

	case( tm_mode )

		`TMM_A: tm_select = {
				1'b1,
				1'b0
			};

		`TMM_A_B: tm_select = {
				1'b1,
				~i_TM_A_PX_TRANS & i_TM_B_PX_TRANS
			};

		`TMM_A_B_O: tm_select = {
				~&{ ~i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS, obj_px_trans },
				~i_TM_A_PX_TRANS & i_TM_B_PX_TRANS
			};

		`TMM_A_BMO: tm_select = {
				~&{ ~i_TM_A_PX_TRANS, i_TM_B_PX_TRANS },
				1'b0
			};

		`TMM_A_O1: tm_select = {
				~&{ ~i_TM_A_PX_TRANS, obj_px_trans },
				1'b0
			};

		`TMM_A_O2: tm_select = {
				i_TM_A_PX_TRANS | ( ~i_TM_B_PX_TRANS & ~obj_px_trans ),
				1'b0
			};

		`TMM_A_O_B: tm_select = {
				~&{ ~i_TM_A_PX_TRANS, obj_px_trans },
				~i_TM_A_PX_TRANS & i_TM_B_PX_TRANS
			};

		`TMM_B: tm_select = {
				1'b1,
				1'b1
			};

		`TMM_B_A: tm_select = {
				1'b1,
				~&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS }
			};

		`TMM_B_A_O: tm_select = {
				~&{ ~i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS },
				i_TM_B_PX_TRANS
			};

		`TMM_B_O: tm_select = {
				i_TM_B_PX_TRANS,
				1'b1
			};

		`TMM_B_O_A: tm_select = {
				i_TM_B_PX_TRANS | i_TM_A_PX_TRANS & ~obj_px_trans,
				~&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS }
			};

		`TMM_O: tm_select = {
				1'b0,
				1'b0
			};

		`TMM_O_A: tm_select = {
				&{ i_TM_A_PX_TRANS, ~obj_px_trans },
				1'b0
			};

		`TMM_O_A_B: tm_select = {
				i_TM_A_PX_TRANS & ~obj_px_trans | i_TM_B_PX_TRANS & ~obj_px_trans,
				~i_TM_A_PX_TRANS
			};

		`TMM_O_B: tm_select = {
				&{ i_TM_B_PX_TRANS, ~obj_px_trans },
				1'b1
			};

		`TMM_O_B_A: tm_select = {
				i_TM_A_PX_TRANS & ~obj_px_trans | i_TM_B_PX_TRANS & ~obj_px_trans,
				~&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS }
			};

		`TMM_A_BMO_B: tm_select = {
				~&{ ~i_TM_A_PX_TRANS, i_TM_B_PX_TRANS, obj_px_trans },
				~i_TM_A_PX_TRANS & i_TM_B_PX_TRANS
			};

		`TMM_APB_O: tm_select = {
				&{ ~i_TM_A_PX_TRANS, i_TM_B_PX_TRANS },
				1'b1
			};

		`TMM_APB_O_A: tm_select = {
				i_TM_A_PX_TRANS & ~obj_px_trans | ~i_TM_A_PX_TRANS & i_TM_B_PX_TRANS,
				~i_TM_A_PX_TRANS
			};

		`TMM_B_AMO: tm_select = {
				~&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS },
				1'b1
			};

		`TMM_B_AMO_A: tm_select = {
				~&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS, obj_px_trans },
				~&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS }
			};

		`TMM_BPA_O: tm_select = {
				&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS },
				1'b0
			};

		`TMM_BPA_O_B: tm_select = {
				i_TM_A_PX_TRANS & ~i_TM_B_PX_TRANS  | i_TM_B_PX_TRANS & ~obj_px_trans,
				i_TM_B_PX_TRANS & ~obj_px_trans
			};

		`TMM_O_APB: tm_select = {
				&{ ~i_TM_A_PX_TRANS, i_TM_B_PX_TRANS, ~obj_px_trans },
				1'b1
			};

		`TMM_O_BPA: tm_select = {
				&{ i_TM_A_PX_TRANS, ~i_TM_B_PX_TRANS, ~obj_px_trans },
				1'b0
			};
	endcase
end

assign o_S1_n = tm_select[1];
assign o_S0_n = tm_select[0];

endmodule
