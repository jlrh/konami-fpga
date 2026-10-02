module jthotchase_psac #(
    parameter CB    = 1,
    parameter AW    = 17,
    parameter WRAP  = 1,
    parameter NCOL  = 320,
    parameter [8:0] ROW0  = 9'd0,
    parameter [8:0] HVIS0 = 9'd0,

    parameter SF_CODE = "", SF_ATTR = "", SF_REGS = ""
)(
    input             rst,
    input             clk,
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

    output     [AW-1:0] rom_addr,
    output            rom_cs,
    input             rom_ok,
    input      [ 7:0] rom_data,

    output     [10:0] pxl,
    output            pxl_ok,

    output reg        busy_ovr
);

reg  [ 7:0] regs[0:13];
`ifdef SIMULATION
initial if( SF_REGS != "" ) $readmemh( SF_REGS, regs );
`endif
reg         flipx_en, flipy_en;
wire [15:0] X0 = {regs[0], regs[1]},  incxx = {regs[2],  regs[3] },
            incyx = {regs[4], regs[5]}, Y0 = {regs[6], regs[7]},
            incxy = {regs[8], regs[9]}, incyy = {regs[10], regs[11]};

reg  [26:0] xrow, yrow, xc, yc;
reg  [ 9:0] tidx;
reg  [26:0] l_incxx, l_incxy, l_incyx, l_incyy;
reg         l_fx, l_fy;

function [26:0] sx16( input [15:0] v ); sx16 = {{11{v[15]}}, v}; endfunction
function [26:0] m223( input [26:0] v ); m223 = (v<<8) - (v<<5) - v; endfunction

wire [26:0] x0e = { {3{X0[15]}}, X0, 8'd0 } - sx16(incxx),
            y0e = { {3{Y0[15]}}, Y0, 8'd0 } - sx16(incxy);

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

jtframe_dual_ram #(.AW(10),.SIMFILE(SF_CODE)) u_code(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( cpu_addr[9:0] ), .we0( vr_cs & cpu_we & ~cpu_addr[10] ), .q0( cpu_code ),
    .clk1 ( clk ), .data1( 8'd0     ), .addr1( tidx          ), .we1( 1'b0 ),                             .q1( t_code   )
);
jtframe_dual_ram #(.AW(10),.SIMFILE(SF_ATTR)) u_attr(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( cpu_addr[9:0] ), .we0( vr_cs & cpu_we &  cpu_addr[10] ), .q0( cpu_attr ),
    .clk1 ( clk ), .data1( 8'd0     ), .addr1( tidx          ), .we1( 1'b0 ),                             .q1( t_attr   )
);

reg         hs_l, prep_on, n_valid, n_inr, n_nib, wpar, p_inr;
reg  [ 1:0] pst;
reg  [ 8:0] pcol, n_col;
reg  [ 3:0] tpx, tpy;
reg  [AW-1:0] n_addr;
reg  [ 6:0] n_attr;
wire [ 8:0] px = xc[19:11], py = yc[19:11];
wire        in_x = WRAP ? 1'b1 : xc[26:20]==0,
            in_y = WRAP ? 1'b1 : yc[26:20]==0;
wire        fx = l_fx & t_attr[6], fy = l_fy & t_attr[7];
wire [ 3:0] cx = tpx ^ {4{fx}}, cy = tpy ^ {4{fy}};
wire        start_line = hs & ~hs_l;
wire        vis_row   = vrender >= ROW0 && vrender < ROW0+9'd224;
wire [16:0] p_addr17 = CB==1 ? { t_attr[1:0], t_code, cy, cx[3:1] } : { 2'd0, t_code, cy, cx[3:1] };
wire [AW-1:0] p_addr = p_addr17[AW-1:0];
wire [ 6:0] p_color  = CB==1 ? { 1'b0, t_attr[7:2] } : { t_attr[5:0], t_code[7] };

function [10:0] mkpx( input [6:0] attr, input nib, input [7:0] d );
    mkpx = { attr, nib ? d[3:0] : d[7:4] };
endfunction

reg  [AW-1:0] f_addr, f_addr_q, c_addr;
reg         f_cs, f_busy, c_valid, o_valid, o_ok, f_nib;
reg  [ 7:0] c_data;
reg  [ 6:0] f_attr;
reg  [ 8:0] f_col, o_col;
reg  [10:0] o_data;
assign rom_addr  = f_addr;  assign rom_cs  = f_cs;
wire        take  = n_valid && !f_busy && !o_valid;
wire        idle  = !prep_on && !n_valid && !f_busy && !o_valid;
wire        u_rsp = f_busy && f_cs && rom_ok && f_addr_q==f_addr;
reg  [ 8:0] wcol;
reg  [10:0] wdata;
reg         we, wok;

always @(posedge clk) begin
    if( rst ) begin
        pst <= 0; prep_on <= 0; n_valid <= 0; hs_l <= 0; busy_ovr <= 0;
        xrow <= 0; yrow <= 0; xc <= 0; yc <= 0; pcol <= 0; wpar <= 0; we <= 0;
        f_busy <= 0; f_cs <= 0; c_valid <= 0; o_valid <= 0;
    end else begin
        hs_l <= hs;
        we   <= 0;
        f_addr_q <= f_addr;
        if( start_line ) begin
            if( !idle ) busy_ovr <= 1;
            n_valid <= 0; pst <= 0;
            f_busy <= 0; f_cs <= 0; o_valid <= 0;
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
                n_valid <= 0;
                f_col   <= n_col;
                if( !n_inr ) begin
                    o_valid <= 1; o_ok <= 0; o_col <= n_col; o_data <= 0;
                end else if( c_valid && c_addr==n_addr ) begin
                    o_valid <= 1; o_ok <= 1; o_col <= n_col;
                    o_data  <= mkpx( n_attr, n_nib, c_data );
                end else begin
                    f_addr <= n_addr; f_cs <= 1; f_busy <= 1;
                    f_attr <= n_attr; f_nib <= n_nib;
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
                    n_attr  <= p_color;
                    n_col   <= pcol;
                    pcol    <= pcol + 1'd1;
                    pst     <= 0;
                    if( pcol == NCOL-1 ) prep_on <= 0;
                end
                default:;
            endcase

            if( u_rsp ) begin
                f_cs <= 0; f_busy <= 0;
                c_valid <= 1; c_addr <= f_addr; c_data <= rom_data;
                o_valid <= 1; o_ok <= 1; o_col <= f_col;
                o_data  <= mkpx( f_attr, f_nib, rom_data );
            end

            if( o_valid ) begin
                we <= 1; wcol <= o_col; wdata <= o_data; wok <= o_ok; o_valid <= 0;
            end
        end
    end
end

wire [ 8:0] rcol0 = hdump - HVIS0;
wire [ 8:0] rcol  = flip ? NCOL[8:0] - 9'd1 - rcol0 : rcol0;
wire [11:0] rdat;

jtframe_dual_ram #(.DW(12),.AW(10)) u_line(
    .clk0 ( clk ), .data0( {wok, wdata} ), .addr0( {wpar, wcol} ), .we0( we ), .q0(  ),
    .clk1 ( clk ), .data1( 12'd0 ), .addr1( {vdump[0], rcol} ), .we1( 1'b0 ), .q1( rdat )
);
assign pxl    = rdat[10:0];
assign pxl_ok = rdat[11];

endmodule
