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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Rafael Eduardo Paiva Feener. Copyright: Miki Saito
    Version: 1.0
    Date: 30-9-2024 */

module jtasterix_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,

    input             lhbl,
    input             lvbl,

    input             pcu_cs,
    input             alpha_cs,
    input             pal_cs,
    input             cpu_we,
    input      [15:0] cpu_dout,
    input      [ 7:0] cpu_d8,
    input      [ 1:0] cpu_dsn,
    input      [12:1] cpu_addr,
    output     [15:0] cpu_din,

    input      [ 7:0] lyrf_pxl,
    input      [ 7:0] lyra_pxl,
    input      [ 7:0] lyrb_pxl,
    input      [ 7:0] lyrc_pxl,
    input      [ 8:0] lyro_pxl,
    input      [ 4:0] lyro_pri,

    input      [ 1:0] shadow,
    input      [ 2:0] dim,
    input             dimmod,
    input             dimpol,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    input      [11:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,
    output     [ 7:0] dump_mmr,

    input      [ 7:0] debug_bus
);

wire _unused = &{1'b0, alpha_cs, cpu_d8, dim, dimmod, dimpol, ioctl_addr[11:4], 1'b0};

wire [15:0] pal_q, pal_rd;
reg  [23:0] bgr;
reg  [ 7:0] r8, g8, b8;
wire [ 7:0] pr8, pg8, pb8;
wire [10:0] pal_addr;
wire        shad, pcu_we, k251_coln;

wire [ 5:0] pri1s;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4;
wire [ 1:0] shd_out, shd_in;

function [7:0] pal5(input [4:0] v); pal5 = {v,v[4:2]}; endfunction
assign pr8 = pal5( pal_rd[ 4: 0] );
assign pg8 = pal5( pal_rd[ 9: 5] );
assign pb8 = pal5( pal_rd[14:10] );

wire [10:0] cpu_cidx = cpu_addr[11:1];
wire        we_pal   = pal_cs & cpu_we;
assign pcu_we    = pcu_cs & ~cpu_dsn[0] & cpu_we;
assign cpu_din   = pal_q;
assign ioctl_din = 8'd0;

assign {blue,green,red} = (lvbl & lhbl) ? bgr : 24'd0;

assign pri1s = {lyro_pri,1'b0};
assign ci0   = {1'b0, lyrf_pxl};
assign ci1   =  lyro_pxl;
assign ci2   = {1'b0, lyra_pxl};
assign ci3   =  8'd0;
assign ci4   =  lyrc_pxl;

assign shd_in= shadow;

jtcolmix_053251 u_k251(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),

    .sel        ( 1'b0      ),
    .pri0       ( 6'h3f     ),
    .pri1       ( pri1s     ),
    .pri2       ( 6'h3f     ),

    .ci0        ( ci0       ),
    .ci1        ( ci1       ),
    .ci2        ( ci2       ),
    .ci3        ( ci3       ),
    .ci4        ( ci4       ),

    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out   ),

    .ioctl_addr ( ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0] ),
    .ioctl_din  ( dump_mmr  ),

    .cout       ( pal_addr  ),
    .brit       (           ),
    .col_n      ( k251_coln )
);

reg  [ 2:0] fix_cbase;
always @(posedge clk, posedge rst) begin
    if(rst) fix_cbase <= 3'd0;
    else if(pcu_we && cpu_addr[4:1]==4'ha) fix_cbase <= cpu_dout[2:0];
end

wire [ 7:0] lyrb_d;
wire        fix_op = |lyrb_d[3:0];

assign      shad   = |shd_out & ~fix_op;
wire [10:0] fix_idx  = {fix_cbase, lyrb_d};
wire [10:0] pal_amux = fix_op ? fix_idx : pal_addr;
jtframe_sh #(.W(8),.L(2)) u_fixdly(.clk(clk),.clk_en(pxl_cen),.din(lyrb_pxl),.drop(lyrb_d));

wire        use_bg  = k251_coln & ~fix_op;
wire [10:0] rd_idx  = use_bg ? 11'd0 : pal_amux;

jtframe_dual_ram #(.DW(16),.AW(11),.SIMFILE("pal.bin")) u_pal(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_cidx ), .we0( we_pal ), .q0( pal_q  ),
    .clk1( clk ), .data1( 16'd0    ), .addr1( rd_idx   ), .we1( 1'b0   ), .q1( pal_rd )
);

function [7:0] shd06(input [7:0] c);
    reg [23:0] m;
    begin
        m      = {16'd0, c} * 24'd39322;
        shd06  = m[23:16];
    end
endfunction
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        { r8, g8, b8 } <= 0;
        bgr <= 0;
    end else begin
        { r8, g8, b8 } <= { pr8, pg8, pb8 };
        if( pxl_cen )
            bgr <= ~shad ? { b8, g8, r8 }
                         : { shd06(b8), shd06(g8), shd06(r8) };
    end
end

`ifdef SIMULATION

integer ps_frame = 0;
reg     ps_lvbl_l = 0;
always @(posedge clk) begin
    ps_lvbl_l <= lvbl;
    if( lvbl && !ps_lvbl_l ) ps_frame <= ps_frame + 1;
end

always @(posedge clk) if( we_pal && cpu_cidx>=11'd1024 && cpu_cidx<11'd1536 )
    $display("PAL-SPR: frame=%0d idx=%0d(0x%03x) data=%04x", ps_frame, cpu_cidx, cpu_cidx, cpu_dout);
`endif

endmodule
