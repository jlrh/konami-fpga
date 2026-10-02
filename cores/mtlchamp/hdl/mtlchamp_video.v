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

module mtlchamp_video(
    input             rst,
    input             clk,
    input             pxl_cen,

    output            lhbl, lvbl, hs, vs,
    output     [ 8:0] hdump, vdump, vrender, vrender1,

    input      [12:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,
    input             vram_cs,
    input             tilereg_cs,
    input             tilereg_b_cs,
    input             pal_cs,
    input             alpha_cs,
    input             pcu_cs,
    output     [15:0] vram_dout,
    output     [15:0] pal_dout,

    output     [20:2] scr_addr,
    output            scr_cs,
    input      [31:0] scr_data,
    input             scr_ok,
    output     [18:0] scrx_addr,
    output            scrx_cs,
    input      [ 7:0] scrx_data,
    input             scrx_ok,

    output     [20:2] scrb_addr,
    output            scrb_cs,
    input      [31:0] scrb_data,
    input             scrb_ok,
    output     [18:0] scrxb_addr,
    output            scrxb_cs,
    input      [ 7:0] scrxb_data,
    input             scrxb_ok,

    input      [ 9:0] obj_buf_addr,
    input             obj_buf_we,
    input      [20:0] obj_buf_din,

    output     [ 7:0] red, green, blue,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout,

    output     [ 8:0] dbg_lyrf, dbg_lyra, dbg_lyrb, dbg_lyrc,
    output     [ 1:0] dbg_mixa, dbg_mixb, dbg_mixc,

    output     [ 4:0] dbg_obj_pen, dbg_obj_color,
    output     [ 7:0] dbg_obj_pri
);

wire lhbl_raw;
reg  lhbl_out=1'b1;
assign lhbl = lhbl_out;
always @(posedge clk) if( pxl_cen ) lhbl_out <= lhbl_raw;

jtframe_vtimer #(
    .HCNT_START(9'h000), .HCNT_END (9'h1FF),
    .HB_START  (9'd383), .HB_END   (9'h1FF),
    .HS_START  (9'd416), .HS_END   (9'd456),
    .H_VNEXT   (9'd416),
    .V_START   (9'h0F8), .VCNT_END (9'h1FF),
    .VB_START  (9'h1EF), .VB_END   (9'h10F),
    .VS_START  (9'h0F9), .VS_END   (9'h101)
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),
    .H          ( hdump     ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( lhbl_raw  ),
    .LVBL       ( lvbl      ),
    .HS         ( hs        ),
    .VS         ( vs        )
);

wire [ 8:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl;
wire [ 1:0] lyra_mix, lyrb_mix, lyrc_mix;
wire [ 7:0] st_tile;

wire        cpu_weg = cpu_we && cpu_dsn!=2'b11;

mtlchamp_k056832 u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),

    .lhbl       ( lhbl_raw  ),
    .hdump      ( hdump     ),
    .vrender1   ( vrender1  ),

    .vram_cs    ( vram_cs      ),
    .reg_cs     ( tilereg_cs   ),
    .regb_cs    ( tilereg_b_cs ),
    .cpu_we     ( cpu_weg   ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( vram_dout ),

    .scr_addr   ( scr_addr  ),
    .scr_cs     ( scr_cs    ),
    .scr_data   ( scr_data  ),
    .scr_ok     ( scr_ok    ),
    .scrx_addr  ( scrx_addr ),
    .scrx_cs    ( scrx_cs   ),
    .scrx_data  ( scrx_data ),
    .scrx_ok    ( scrx_ok   ),
    .scrb_addr  ( scrb_addr ),
    .scrb_cs    ( scrb_cs   ),
    .scrb_data  ( scrb_data ),
    .scrb_ok    ( scrb_ok   ),
    .scrxb_addr ( scrxb_addr),
    .scrxb_cs   ( scrxb_cs  ),
    .scrxb_data ( scrxb_data),
    .scrxb_ok   ( scrxb_ok  ),

    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyrc_pxl   ( lyrc_pxl  ),
    .lyra_mix   ( lyra_mix  ),
    .lyrb_mix   ( lyrb_mix  ),
    .lyrc_mix   ( lyrc_mix  ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_tile   )
);

assign dbg_lyrf = lyrf_pxl;
assign dbg_lyra = lyra_pxl;
assign dbg_lyrb = lyrb_pxl;
assign dbg_lyrc = lyrc_pxl;
assign dbg_mixa = lyra_mix;
assign dbg_mixb = lyrb_mix;
assign dbg_mixc = lyrc_mix;

reg [ 8:0] lyrf_q=0, lyra_q=0, lyrb_q=0, lyrc_q=0;
reg [ 1:0] lyra_mix_q=0, lyrb_mix_q=0, lyrc_mix_q=0;
always @(posedge clk) if( pxl_cen ) begin
    lyrf_q <= lyrf_pxl; lyra_q <= lyra_pxl; lyrb_q <= lyrb_pxl; lyrc_q <= lyrc_pxl;
    lyra_mix_q <= lyra_mix; lyrb_mix_q <= lyrb_mix; lyrc_mix_q <= lyrc_mix;
end

wire [ 7:0] pal_r, pal_g, pal_b, pal2_r, pal2_g, pal2_b;
wire [10:0] pal_addr, pal2_addr;
wire [23:0] k338_bg_bgr;
wire [ 8:0] k338_shd1_r, k338_shd1_g, k338_shd1_b,
            k338_shd2_r, k338_shd2_g, k338_shd2_b,
            k338_shd3_r, k338_shd3_g, k338_shd3_b;
wire [ 7:0] k338_alpha_lv1, k338_alpha_lv2, k338_alpha_lv3;
wire        k338_add1, k338_add2, k338_add3,
            k338_kill, k338_mixpri, k338_shdpri, k338_brtpri, k338_wailsl, k338_clipsl;
wire [ 7:0] k338_bri_lv1, k338_bri_lv2, k338_bri_lv3;

mtlchamp_palette u_palette(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .pal_cs     ( pal_cs    ),
    .pal_dout   ( pal_dout  ),
    .pal_addr   ( pal_addr  ),
    .pal_r      ( pal_r     ),
    .pal_g      ( pal_g     ),
    .pal_b      ( pal_b     ),
    .pal2_addr  ( pal2_addr ),
    .pal2_r     ( pal2_r    ),
    .pal2_g     ( pal2_g    ),
    .pal2_b     ( pal2_b    )
);

mtlchamp_k054338 u_k054338(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .alpha_cs   ( alpha_cs      ),
    .cpu_addr   ( cpu_addr[4:1] ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_we     ( cpu_we        ),
    .bg_bgr     ( k338_bg_bgr   ),
    .shd1_r     ( k338_shd1_r   ), .shd1_g( k338_shd1_g ), .shd1_b( k338_shd1_b ),
    .shd2_r     ( k338_shd2_r   ), .shd2_g( k338_shd2_g ), .shd2_b( k338_shd2_b ),
    .shd3_r     ( k338_shd3_r   ), .shd3_g( k338_shd3_g ), .shd3_b( k338_shd3_b ),
    .alpha_lv1  ( k338_alpha_lv1), .alpha_lv2( k338_alpha_lv2 ), .alpha_lv3( k338_alpha_lv3 ),
    .add1       ( k338_add1     ), .add2( k338_add2 ), .add3( k338_add3 ),
    .ctl_kill   ( k338_kill     ), .ctl_mixpri( k338_mixpri ), .ctl_shdpri( k338_shdpri ),
    .ctl_brtpri ( k338_brtpri   ), .ctl_wailsl( k338_wailsl ), .ctl_clipsl( k338_clipsl ),
    .bri_lv1    ( k338_bri_lv1  ), .bri_lv2( k338_bri_lv2 ), .bri_lv3( k338_bri_lv3 )
);

wire [20:0] objbuf_dout;
jtframe_obj_buffer #(
    .DW         ( 21        ),
    .AW         ( 10        ),
    .ALPHAW     ( 5         ),
    .ALPHA      ( 21'd0     ),
    .BLANK      ( 21'd0     ),
    .KEEP_OLD   ( 0         )
) u_objbuf(
    .clk        ( clk           ),
    .LHBL       ( ~hs           ),
    .flip       ( 1'b0          ),
    .wr_data    ( obj_buf_din   ),
    .wr_addr    ( obj_buf_addr  ),
    .we         ( obj_buf_we & ~obj_buf_din[18] & ~|obj_buf_din[20:19] ),
    .rd_addr    ( { 1'b0, hdump } ),
    .rd         ( pxl_cen       ),
    .rd_data    ( objbuf_dout   )
);
wire [4:0] obj_pen_w   = objbuf_dout[4:0];
wire [4:0] obj_color_w = objbuf_dout[9:5];
wire [7:0] obj_pri_w   = objbuf_dout[17:10];

wire [1:0] obj_mix_w   = objbuf_dout[20:19];

wire [12:0] shdbuf_dout;
jtframe_obj_buffer #(
    .DW( 13 ), .AW( 10 ), .ALPHAW( 5 ), .ALPHA( 13'd0 ), .BLANK( 13'd0 ), .KEEP_OLD( 0 )
) u_shdbuf(
    .clk( clk ), .LHBL( ~hs ), .flip( 1'b0 ),
    .wr_data( { obj_buf_din[17:10], obj_buf_din[4:0] } ),
    .wr_addr( obj_buf_addr ),
    .we     ( obj_buf_we &  obj_buf_din[18] ),
    .rd_addr( { 1'b0, hdump } ), .rd( pxl_cen ), .rd_data( shdbuf_dout )
);

wire [19:0] mixbuf_dout;
jtframe_obj_buffer #(
    .DW( 20 ), .AW( 10 ), .ALPHAW( 5 ), .ALPHA( 20'd0 ), .BLANK( 20'd0 ), .KEEP_OLD( 0 )
) u_mixbuf(
    .clk( clk ), .LHBL( ~hs ), .flip( 1'b0 ),
    .wr_data( { obj_buf_din[20:19], obj_buf_din[17:0] } ),
    .wr_addr( obj_buf_addr ),
    .we     ( obj_buf_we & ~obj_buf_din[18] & |obj_buf_din[20:19] ),
    .rd_addr( { 1'b0, hdump } ), .rd( pxl_cen ), .rd_data( mixbuf_dout )
);
wire [4:0] objm_pen   = mixbuf_dout[ 4: 0];
wire [4:0] objm_color = mixbuf_dout[ 9: 5];
wire [7:0] objm_pri   = mixbuf_dout[17:10];
wire [1:0] objm_mix   = mixbuf_dout[19:18];

wire [4:0] obj_shd_pen = shdbuf_dout[4:0];
wire [7:0] obj_shd_pri = shdbuf_dout[12:5];
assign dbg_obj_pen   = obj_pen_w;
assign dbg_obj_color = obj_color_w;
assign dbg_obj_pri   = obj_pri_w;

mtlchamp_k055555 u_mixer(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pcu_cs     ( pcu_cs        ),
    .cpu_addr   ( cpu_addr[6:1] ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_we     ( cpu_we        ),

    .lyrf_pxl   ( lyrf_q    ), .lyra_pxl( lyra_q   ), .lyrb_pxl( lyrb_q   ), .lyrc_pxl( lyrc_q   ),
    .lyra_mix   ( lyra_mix_q), .lyrb_mix( lyrb_mix_q), .lyrc_mix( lyrc_mix_q),

    .obj_pen    ( obj_pen_w    ),
    .obj_color  ( obj_color_w  ),
    .obj_pri    ( obj_pri_w    ),
    .objm_pen   ( objm_pen     ),
    .objm_color ( objm_color   ),
    .objm_pri   ( objm_pri     ),
    .objm_mix   ( objm_mix     ),
    .obj_shd_pen( obj_shd_pen   ),
    .obj_shd_pri( obj_shd_pri   ),

    .bg_bgr     ( k338_bg_bgr    ),
    .alpha_lv1  ( k338_alpha_lv1 ), .alpha_lv2( k338_alpha_lv2 ), .alpha_lv3( k338_alpha_lv3 ),
    .add1       ( k338_add1      ), .add2( k338_add2 ), .add3( k338_add3 ),
    .bri_lv1    ( k338_bri_lv1   ), .bri_lv2( k338_bri_lv2 ), .bri_lv3( k338_bri_lv3 ),

    .pal_addr   ( pal_addr  ), .pal_r ( pal_r  ), .pal_g ( pal_g  ), .pal_b ( pal_b  ),
    .pal2_addr  ( pal2_addr ), .pal2_r( pal2_r ), .pal2_g( pal2_g ), .pal2_b( pal2_b ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      )
);

assign st_dout = st_tile;

endmodule
