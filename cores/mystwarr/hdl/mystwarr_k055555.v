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

module mystwarr_k055555(
    input             rst,
    input             clk,

    input             pcu_cs,
    input      [ 6:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    input      [ 8:0] lyrf_pxl,
    input      [ 8:0] lyra_pxl, lyrb_pxl, lyrc_pxl,
    input      [ 1:0] lyra_mix, lyrb_mix, lyrc_mix,

    input      [ 4:0] obj_pen,
    input      [ 4:0] obj_color,
    input      [ 7:0] obj_pri,
    input      [ 1:0] obj_shd,

    input      [23:0] bg_bgr,

    input      [ 8:0] shd1_r, shd1_g, shd1_b,
    input      [ 8:0] shd2_r, shd2_g, shd2_b,
    input      [ 8:0] shd3_r, shd3_g, shd3_b,
    input      [ 7:0] alpha_lv1, alpha_lv2, alpha_lv3,
    input             add1, add2, add3,
    input      [ 7:0] bri_lv1, bri_lv2, bri_lv3,

    output     [10:0] pal_addr,
    input      [ 7:0] pal_r, pal_g, pal_b,
    output     [10:0] pal2_addr,
    input      [ 7:0] pal2_r, pal2_g, pal2_b,

    output     [ 7:0] red, green, blue
);

reg [7:0] r [0:45];
wire       byte_lds_only = (cpu_dsn == 2'b10);
wire [7:0] wr_data        = byte_lds_only ? cpu_dout[7:0] : cpu_dout[15:8];
wire       wr_en          = pcu_cs & cpu_we & (cpu_dsn != 2'b11) & (cpu_addr < 6'd46);

always @(posedge clk, posedge rst) begin : r_rst
    integer ri;
    if(rst) for(ri=0; ri<46; ri=ri+1) r[ri] <= 8'd0;
    else if(wr_en) r[cpu_addr] <= wr_data;
end

wire [7:0] r_a_pri = r[7],  r_b_pri = r[10], r_c_pri = r[13], r_d_pri = r[14];
wire [7:0] r_a_pal = r[23], r_b_pal = r[24], r_c_pal = r[25], r_d_pal = r[26];
wire [7:0] r_obj_pal = r[27];
wire [7:0] r_vbri    = r[42];

wire [7:0] r_osbri    = r[43];
wire [7:0] r_osbri_on = r[44];
wire [7:0] r_shd1_pri = r[37], r_shd2_pri = r[38], r_shd3_pri = r[39];
wire [7:0] r_shdprisel = r[41];
wire [7:0] r_inpen   = r[45];

wire en_a = r_inpen[0], en_b = r_inpen[1], en_c = r_inpen[2], en_d = r_inpen[3], en_o = r_inpen[4];

wire [7:0] r_vinmix = r[33], r_vmixon = r[34];

function [1:0] mix_efectivo(input [1:0] tile_mix, input [1:0] vinmix, input [1:0] vmixon);
    mix_efectivo = (tile_mix != 2'd0) ? (tile_mix & ~vmixon) : (vinmix & vmixon);
endfunction

wire [1:0] mixef_b = mix_efectivo(lyra_mix, r_vinmix[3:2], r_vmixon[3:2]);
wire [1:0] mixef_c = mix_efectivo(lyrb_mix, r_vinmix[5:4], r_vmixon[5:4]);
wire [1:0] mixef_d = mix_efectivo(lyrc_mix, r_vinmix[7:6], r_vmixon[7:6]);

wire [3:0] colnib_a = lyrf_pxl[8:5], colnib_b = lyra_pxl[8:5],
           colnib_c = lyrb_pxl[8:5], colnib_d = lyrc_pxl[8:5];
wire [4:0] pen_a = lyrf_pxl[4:0], pen_b = lyra_pxl[4:0],
           pen_c = lyrb_pxl[4:0], pen_d = lyrc_pxl[4:0];

wire a_opaque = |pen_a, b_opaque = |pen_b, c_opaque = |pen_c, d_opaque = |pen_d, o_opaque = |obj_pen;

wire a_ok = en_a &  a_opaque;
wire b_ok = en_b &  b_opaque & (mixef_b==2'd0);
wire c_ok = en_c &  c_opaque & (mixef_c==2'd0);
wire d_ok = en_d &  d_opaque & (mixef_d==2'd0);
wire o_ok = en_o &  o_opaque;

reg [2:0] bg_win;
reg [7:0] bg_pri;
always @* begin
    bg_win = 3'd5; bg_pri = 8'hff;
    if( d_ok && r_d_pri < bg_pri ) begin bg_win = 3'd3; bg_pri = r_d_pri; end
    if( c_ok && r_c_pri < bg_pri ) begin bg_win = 3'd2; bg_pri = r_c_pri; end
    if( b_ok && r_b_pri < bg_pri ) begin bg_win = 3'd1; bg_pri = r_b_pri; end
    if( a_ok && r_a_pri < bg_pri ) begin bg_win = 3'd0; bg_pri = r_a_pri; end
    if( o_ok && obj_pri  < bg_pri ) begin bg_win = 3'd4; bg_pri = obj_pri; end
end

wire b_alpha_ok = en_b & b_opaque & (mixef_b!=2'd0);
wire c_alpha_ok = en_c & c_opaque & (mixef_c!=2'd0);
wire d_alpha_ok = en_d & d_opaque & (mixef_d!=2'd0);

reg [1:0] fr_win;
reg [7:0] fr_pri;
reg [1:0] fr_mix;
always @* begin
    fr_win = 2'd3; fr_pri = 8'hff; fr_mix = 2'd0;
    if( d_alpha_ok && r_d_pri < fr_pri ) begin fr_win=2'd2; fr_pri=r_d_pri; fr_mix=mixef_d; end
    if( c_alpha_ok && r_c_pri < fr_pri ) begin fr_win=2'd1; fr_pri=r_c_pri; fr_mix=mixef_c; end
    if( b_alpha_ok && r_b_pri < fr_pri ) begin fr_win=2'd0; fr_pri=r_b_pri; fr_mix=mixef_b; end
end

wire fr_visible = (fr_win!=2'd3) && (fr_pri < bg_pri);

function [10:0] tile_pal_addr(input [7:0] palreg, input [3:0] colnib, input [4:0] pen);
    reg [10:0] base;
    begin
        base = { palreg[2:0], colnib, 4'b0 };
        tile_pal_addr = base + { 6'b0, pen };
    end
endfunction

function [10:0] obj_pal_addr_f(input [7:0] palreg, input [4:0] color, input [4:0] pen);
    reg [20:0] full;
    begin
        full = ( { 8'b0, palreg, color } << 5 ) + { 16'b0, pen };
        obj_pal_addr_f = full[10:0];
    end
endfunction

reg [10:0] bg_pal_addr;
always @* begin
    case(bg_win)
        3'd0:    bg_pal_addr = tile_pal_addr(r_a_pal, colnib_a, pen_a);
        3'd1:    bg_pal_addr = tile_pal_addr(r_b_pal, colnib_b, pen_b);
        3'd2:    bg_pal_addr = tile_pal_addr(r_c_pal, colnib_c, pen_c);
        3'd3:    bg_pal_addr = tile_pal_addr(r_d_pal, colnib_d, pen_d);
        3'd4:    bg_pal_addr = obj_pal_addr_f(r_obj_pal, obj_color, obj_pen);
        default: bg_pal_addr = 11'd0;
    endcase
end

reg [10:0] fr_pal_addr;
always @* begin
    case(fr_win)
        2'd0:    fr_pal_addr = tile_pal_addr(r_b_pal, colnib_b, pen_b);
        2'd1:    fr_pal_addr = tile_pal_addr(r_c_pal, colnib_c, pen_c);
        2'd2:    fr_pal_addr = tile_pal_addr(r_d_pal, colnib_d, pen_d);
        default: fr_pal_addr = 11'd0;
    endcase
end

assign pal_addr  = (bg_win==3'd5) ? 11'd0 : bg_pal_addr;
assign pal2_addr = fr_pal_addr;

reg [2:0]  bg_win_q;
reg [1:0]  fr_win_q, fr_mix_q;
reg        fr_visible_q;
reg [23:0] bg_bgr_q;
reg [1:0]  obj_shd_q;
reg [7:0]  bg_pri_q;
always @(posedge clk) begin
    bg_win_q     <= bg_win;
    fr_win_q     <= fr_win;
    fr_mix_q     <= fr_mix;
    fr_visible_q <= fr_visible;
    bg_bgr_q     <= bg_bgr;
    obj_shd_q    <= obj_shd;
    bg_pri_q     <= bg_pri;
end

function [7:0] bri_factor(input [1:0] mode);
    case(mode)
        2'd1:    bri_factor = bri_lv1;
        2'd2:    bri_factor = bri_lv2;
        2'd3:    bri_factor = bri_lv3;
        default: bri_factor = 8'hff;
    endcase
endfunction

function [1:0] vbri_mode(input [2:0] lyr);
    case(lyr)
        3'd0:    vbri_mode = r_vbri[1:0];
        3'd1:    vbri_mode = r_vbri[3:2];
        3'd2:    vbri_mode = r_vbri[5:4];
        default: vbri_mode = r_vbri[7:6];
    endcase
endfunction

function [7:0] apply_bri(input [7:0] comp, input [7:0] factor);
    reg [15:0] prod;
    begin
        prod      = comp * factor;
        apply_bri = (factor==8'hff) ? comp : prod[15:8];
    end
endfunction

function [7:0] alpha_used(input [1:0] mixsel);
    reg [7:0] lv; reg addf;
    begin
        case(mixsel)
            2'd1: begin lv=alpha_lv1; addf=add1; end
            2'd2: begin lv=alpha_lv2; addf=add2; end
            default: begin lv=alpha_lv3; addf=add3; end
        endcase
        alpha_used = (addf && lv!=8'd0) ? (~lv) : lv;
    end
endfunction

wire [2:0] bg_vbri_lyr = (bg_win_q<=3'd3) ? bg_win_q : 3'd0;

wire [1:0] obj_bri_mode = r_osbri_on[0] ? r_osbri[1:0] : 2'd0;
wire [1:0] bg_bri_mode  = (bg_win_q<=3'd3) ? vbri_mode(bg_vbri_lyr) :
                          (bg_win_q==3'd4) ? obj_bri_mode : 2'd0;
wire [7:0] bg_bri = bri_factor(bg_bri_mode);
wire [2:0] fr_vbri_lyr = {1'b0,fr_win_q} + 3'd1;
wire [7:0] fr_bri = bri_factor(vbri_mode(fr_vbri_lyr));

wire [7:0] bg_r = (bg_win_q==3'd5) ? bg_bgr_q[ 7:0] : apply_bri(pal_r, bg_bri);
wire [7:0] bg_g = (bg_win_q==3'd5) ? bg_bgr_q[15:8] : apply_bri(pal_g, bg_bri);
wire [7:0] bg_b = (bg_win_q==3'd5) ? bg_bgr_q[23:16]: apply_bri(pal_b, bg_bri);

wire [7:0] fr_r = apply_bri(pal2_r, fr_bri);
wire [7:0] fr_g = apply_bri(pal2_g, fr_bri);
wire [7:0] fr_b = apply_bri(pal2_b, fr_bri);

wire [7:0] a_lv = alpha_used(fr_mix_q);
wire [15:0] a_lv_w = {8'd0, a_lv};
wire [15:0] bg_w   = 16'd256 - a_lv_w;
wire [15:0] mix_r = bg_r*bg_w + fr_r*a_lv_w;
wire [15:0] mix_g = bg_g*bg_w + fr_g*a_lv_w;
wire [15:0] mix_b = bg_b*bg_w + fr_b*a_lv_w;

wire [7:0] pre_r = fr_visible_q ? mix_r[15:8] : bg_r;
wire [7:0] pre_g = fr_visible_q ? mix_g[15:8] : bg_g;
wire [7:0] pre_b = fr_visible_q ? mix_b[15:8] : bg_b;

function tabla_armada(input [8:0] dr, input [8:0] dg, input [8:0] db, input [1:0] selbits);
    tabla_armada = (selbits != 2'd0);
endfunction

wire shd1_on = tabla_armada(shd1_r, shd1_g, shd1_b, r_shdprisel[1:0]);
wire shd2_on = tabla_armada(shd2_r, shd2_g, shd2_b, r_shdprisel[3:2]);
wire shd3_on = tabla_armada(shd3_r, shd3_g, shd3_b, r_shdprisel[5:4]);

reg [8:0] shd_dr, shd_dg, shd_db;
reg [7:0] shd_pri;
reg       shd_on;
always @* begin
    case( obj_shd_q )
        2'd1:    begin shd_dr=shd1_r; shd_dg=shd1_g; shd_db=shd1_b; shd_pri=r_shd1_pri; shd_on=shd1_on; end
        2'd2:    begin shd_dr=shd2_r; shd_dg=shd2_g; shd_db=shd2_b; shd_pri=r_shd2_pri; shd_on=shd2_on; end
        2'd3:    begin shd_dr=shd3_r; shd_dg=shd3_g; shd_db=shd3_b; shd_pri=r_shd3_pri; shd_on=shd3_on; end
        default: begin shd_dr=0; shd_dg=0; shd_db=0; shd_pri=8'hff; shd_on=0; end
    endcase
end

wire shd_apply = en_o && obj_shd_q != 2'd0 && shd_on && shd_pri <= bg_pri_q;

function [7:0] satura(input [7:0] comp, input [8:0] delta);
    reg signed [10:0] suma;
    begin
        suma = $signed({3'b0, comp}) + $signed({{2{delta[8]}}, delta});
        satura = suma[10]         ? 8'd0   :
                 (suma > 11'sd255) ? 8'd255 : suma[7:0];
    end
endfunction

assign red   = shd_apply ? satura(pre_r, shd_dr) : pre_r;
assign green = shd_apply ? satura(pre_g, shd_dg) : pre_g;
assign blue  = shd_apply ? satura(pre_b, shd_db) : pre_b;

endmodule
