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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.  */

module mystwarr_obj_dma(
    input             rst,
    input             clk,

    input             dma_en,
    input             desc_sort,

    input             hs,
    input             lvbl,

    output reg [10:0] list_addr,
    input      [15:0] list_din,

    output            dma_bsy,

    input      [ 9:0] scan_addr,
    output     [15:0] scan_even,
    output     [15:0] scan_odd
);

reg  [1:0] lvbl_sh;
reg        hsl;
wire       hs_pos  = hs & ~hsl;
wire       trigger = dma_en & (lvbl_sh==2'b10) & hs_pos;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        hsl <= 1'b0; lvbl_sh <= 2'b00;
    end else begin
        hsl <= hs;
        if( hs_pos ) lvbl_sh <= { lvbl_sh[0], lvbl };
    end
end

localparam ST_IDLE=3'd0, ST_CLEAR=3'd1, ST_ADDR=3'd2, ST_WAIT=3'd3, ST_DATA=3'd4;
reg  [2:0]  st;
reg  [10:0] clr_idx;
reg  [7:0]  entry;
reg  [2:0]  sub;
reg  [7:0]  zcode_r;
reg         active_r;

reg [10:0] we_addr;
reg [15:0] we_data;
reg        we;

assign dma_bsy = st != ST_IDLE;

wire [7:0] slot_w0 = desc_sort ? list_din[7:0] : ~list_din[7:0];

always @(posedge clk, posedge rst) begin: fsm
    if( rst ) begin
        st       <= ST_IDLE;
        list_addr<= 11'd0;
        clr_idx  <= 11'd0;
        entry    <= 8'd0;
        sub      <= 3'd0;
        zcode_r  <= 8'd0;
        active_r <= 1'b0;
        we       <= 1'b0;
        we_addr  <= 11'd0;
        we_data  <= 16'd0;
    end else begin
        we <= 1'b0;
        case( st )
            ST_IDLE: if( trigger ) begin
                st      <= ST_CLEAR;
                clr_idx <= 11'd0;
            end
            ST_CLEAR: begin
                we      <= 1'b1;
                we_addr <= clr_idx;
                we_data <= 16'd0;
                clr_idx <= clr_idx + 11'd1;
                if( clr_idx == 11'h7ff ) begin
                    st    <= ST_ADDR;
                    entry <= 8'd0;
                    sub   <= 3'd0;
                end
            end
            ST_ADDR: begin
                list_addr <= { entry, sub };
                st        <= ST_WAIT;
            end
            ST_WAIT: st <= ST_DATA;
            ST_DATA: begin

                if( sub == 3'd0 ) begin
                    active_r <= list_din[15];
                    zcode_r  <= slot_w0;
                    we       <= list_din[15];
                    we_addr  <= { slot_w0, 3'd0 };
                    we_data  <= list_din;
                end else begin
                    we      <= active_r;
                    we_addr <= { zcode_r, sub };
                    we_data <= list_din;
                end
                if( sub == 3'd7 ) begin
                    sub <= 3'd0;
                    if( entry == 8'hff ) st <= ST_IDLE;
                    else begin
                        entry <= entry + 8'd1;
                        st    <= ST_ADDR;
                    end
                end else begin
                    sub <= sub + 3'd1;
                    st  <= ST_ADDR;
                end
            end
            default: st <= ST_IDLE;
        endcase
    end
end

wire [9:0] we_pair_addr = { we_addr[10:3], we_addr[2:1] };
wire       we_even      = we & ~we_addr[0];
wire       we_odd       = we &  we_addr[0];

jtframe_dual_ram16 #(.AW(10)) u_even(
    .clk0( clk ), .data0( we_data ), .addr0( we_pair_addr ), .we0( {2{we_even}} ), .q0(          ),
    .clk1( clk ), .data1( 16'd0   ), .addr1( scan_addr     ), .we1( 2'd0        ), .q1( scan_even )
);

jtframe_dual_ram16 #(.AW(10)) u_odd(
    .clk0( clk ), .data0( we_data ), .addr0( we_pair_addr ), .we0( {2{we_odd}}  ), .q0(          ),
    .clk1( clk ), .data1( 16'd0   ), .addr1( scan_addr     ), .we1( 2'd0        ), .q1( scan_odd  )
);

endmodule
