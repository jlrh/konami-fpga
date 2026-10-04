/*  This file is part of the Chequered Flag core for MiSTer. GPLv3. */

module jtchequeredflag_psac #(
    parameter BPP  = 8,
    parameter AW   = 20,
    parameter WRAP = 1,
    parameter DUAL = 0,

    parameter [8:0] ROW0  = 9'h110,
    parameter [8:0] HVIS0 = 9'h069
)(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             flip,

    input      [ 8:0] hdump,
    input      [ 8:0] vrender,
    input      [ 8:0] vdump,
    input             hs,

    input      [10:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    input             vr_cs,
    input             io_cs,
    output     [ 7:0] cpu_din,
    output     [12:0] ckbank,

    output     [AW-1:0] rom_addr,
    output            rom_cs,
    input             rom_ok,
    input      [ 7:0] rom_data,

    output     [AW-1:0] rom2_addr,
    output            rom2_cs,
    input             rom2_ok,
    input      [ 7:0] rom2_data,

    output     [ 8:0] pxl,
    output            pxl_ok,

    output reg        busy_ovr
);

localparam NCOL = 304;

reg  [ 7:0] regs[0:13];
reg         flipx_en, flipy_en;
wire [15:0] X0 = {regs[0], regs[1]},  incxx = {regs[2],  regs[3] },
            incyx = {regs[4], regs[5]}, Y0 = {regs[6], regs[7]},
            incxy = {regs[8], regs[9]}, incyy = {regs[10], regs[11]};
assign ckbank = { regs[13][4:0], regs[12] };

reg  [26:0] xrow, yrow, xc, yc;
reg  [ 9:0] tidx;
reg  [26:0] l_incxx, l_incxy, l_incyx, l_incyy;
reg         l_fx, l_fy;

function [26:0] sx16( input [15:0] v ); sx16 = {{11{v[15]}}, v}; endfunction
function [26:0] m223( input [26:0] v ); m223 = (v<<8) - (v<<5) - v; endfunction

wire [26:0] x0e = { {3{X0[15]}}, X0, 8'd0 }, y0e = { {3{Y0[15]}}, Y0, 8'd0 };
wire [26:0] x0f = x0e + m223( sx16(incyx) ), y0f = y0e + m223( sx16(incyy) );

always @(posedge clk) begin
    if( rst ) begin
        flipx_en <= 0; flipy_en <= 0;
    end else if( io_cs && cpu_we ) begin
        if( cpu_addr[3:0] < 4'd14 ) regs[cpu_addr[3:0]] <= cpu_dout;
        if( cpu_addr[3:0]==4'd14 ) begin flipx_en <= cpu_dout[1]; flipy_en <= cpu_dout[2]; end
    end
end

wire [ 7:0] cpu_code, cpu_attr, t_code, t_attr;
assign cpu_din = cpu_addr[10] ? cpu_attr : cpu_code;

jtframe_dual_ram #(.AW(10)) u_code(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( cpu_addr[9:0] ), .we0( vr_cs & cpu_we & ~cpu_addr[10] ), .q0( cpu_code ),
    .clk1 ( clk ), .data1( 8'd0     ), .addr1( tidx          ), .we1( 1'b0 ),                             .q1( t_code   )
);
jtframe_dual_ram #(.AW(10)) u_attr(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( cpu_addr[9:0] ), .we0( vr_cs & cpu_we &  cpu_addr[10] ), .q0( cpu_attr ),
    .clk1 ( clk ), .data1( 8'd0     ), .addr1( tidx          ), .we1( 1'b0 ),                             .q1( t_attr   )
);

reg         hs_l, prep_on, n_valid, n_inr, n_nib, wpar, p_inr;
reg  [ 1:0] pst;
reg  [ 8:0] pcol, n_col;
reg  [ 3:0] tpx, tpy;
reg  [AW-1:0] n_addr;
reg  [ 4:0] n_attr;
wire [ 8:0] px = xc[19:11], py = yc[19:11];
wire        in_x = WRAP ? 1'b1 : xc[26:20]==0,
            in_y = WRAP ? 1'b1 : yc[26:20]==0;
wire        fx = l_fx & t_attr[6], fy = l_fy & t_attr[7];
wire [ 3:0] cx = tpx ^ {4{fx}}, cy = tpy ^ {4{fy}};
wire        start_line = hs & ~hs_l;
wire        vis_row   = vrender >= ROW0 && vrender < ROW0+9'd224;
wire [AW-1:0] p_addr = BPP==8 ? { t_attr[3:0], t_code, cy, cx } : { t_attr[1:0], t_code, cy, cx[3:1] };

function [8:0] mkpx( input [4:0] attr, input nib, input [7:0] d );
    mkpx = BPP==8 ? { attr[0], d } : { 1'b0, attr[4:1], nib ? d[3:0] : d[7:4] };
endfunction

reg  [AW-1:0] f_addr [0:1], f_addr_q [0:1], c_addr [0:1];
reg         f_cs [0:1], f_busy [0:1], c_valid [0:1], o_valid [0:1], o_ok [0:1], f_nib [0:1];
reg  [ 7:0] c_data [0:1];
reg  [ 4:0] f_attr [0:1];
reg  [ 8:0] f_col [0:1], o_col [0:1], o_data [0:1];
wire        u_ok   [0:1];
wire [ 7:0] u_data [0:1];
assign rom_addr  = f_addr[0];  assign rom_cs  = f_cs[0];
assign rom2_addr = f_addr[1];  assign rom2_cs = f_cs[1];
assign u_ok[0]   = rom_ok;     assign u_data[0] = rom_data;
assign u_ok[1]   = rom2_ok;    assign u_data[1] = rom2_data;
wire        tgt   = DUAL ? n_col[0] : 1'b0;
wire        take  = n_valid && !f_busy[tgt] && !o_valid[tgt];
wire        idle  = !prep_on && !n_valid && !f_busy[0] && !f_busy[1] && !o_valid[0] && !o_valid[1];
wire        u_rsp [0:1];
assign u_rsp[0] = f_busy[0] && f_cs[0] && u_ok[0] && f_addr_q[0]==f_addr[0];
assign u_rsp[1] = f_busy[1] && f_cs[1] && u_ok[1] && f_addr_q[1]==f_addr[1];
reg  [ 8:0] wcol, wdata;
reg         we, wok;

integer u;
always @(posedge clk) begin
    if( rst ) begin
        pst <= 0; prep_on <= 0; n_valid <= 0; hs_l <= 0; busy_ovr <= 0;
        xrow <= 0; yrow <= 0; xc <= 0; yc <= 0; pcol <= 0; wpar <= 0; we <= 0;
        for( u=0; u<2; u=u+1 ) begin
            f_busy[u] <= 0; f_cs[u] <= 0; c_valid[u] <= 0; o_valid[u] <= 0;
        end
    end else begin
        hs_l <= hs;
        we   <= 0;
        for( u=0; u<2; u=u+1 ) f_addr_q[u] <= f_addr[u];
        if( start_line ) begin
            if( !idle ) busy_ovr <= 1;
            n_valid <= 0; pst <= 0;
            for( u=0; u<2; u=u+1 ) begin f_busy[u] <= 0; f_cs[u] <= 0; o_valid[u] <= 0; end
            prep_on <= vis_row;
            if( vis_row ) begin

                if( vrender==ROW0 ) begin
                    l_incxx <= sx16(incxx); l_incxy <= sx16(incxy);
                    l_incyx <= sx16(incyx); l_incyy <= sx16(incyy);
                    l_fx <= flipx_en; l_fy <= flipy_en;
                    xrow <= flip ? x0f : x0e;  xc <= flip ? x0f : x0e;
                    yrow <= flip ? y0f : y0e;  yc <= flip ? y0f : y0e;
                end else if( flip ) begin
                    xc <= xrow - l_incyx;  xrow <= xrow - l_incyx;
                    yc <= yrow - l_incyy;  yrow <= yrow - l_incyy;
                end else begin
                    xc <= xrow + l_incyx;  xrow <= xrow + l_incyx;
                    yc <= yrow + l_incyy;  yrow <= yrow + l_incyy;
                end
                pcol <= 0;
                wpar <= vrender[0];
            end
        end else begin

            if( take ) begin
                n_valid    <= 0;
                f_col[tgt] <= n_col;
                if( !n_inr ) begin
                    o_valid[tgt] <= 1; o_ok[tgt] <= 0; o_col[tgt] <= n_col; o_data[tgt] <= 0;
                end else if( c_valid[tgt] && c_addr[tgt]==n_addr ) begin
                    o_valid[tgt] <= 1; o_ok[tgt] <= 1; o_col[tgt] <= n_col;
                    o_data[tgt]  <= mkpx( n_attr, n_nib, c_data[tgt] );
                end else begin
                    f_addr[tgt] <= n_addr; f_cs[tgt] <= 1; f_busy[tgt] <= 1;
                    f_attr[tgt] <= n_attr; f_nib[tgt] <= n_nib;
                end
            end

            if( prep_on ) case( pst )
                0: begin
                    p_inr <= in_x & in_y;
                    tidx  <= { py[8:4], px[8:4] };
                    tpx   <= px[3:0]; tpy <= py[3:0];
                    xc    <= xc + l_incxx;
                    yc    <= yc + l_incxy;
                    pst   <= 1;
                end
                1: pst <= 2;
                2: if( !n_valid || take ) begin
                    n_valid <= 1;
                    n_inr   <= p_inr;
                    n_addr  <= p_addr;
                    n_nib   <= cx[0];
                    n_attr  <= BPP==8 ? { 4'd0, t_attr[4] } : { t_attr[5:2], 1'b0 };
                    n_col   <= pcol;
                    pcol    <= pcol + 1'd1;
                    pst     <= 0;
                    if( pcol == NCOL-1 ) prep_on <= 0;
                end
                default:;
            endcase

            for( u=0; u<2; u=u+1 ) begin
                if( u_rsp[u] ) begin
                    f_cs[u] <= 0; f_busy[u] <= 0;
                    c_valid[u] <= 1; c_addr[u] <= f_addr[u]; c_data[u] <= u_data[u];
                    o_valid[u] <= 1; o_ok[u] <= 1; o_col[u] <= f_col[u];
                    o_data[u]  <= mkpx( f_attr[u], f_nib[u], u_data[u] );
                end
            end

            if( o_valid[0] ) begin
                we <= 1; wcol <= o_col[0]; wdata <= o_data[0]; wok <= o_ok[0]; o_valid[0] <= 0;
            end else if( o_valid[1] ) begin
                we <= 1; wcol <= o_col[1]; wdata <= o_data[1]; wok <= o_ok[1]; o_valid[1] <= 0;
            end
        end
    end
end

wire [ 8:0] rcol0 = hdump - HVIS0;
wire [ 8:0] rcol  = flip ? 9'd303 - rcol0 : rcol0;
wire [ 9:0] rdat;

jtframe_dual_ram #(.DW(10),.AW(10)) u_line(
    .clk0 ( clk ), .data0( {wok, wdata} ), .addr0( {wpar, wcol} ), .we0( we ), .q0(  ),
    .clk1 ( clk ), .data1( 10'd0 ), .addr1( {vdump[0], rcol} ), .we1( 1'b0 ), .q1( rdat )
);
assign pxl    = rdat[8:0];
assign pxl_ok = rdat[9];

`ifdef SIMULATION

integer bf, lcyc=0, lmax=0, nf=0, lat_sum=0, lat_n=0, lat_max=0, lat_c0=0, lat_c1=0;
initial bf = $fopen( BPP==8 ? "psac2_presupuesto.log" : "psac1_presupuesto.log", "w" );
always @(posedge clk) begin
    if( start_line ) begin
        if( lcyc > lmax ) lmax = lcyc;
        lcyc = 0;
        if( vrender==ROW0 ) begin
            if( nf>0 ) begin
                $fdisplay( bf, "frame %0d: linea mas cara %0d clk (de 3072), lat ROM media %0d max %0d",
                    nf, lmax, lat_n ? lat_sum/lat_n : 0, lat_max ); $fflush( bf );
            end
            nf = nf + 1; lmax = 0; lat_sum = 0; lat_n = 0; lat_max = 0;
        end
    end else if( !idle ) lcyc = lcyc + 1;
    if( f_busy[0] ) lat_c0 = lat_c0 + 1;
    if( f_busy[1] ) lat_c1 = lat_c1 + 1;
    if( u_rsp[0] ) begin
        lat_sum = lat_sum + lat_c0; lat_n = lat_n + 1; if( lat_c0 > lat_max ) lat_max = lat_c0; lat_c0 = 0;
    end
    if( u_rsp[1] ) begin
        lat_sum = lat_sum + lat_c1; lat_n = lat_n + 1; if( lat_c1 > lat_max ) lat_max = lat_c1; lat_c1 = 0;
    end
end
`endif

endmodule
