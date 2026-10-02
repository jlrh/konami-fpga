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

module mystwarr_palette(
    input             rst,
    input             clk,

    input      [12:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,
    input             pal_cs,
    output     [15:0] pal_dout,

    input      [10:0] pal_addr,
    output     [ 7:0] pal_r, pal_g, pal_b,

    input      [10:0] pal2_addr,
    output     [ 7:0] pal2_r, pal2_g, pal2_b
);

wire [10:0] cpu_cidx = cpu_addr[12:2];
wire        cpu_weg  = pal_cs & cpu_we;
wire        we_r = cpu_weg & ~cpu_addr[1] & ~cpu_dsn[0];
wire        we_g = cpu_weg &  cpu_addr[1] & ~cpu_dsn[1];
wire        we_b = cpu_weg &  cpu_addr[1] & ~cpu_dsn[0];
wire        we_x = cpu_weg & ~cpu_addr[1] & ~cpu_dsn[1];
wire [ 7:0] cr, cg, cb, cx;

assign pal_dout = cpu_addr[1] ? {cg, cb} : {cx, cr};

jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_r.bin")) u_pal_r(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_r ), .q0( cr    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_addr ), .we1( 1'b0 ), .q1( pal_r )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_g.bin")) u_pal_g(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_g ), .q0( cg    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_addr ), .we1( 1'b0 ), .q1( pal_g )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_b.bin")) u_pal_b(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_b ), .q0( cb    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_addr ), .we1( 1'b0 ), .q1( pal_b )
);

jtframe_dual_ram #(.DW(8),.AW(11)) u_pal_x(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_x ), .q0( cx    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_addr ), .we1( 1'b0 ), .q1(       )
);

jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_r.bin")) u_pal_r2(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_r ), .q0(       ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal2_addr), .we1( 1'b0 ), .q1( pal2_r )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_g.bin")) u_pal_g2(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_g ), .q0(       ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal2_addr), .we1( 1'b0 ), .q1( pal2_g )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_b.bin")) u_pal_b2(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_b ), .q0(       ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal2_addr), .we1( 1'b0 ), .q1( pal2_b )
);

endmodule
