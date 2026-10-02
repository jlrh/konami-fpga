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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module mtlchamp_k055555(
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

    input      [ 4:0] objm_pen,
    input      [ 4:0] objm_color,
    input      [ 7:0] objm_pri,
    input      [ 1:0] objm_mix,

    input      [ 4:0] obj_shd_pen,
    input      [ 7:0] obj_shd_pri,

    input      [23:0] bg_bgr,
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
wire [7:0] r_inpen   = r[45];

wire en_a = r_inpen[0], en_b = r_inpen[1], en_c = r_inpen[2], en_d = r_inpen[3], en_o = r_inpen[4];

wire [3:0] colnib_a = lyrf_pxl[8:5], colnib_b = lyra_pxl[8:5],
           colnib_c = lyrb_pxl[8:5], colnib_d = lyrc_pxl[8:5];
wire [4:0] pen_a = lyrf_pxl[4:0], pen_b = lyra_pxl[4:0],
           pen_c = lyrb_pxl[4:0], pen_d = lyrc_pxl[4:0];

wire a_opaque = |pen_a, b_opaque = |pen_b, c_opaque = |pen_c, d_opaque = |pen_d, o_opaque = |obj_pen;

localparam OBJ_MIX_EN = 1'b1;
wire [1:0] objm_mix_eff = OBJ_MIX_EN ? objm_mix : 2'd0;

wire a_ok = en_a &  a_opaque;
wire b_ok = en_b &  b_opaque & (lyra_mix==2'd0);
wire c_ok = en_c &  c_opaque & (lyrb_mix==2'd0);
wire d_ok = en_d &  d_opaque & (lyrc_mix==2'd0);
wire o_ok = en_o &  o_opaque;

wire o_solid = o_ok;
wire o_shadw = en_o & |obj_shd_pen;

wire o_alpha_ok = en_o & (|objm_pen) & (objm_mix_eff!=2'd0);

reg [2:0] bg_win;
reg [7:0] bg_pri;
reg       obj_gana;
localparam SHD_NO_SOBRE_SPRITE = 1'b1;
reg       shd_hit;
always @* begin
    bg_win = 3'd5; bg_pri = 8'hff;
    obj_gana = 1'b0;
    if( d_ok && r_d_pri < bg_pri ) begin bg_win = 3'd3; bg_pri = r_d_pri; end
    if( c_ok && r_c_pri < bg_pri ) begin bg_win = 3'd2; bg_pri = r_c_pri; end
    if( b_ok && r_b_pri < bg_pri ) begin bg_win = 3'd1; bg_pri = r_b_pri; end
    if( a_ok && r_a_pri < bg_pri ) begin bg_win = 3'd0; bg_pri = r_a_pri; end
    if( o_solid && obj_pri < bg_pri ) begin bg_win = 3'd4; bg_pri = obj_pri; end

    obj_gana = (bg_win==3'd4) || (o_alpha_ok && objm_pri < bg_pri);

    shd_hit = o_shadw && obj_shd_pri < bg_pri && !(SHD_NO_SOBRE_SPRITE && obj_gana);
end

wire b_alpha_ok = en_b & b_opaque & (lyra_mix!=2'd0);
wire c_alpha_ok = en_c & c_opaque & (lyrb_mix!=2'd0);
wire d_alpha_ok = en_d & d_opaque & (lyrc_mix!=2'd0);

reg [2:0] fr_win;
reg [7:0] fr_pri;
reg [1:0] fr_mix;
always @* begin
    fr_win = 3'd4; fr_pri = 8'hff; fr_mix = 2'd0;
    if( d_alpha_ok && r_d_pri < fr_pri ) begin fr_win=3'd2; fr_pri=r_d_pri; fr_mix=lyrc_mix; end
    if( c_alpha_ok && r_c_pri < fr_pri ) begin fr_win=3'd1; fr_pri=r_c_pri; fr_mix=lyrb_mix; end
    if( b_alpha_ok && r_b_pri < fr_pri ) begin fr_win=3'd0; fr_pri=r_b_pri; fr_mix=lyra_mix; end

    if( o_alpha_ok && objm_pri < fr_pri ) begin fr_win=3'd3; fr_pri=objm_pri; fr_mix=objm_mix_eff; end
end

wire fr_visible = (fr_win!=3'd4) && (fr_pri < bg_pri);

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
        3'd0:    fr_pal_addr = tile_pal_addr(r_b_pal, colnib_b, pen_b);
        3'd1:    fr_pal_addr = tile_pal_addr(r_c_pal, colnib_c, pen_c);
        3'd2:    fr_pal_addr = tile_pal_addr(r_d_pal, colnib_d, pen_d);
        3'd3:    fr_pal_addr = obj_pal_addr_f(r_obj_pal, objm_color, objm_pen);
        default: fr_pal_addr = 11'd0;
    endcase
end

assign pal_addr  = (bg_win==3'd5) ? 11'd0 : bg_pal_addr;
assign pal2_addr = fr_pal_addr;

reg [2:0]  bg_win_q;
reg [2:0]  fr_win_q;
reg [1:0]  fr_mix_q;
reg        fr_visible_q;
reg [23:0] bg_bgr_q;
reg        shd_hit_q;
always @(posedge clk) begin
    bg_win_q     <= bg_win;
    fr_win_q     <= fr_win;
    fr_mix_q     <= fr_mix;
    fr_visible_q <= fr_visible;
    bg_bgr_q     <= bg_bgr;
    shd_hit_q    <= shd_hit;
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
    apply_bri = (factor==8'hff) ? comp : ((comp * factor) >> 8);
endfunction

function [7:0] alpha_used(input [1:0] mixsel);
    case(mixsel)
        2'd1:    alpha_used = alpha_lv1;
        2'd2:    alpha_used = alpha_lv2;
        default: alpha_used = alpha_lv3;
    endcase
endfunction

function add_used(input [1:0] mixsel);
    case(mixsel)
        2'd1:    add_used = add1;
        2'd2:    add_used = add2;
        default: add_used = add3;
    endcase
endfunction

wire [2:0] bg_vbri_lyr = (bg_win_q<=3'd3) ? bg_win_q : 3'd0;
wire       bg_has_vbri = (bg_win_q<=3'd3);
wire [7:0] bg_bri = bg_has_vbri ? bri_factor(vbri_mode(bg_vbri_lyr)) : 8'hff;
wire [2:0] fr_vbri_lyr = fr_win_q + 3'd1;

wire [7:0] fr_bri = (fr_win_q==3'd3) ? 8'hff : bri_factor(vbri_mode(fr_vbri_lyr));

wire [7:0] bg_r = (bg_win_q==3'd5) ? bg_bgr_q[ 7:0] : apply_bri(pal_r, bg_bri);
wire [7:0] bg_g = (bg_win_q==3'd5) ? bg_bgr_q[15:8] : apply_bri(pal_g, bg_bri);
wire [7:0] bg_b = (bg_win_q==3'd5) ? bg_bgr_q[23:16]: apply_bri(pal_b, bg_bri);

wire [7:0] fr_r = apply_bri(pal2_r, fr_bri);
wire [7:0] fr_g = apply_bri(pal2_g, fr_bri);
wire [7:0] fr_b = apply_bri(pal2_b, fr_bri);

wire        fr_is_obj = fr_win_q == 3'd3;
wire [7:0]  lv_raw = alpha_used(fr_mix_q);
wire        add_raw = add_used(fr_mix_q);

localparam [7:0] OBJ_MIX_LV = 8'd128;

wire [7:0]  a_lv   = fr_is_obj ? OBJ_MIX_LV
                               : ((add_raw && lv_raw!=8'd0) ? ~lv_raw : lv_raw);
wire        a_add  = 1'b0;
wire [15:0] a_lv_w = {8'd0, a_lv};
wire [15:0] bg_w   = 16'd256 - a_lv_w;

wire [15:0] src_r = fr_r*a_lv_w, src_g = fr_g*a_lv_w, src_b = fr_b*a_lv_w;

function [7:0] sat_add(input [7:0] d, input [7:0] s);
    reg [8:0] t;
    begin
        t = {1'b0,d} + {1'b0,s};
        sat_add = t[8] ? 8'hff : t[7:0];
    end
endfunction

wire [15:0] itp_r = bg_r*bg_w + src_r;
wire [15:0] itp_g = bg_g*bg_w + src_g;
wire [15:0] itp_b = bg_b*bg_w + src_b;

wire [7:0] mix_r = a_add ? sat_add(bg_r, src_r[15:8]) : itp_r[15:8];
wire [7:0] mix_g = a_add ? sat_add(bg_g, src_g[15:8]) : itp_g[15:8];
wire [7:0] mix_b = a_add ? sat_add(bg_b, src_b[15:8]) : itp_b[15:8];

localparam [4:0] SHD_D5 = 5'd10;

localparam [7:0] SHD_D8 = 8'd80;

function [7:0] shade(input [7:0] c);
    reg [4:0] c5;
    reg [7:0] base8;
    begin
        c5    = c[7:3];
        base8 = { c5, c5[4:2] };
        shade = (base8 > SHD_D8) ? (base8 - SHD_D8) : 8'd0;
    end
endfunction

wire [7:0] out_r = fr_visible_q ? mix_r : bg_r;
wire [7:0] out_g = fr_visible_q ? mix_g : bg_g;
wire [7:0] out_b = fr_visible_q ? mix_b : bg_b;

assign red   = shd_hit_q ? shade(out_r) : out_r;
assign green = shd_hit_q ? shade(out_g) : out_g;
assign blue  = shd_hit_q ? shade(out_b) : out_b;

endmodule
