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

module mystwarr_k055673(
    input             rst,
    input             clk,

    input             objsys_cs,
    input             objreg_cs,
    input             obj46_cs,
    input             objrom_cs,

    input      [15:1] main_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    output     [15:0] oram_dout,
    output     [15:0] objrom_dout,

    input      [10:0] list_addr,
    output     [15:0] list_dout,

    output     [63:0] kx46_dbg,
    output    [127:0] kx47_dbg
);

wire        chip_sel = main_addr[7:4]==4'h0;
wire [10:0] chip_idx = { main_addr[15:8], main_addr[3:1] };

wire [1:0]  wen      = {2{cpu_we}} & ~cpu_dsn;
wire [1:0]  we_chip  = (objsys_cs &  chip_sel) ? wen : 2'b00;
wire [1:0]  we_scat  = (objsys_cs & ~chip_sel) ? wen : 2'b00;

wire [15:0] q_chip, q_scat;
assign oram_dout = chip_sel ? q_chip : q_scat;

jtframe_dual_ram16 #(.AW(15)) u_scat(
    .clk0( clk ), .data0( cpu_dout ), .addr0( main_addr ), .we0( we_scat ), .q0( q_scat ),
    .clk1( clk ), .data1( 16'd0    ), .addr1( 15'd0     ), .we1( 2'd0    ), .q1(        )
);

jtframe_dual_ram16 #(.AW(11)) u_chip(
    .clk0( clk ), .data0( cpu_dout ), .addr0( chip_idx  ), .we0( we_chip ), .q0( q_chip ),
    .clk1( clk ), .data1( 16'd0    ), .addr1( list_addr ), .we1( 2'd0    ), .q1( list_dout )
);

reg [7:0] kx46 [0:7];
always @(posedge clk, posedge rst) begin: kx46_rst
    integer bi;
    if( rst ) for( bi=0; bi<8; bi=bi+1 ) kx46[bi] <= 8'd0;
    else if( obj46_cs & cpu_we ) begin
        if( ~cpu_dsn[1] ) kx46[{main_addr[2:1],1'b0}] <= cpu_dout[15:8];
        if( ~cpu_dsn[0] ) kx46[{main_addr[2:1],1'b1}] <= cpu_dout[ 7:0];
    end
end

reg [15:0] kx47 [0:7];
always @(posedge clk, posedge rst) begin: kx47_rst
    integer wi;
    if( rst ) for( wi=0; wi<8; wi=wi+1 ) kx47[wi] <= 16'd0;
    else if( objreg_cs & cpu_we ) kx47[main_addr[3:1]] <= cpu_dout;
end

assign kx46_dbg = { kx46[7], kx46[6], kx46[5], kx46[4], kx46[3], kx46[2], kx46[1], kx46[0] };
assign kx47_dbg = { kx47[7], kx47[6], kx47[5], kx47[4], kx47[3], kx47[2], kx47[1], kx47[0] };

assign objrom_dout = 16'd0;

endmodule
