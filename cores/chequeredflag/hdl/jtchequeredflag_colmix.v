/*  This file is part of the Chequered Flag core for MiSTer. GPLv3. */

module jtchequeredflag_colmix(
    input             clk,
    input             pxl_cen,

    input      [10:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    input             pal_cs,
    output     [ 7:0] pal_dout,

    input      [ 7:0] vreg,
    input             shadow_mode,

    input      [ 8:0] p2_pxl,
    input      [ 8:0] p1_pxl,
    input             p1_ok,
    input             o_src, o_pm, o_sh0, o_sh1,
    input      [ 7:0] o_col,
    input      [ 3:0] gfx_en,
    output reg [ 7:0] red, green, blue
);

wire [ 7:0] hi_cpu, lo_cpu, hi, lo;
reg  [ 9:0] idx;
reg  [ 1:0] grp, grp_l;
reg         bgp, bgp_l;
reg  [ 2:0] ph;
reg  [ 7:0] r_s, g_s, b_s;
wire [ 1:0] vidx = { vreg[7], vreg[3] };
wire [14:0] c = { hi[6:0], lo };
wire [ 7:0] rq, gq, bq;

assign pal_dout = cpu_addr[0] ? lo_cpu : hi_cpu;

wire        p2_hi = p2_pxl[7:6]==2'b11;
wire        p2_en = gfx_en[1], o_en = gfx_en[3], p1_en = gfx_en[0];
wire        o_vis = o_en && o_src && !(o_pm && p2_hi && p2_en);
wire        sha   = o_en && (o_sh0 || (o_sh1 && !(p2_hi && p2_en)));
wire        p1_vis= p1_en && p1_ok && p1_pxl[3:0]!=0;

always @(posedge clk) begin
    ph <= pxl_cen ? 3'd1 : (ph!=0 ? ph + 3'd1 : 3'd0);
    if( pxl_cen ) begin
        if( p1_vis ) begin
            idx <= { 2'b01, p1_pxl[7:0] }; grp <= 0;
        end else begin
            idx <= o_vis ? { 2'b00, o_col } : (p2_en ? { 1'b1, p2_pxl } : 10'd0);
            grp <= sha ? ( shadow_mode ? 2'd2 : 2'd1 ) : 2'd0;
        end
    end

    if( ph==3'd2 ) begin grp_l <= grp; bgp_l <= idx[9]; end
    if( ph==3'd5 ) begin r_s <= rq; g_s <= gq; b_s <= bq; end

    if( pxl_cen ) begin red <= r_s; green <= g_s; blue <= b_s; end
end

jtframe_dual_ram #(.AW(10)) u_hi(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[10:1] ), .we0( pal_cs & cpu_we & ~cpu_addr[0] ), .q0( hi_cpu ),
    .clk1( clk ), .data1( 8'd0 ),     .addr1( idx ),            .we1( 1'b0 ),                             .q1( hi     )
);
jtframe_dual_ram #(.AW(10)) u_lo(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[10:1] ), .we0( pal_cs & cpu_we &  cpu_addr[0] ), .q0( lo_cpu ),
    .clk1( clk ), .data1( 8'd0 ),     .addr1( idx ),            .we1( 1'b0 ),                             .q1( lo     )
);

jtchequeredflag_colortab u_rtab( .clk( clk ), .addr( { grp_l, bgp_l, vidx, c[ 4: 0] } ), .q( rq ) );
jtchequeredflag_colortab u_gtab( .clk( clk ), .addr( { grp_l, bgp_l, vidx, c[ 9: 5] } ), .q( gq ) );
jtchequeredflag_colortab u_btab( .clk( clk ), .addr( { grp_l, bgp_l, vidx, c[14:10] } ), .q( bq ) );

endmodule
