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

module xexex_colmix(
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

    input             lyra_mix, lyrb_mix, lyrc_mix,
    input      [ 8:0] lyro_pxl,
    input      [ 4:0] lyro_pri,

    input      [ 1:0] shadow,
    input             alpha_off,
    input      [ 8:0] lvc_pxl,
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

wire [ 7:0] pal_r, pal_g, pal_b;
wire [ 7:0] cr, cg, cb, cx;
reg  [23:0] bgr;
reg  [ 7:0] r8, b8, g8;
wire [10:0] pal_addr;
wire        shad, pcu_we, nc, k251_coln;

wire [ 5:0] pri1;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4;
wire [ 1:0] shd_out, shd_in;

wire [10:0] cout_b;
wire        coln_b;
wire [ 7:0] pal_r2, pal_g2, pal_b2;
wire        front_a, front_b, front_c;
reg  [ 5:0] pri_a, pri_b, pri_c;
wire        do_blend;
wire [23:0] blended_bgr;

wire [10:0] cpu_cidx = cpu_addr[12:2];
wire        we_r = pal_cs & cpu_we & ~cpu_addr[1] & ~cpu_dsn[0];
wire        we_g = pal_cs & cpu_we &  cpu_addr[1] & ~cpu_dsn[1];
wire        we_b = pal_cs & cpu_we &  cpu_addr[1] & ~cpu_dsn[0];

wire        we_x = pal_cs & cpu_we & ~cpu_addr[1] & ~cpu_dsn[1];
assign pcu_we    = pcu_cs & ~cpu_dsn[0] & cpu_we;
assign cpu_din   = cpu_addr[1] ? {cg, cb} : {cx, cr};
assign ioctl_din = 8'd0;

assign {blue,green,red} = (lvbl & lhbl ) ? (do_blend ? blended_bgr : (use_bg ? bg_bgr : bgr)) : 24'd0;

wire [ 5:0] pri0s = {lyro_pri,1'b0};
assign pri1      = 6'h3f;
assign ci0       =  lyro_pxl;
assign ci1       =  lvc_pxl;

wire   cur_alpha = ~alpha_off;
assign ci2       = (cur_alpha & lyra_mix) ? 9'd0 : {1'b0, lyra_pxl};
assign ci3       =  lyrb_pxl;
assign ci4       =  lyrc_pxl;
assign shad      = |shd_out;
assign shd_in    =  shadow;

wire [ 7:0] lyrf_d;
wire        fix_op = |lyrf_d[3:0];
wire [10:0] pal_amux = fix_op ? {3'b111, lyrf_d} : pal_addr;
jtframe_sh #(.W(8),.L(2)) u_fixdly(.clk(clk),.clk_en(pxl_cen),.din(lyrf_pxl),.drop(lyrf_d));

reg  [15:0] k38[0:15];

always @(posedge clk, posedge rst) begin : k38_rst
    integer ai;
    if(rst) for(ai=0;ai<16;ai=ai+1) k38[ai]<=16'd0;
    else if(alpha_cs & cpu_we) k38[cpu_addr[4:1]] <= cpu_dout;
end

wire [23:0] bg_bgr   = { k38[1][7:0], k38[1][15:8], k38[0][7:0] };

wire        alpha_en = 1'b1;
wire [ 4:0] mixlv    = k38[13][4:0];
wire [ 7:0] alpha_lv = {mixlv, mixlv[4:2]};

wire        lyra_mix_d;
jtframe_sh #(.W(1),.L(1)) u_mixdly(.clk(clk),.clk_en(pxl_cen),.din(lyra_mix),.drop(lyra_mix_d));
wire        mix_front = lyra_mix_d;

always @(posedge clk, posedge rst) begin
    if(rst) begin pri_a<=0; pri_b<=0; pri_c<=0; end
    else if(pcu_we) case(cpu_addr[4:1])
        4'd2: pri_a <= cpu_dout[5:0];
        4'd3: pri_b <= cpu_dout[5:0];
        4'd4: pri_c <= cpu_dout[5:0];
        default:;
    endcase
end

reg [1:0] sl0, sl1, sl2; reg [5:0] sp0, sp1, sp2;
always @* begin
    sl0=2'd0; sl1=2'd1; sl2=2'd2; sp0=pri_a; sp1=pri_b; sp2=pri_c;
    if(sp0<sp1) begin {sp0,sp1}={sp1,sp0}; {sl0,sl1}={sl1,sl0}; end
    if(sp0<sp2) begin {sp0,sp2}={sp2,sp0}; {sl0,sl2}={sl2,sl0}; end
    if(sp1<sp2) begin {sp1,sp2}={sp2,sp1}; {sl1,sl2}={sl2,sl1}; end
end
assign front_a = sl2==2'd0;
assign front_b = sl2==2'd1;
assign front_c = sl2==2'd2;

wire [15:0] shdR = shd_out==2'd1 ? k38[2] : shd_out==2'd2 ? k38[5] : k38[ 8];
wire [15:0] shdG = shd_out==2'd1 ? k38[3] : shd_out==2'd2 ? k38[6] : k38[ 9];
wire [15:0] shdB = shd_out==2'd1 ? k38[4] : shd_out==2'd2 ? k38[7] : k38[10];

function [7:0] shd_add( input [7:0] c, input [15:0] rg );
    reg signed [10:0] d, s;
    begin
        d = $signed({{2{rg[8]}}, rg[8:0]});
        s = $signed({3'b0, c}) + d;
        shd_add = s[10]      ? 8'd0   :
                  (s > 255)  ? 8'd255 : s[7:0];
    end
endfunction

function [7:0] blend8( input [7:0] fr, input [7:0] bk, input [7:0] a );
    reg [16:0] num; reg [31:0] mul;
    begin

        num = fr*a + bk*(9'd256 - {1'b0,a});
        mul = {15'd0, num};
        blend8 = num[15:8];
    end
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bgr   <= 0;
    end else begin
        { b8, g8, r8 } <= { pal_b, pal_g, pal_r };
        if( pxl_cen ) bgr <= ~shad ? { b8, g8, r8 }
                                   : { shd_add(b8,shdB), shd_add(g8,shdG), shd_add(r8,shdR) };
    end
end

k053251 #(.MAME_PRI(1)) u_k251(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),

    .sel        ( 1'b0      ),
    .pri0       ( pri0s     ),
    .pri1       ( pri1      ),
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

wire coln_a, fixop_a;

jtframe_sh #(.W(1),.L(1)) u_colndly(.clk(clk),.clk_en(pxl_cen),.din(k251_coln),.drop(coln_a ));
jtframe_sh #(.W(1),.L(1)) u_fopdly (.clk(clk),.clk_en(pxl_cen),.din(fix_op),   .drop(fixop_a));
wire use_bg = coln_a & ~fixop_a;

jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_r.bin")) u_pal_r(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_r ), .q0( cr    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1( pal_r )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_g.bin")) u_pal_g(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_g ), .q0( cg    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1( pal_g )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_b.bin")) u_pal_b(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_b ), .q0( cb    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1( pal_b )
);

jtframe_dual_ram #(.DW(8),.AW(11)) u_pal_x(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_x ), .q0( cx    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1(       )
);

wire [8:0] ci2b = {1'b0, lyra_pxl};
wire [7:0] ci3b = 8'd0;
wire [7:0] ci4b = 8'd0;
wire [1:0] shd_out_b;

k053251 #(.MAME_PRI(1)) u_k251_back(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),
    .sel        ( 1'b0      ),
    .pri0       ( pri0s     ),
    .pri1       ( pri1      ),
    .pri2       ( 6'h3f     ),
    .ci0        ( 9'd0      ),
    .ci1        ( 9'd0      ),
    .ci2        ( ci2b      ),
    .ci3        ( ci3b      ),
    .ci4        ( ci4b      ),
    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out_b ),
    .ioctl_addr ( 4'd0      ),
    .ioctl_din  (           ),
    .cout       ( cout_b    ),
    .brit       (           ),
    .col_n      ( coln_b    )
);

jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_r.bin")) u_pal_r2(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_r ), .q0(         ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( cout_b   ), .we1( 1'b0 ), .q1( pal_r2 )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_g.bin")) u_pal_g2(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_g ), .q0(         ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( cout_b   ), .we1( 1'b0 ), .q1( pal_g2 )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_b.bin")) u_pal_b2(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_b ), .q0(         ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( cout_b   ), .we1( 1'b0 ), .q1( pal_b2 )
);

reg  [ 7:0] br8, bg8, bb8;
reg  [23:0] back_bgr;
always @(posedge clk, posedge rst) begin
    if( rst ) begin { br8,bg8,bb8 } <= 0; back_bgr <= 0; end
    else begin
        { bb8, bg8, br8 } <= { pal_b2, pal_g2, pal_r2 };
        if( pxl_cen ) back_bgr <= { bb8, bg8, br8 };
    end
end

wire       blend_en_now = alpha_en & cur_alpha & mix_front & ~coln_b & (alpha_lv != 8'd0);
wire       blend_en_a, colnb_a;
jtframe_sh #(.W(1),.L(1)) u_blenddly(.clk(clk),.clk_en(pxl_cen),.din(blend_en_now),.drop(blend_en_a));
jtframe_sh #(.W(1),.L(1)) u_colnbdly(.clk(clk),.clk_en(pxl_cen),.din(coln_b     ),.drop(colnb_a  ));
assign do_blend = blend_en_a & ~fixop_a;

wire [23:0] base_sel   = use_bg ? bg_bgr : bgr;
assign blended_bgr = { blend8(back_bgr[23:16], base_sel[23:16], alpha_lv),
                       blend8(back_bgr[15: 8], base_sel[15: 8], alpha_lv),
                       blend8(back_bgr[ 7: 0], base_sel[ 7: 0], alpha_lv) };

endmodule