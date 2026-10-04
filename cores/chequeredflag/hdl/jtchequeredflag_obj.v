/*  This file is part of the Chequered Flag core for MiSTer. GPLv3. */

module jtchequeredflag_obj(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             flip,

    input      [ 8:0] hdump, vdump, vrender,
    input             hs, lvbl,

    input             cs,
    input      [10:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    output reg [ 7:0] cpu_din,
    output            irq_n, nmi_n,
    output            shadow_mode,

    output reg [19:2] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [31:0] rom_data,

    output            px_src, px_pm, px_sh0, px_sh1,
    output     [ 7:0] px_col,
    output reg        busy_ovr
);

localparam [8:0] ROW0 = 9'h110, HVIS0 = 9'h069;
localparam NCOL = 304;

reg  [7:0] ctrl;
reg  [2:0] shcfg;
reg        irq, nmi, lvbl_l, nmi_l, busy;
wire       vb_start = lvbl_l & ~lvbl;
wire       nmi_line = (vdump[4:0]==0 && vdump>=9'h100) || vdump==9'h0F8;
assign irq_n = ~irq, nmi_n = ~nmi, shadow_mode = shcfg[0];

always @(posedge clk) begin
    if( rst ) begin
        ctrl <= 0; shcfg <= 0; irq <= 0; nmi <= 0; lvbl_l <= 1; nmi_l <= 0;
    end else begin
        lvbl_l <= lvbl;
        nmi_l  <= nmi_line;
        if( cs && cpu_we && !cpu_addr[10] ) case( cpu_addr[2:0] )
            0: begin
                if( ~cpu_dout[0] & ctrl[0] ) irq <= 0;
                if( ~cpu_dout[2] & ctrl[2] ) nmi <= 0;
                ctrl <= cpu_dout;
            end
            1: shcfg <= cpu_dout[2:0];
            default:;
        endcase
        if( vb_start && ctrl[0] ) irq <= 1;
        if( nmi_line && !nmi_l && ctrl[2] ) nmi <= 1;
    end
end

wire [ 7:0] ram_q, ram_dq, buf_q, ord_q;
reg  [ 9:0] ra, ba, bwa;
reg         bwe, owe, rwe;
reg  [ 7:0] bwd, owd;
reg  [ 6:0] owa, ora, rwa, rra;
localparam RW = 78;
reg  [RW-1:0] rwd;
wire [RW-1:0] rq;

always @(*) cpu_din = cpu_addr[10] ? ram_q : ( cpu_addr[2:0]==0 ? {7'd0, busy} : 8'd0 );

jtframe_dual_ram #(.AW(10)) u_ram(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[9:0] ), .we0( cs & cpu_we & cpu_addr[10] ), .q0( ram_q  ),
    .clk1( clk ), .data1( 8'd0     ), .addr1( ra            ), .we1( 1'b0 ),                          .q1( ram_dq )
);
jtframe_dual_ram #(.AW(10)) u_buf(
    .clk0( clk ), .data0( bwd  ), .addr0( bwa ), .we0( bwe  ), .q0(       ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ba  ), .we1( 1'b0 ), .q1( buf_q )
);
jtframe_dual_ram #(.AW(7)) u_ord(
    .clk0( clk ), .data0( owd  ), .addr0( owa ), .we0( owe  ), .q0(       ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ora ), .we1( 1'b0 ), .q1( ord_q )
);

jtframe_dual_ram #(.DW(RW),.AW(7)) u_rec(
    .clk0( clk ), .data0( rwd ),        .addr0( rwa ), .we0( rwe  ), .q0(    ),
    .clk1( clk ), .data1( {RW{1'b0}} ), .addr1( rra ), .we1( 1'b0 ), .q1( rq )
);

function [5:0] zoomy_t( input [5:0] i );
    case( i )
        0: zoomy_t=6'h00; 1: zoomy_t=6'h01; 2: zoomy_t=6'h03; 3: zoomy_t=6'h05; 4: zoomy_t=6'h07; 5: zoomy_t=6'h09;
        6: zoomy_t=6'h0a; 7: zoomy_t=6'h0c; 8: zoomy_t=6'h0e; 9: zoomy_t=6'h0f; 10: zoomy_t=6'h11; 11: zoomy_t=6'h12;
        12: zoomy_t=6'h14; 13: zoomy_t=6'h15; 14: zoomy_t=6'h16; 15: zoomy_t=6'h18; 16: zoomy_t=6'h19; 17: zoomy_t=6'h1a;
        18: zoomy_t=6'h1c; 19: zoomy_t=6'h1d; 20: zoomy_t=6'h1e; 21: zoomy_t=6'h1f; 22: zoomy_t=6'h20; 23: zoomy_t=6'h21;
        24: zoomy_t=6'h22; 25: zoomy_t=6'h23; 26: zoomy_t=6'h24; 27: zoomy_t=6'h25; 28: zoomy_t=6'h26; 29: zoomy_t=6'h27;
        30: zoomy_t=6'h28; 31: zoomy_t=6'h29; 32: zoomy_t=6'h2a; 33: zoomy_t=6'h2b; 34: zoomy_t=6'h2c; 35: zoomy_t=6'h2d;
        36: zoomy_t=6'h2e; 37: zoomy_t=6'h2e; 38: zoomy_t=6'h2f; 39: zoomy_t=6'h30; 40: zoomy_t=6'h31; 41: zoomy_t=6'h31;
        42: zoomy_t=6'h32; 43: zoomy_t=6'h33; 44: zoomy_t=6'h34; 45: zoomy_t=6'h34; 46: zoomy_t=6'h35; 47: zoomy_t=6'h36;
        48: zoomy_t=6'h36; 49: zoomy_t=6'h37; 50: zoomy_t=6'h38; 51: zoomy_t=6'h38; 52: zoomy_t=6'h39; 53: zoomy_t=6'h39;
        54: zoomy_t=6'h3a; 55: zoomy_t=6'h3b; 56: zoomy_t=6'h3b; 57: zoomy_t=6'h3c; 58: zoomy_t=6'h3c; 59: zoomy_t=6'h3d;
        60: zoomy_t=6'h3d; 61: zoomy_t=6'h3e; 62: zoomy_t=6'h3e; default: zoomy_t=6'h3f;
    endcase
endfunction

localparam F_IDLE=0, F_DMA=1, F_CLR=2, F_SORT=3, F_DEC=4;
reg  [ 2:0] fph;
reg  [10:0] fcnt;
reg  [ 9:0] a1, a2;
reg         v1, v2;
reg  [ 7:0] nact;
reg  [ 7:0] nrec, nrec_l;
reg  [15:0] busy_cnt;
reg  [ 6:0] dent;
reg  [ 3:0] dst;
reg  [ 7:0] sb [0:7];

reg  [ 1:0] d_wl, d_hl;
reg  [12:0] d_code;
reg  [ 7:0] d_z;
reg  [16:0] d_zx, d_zy;
reg  [ 9:0] d_oy;
always @(*) begin
    case( sb[1][7:5] )
        0: {d_wl,d_hl} = {2'd0,2'd0}; 1: {d_wl,d_hl} = {2'd1,2'd0}; 2: {d_wl,d_hl} = {2'd0,2'd1};
        3: {d_wl,d_hl} = {2'd1,2'd1}; 4: {d_wl,d_hl} = {2'd2,2'd1}; 5: {d_wl,d_hl} = {2'd1,2'd2};
        6: {d_wl,d_hl} = {2'd2,2'd2}; default: {d_wl,d_hl} = {2'd3,2'd3};
    endcase
    d_code = { sb[1][4:0], sb[2] };
    if( d_wl>=1 ) d_code[0]=0;  if( d_hl>=1 ) d_code[1]=0;  if( d_wl>=2 ) d_code[2]=0;
    if( d_hl>=2 ) d_code[3]=0;  if( d_wl>=3 ) d_code[4]=0;  if( d_hl>=3 ) d_code[5]=0;
    d_oy = 10'd256 - { 1'b0, sb[4][0], sb[5] };
    d_zx = 17'd512 * (17'd128 - {11'd0, sb[6][7:2]});
    d_z  = 8'd128 - {2'd0, zoomy_t(sb[4][7:2])};

    if( d_hl<=0 ) d_z = (d_z+1'd1)>>1;
    if( d_hl<=1 ) d_z = (d_z+1'd1)>>1;
    if( d_hl<=2 ) d_z = (d_z+1'd1)>>1;
    d_z  = d_z << (2'd3-d_hl);
    d_zy = 17'd512 * {9'd0, d_z};
end
wire d_sh = !shcfg[2] && (shcfg[1] || sb[3][7]);
wire d_pm = !sb[3][4];

always @(posedge clk) begin
    bwe <= 0; owe <= 0; rwe <= 0;
    if( rst ) begin
        fph <= F_IDLE; busy <= 0; busy_cnt <= 0; nrec <= 0; nrec_l <= 0; v1 <= 0; v2 <= 0;
    end else begin
        if( busy_cnt != 0 ) busy_cnt <= busy_cnt - 1'd1; else busy <= 0;
        a1 <= fph==F_DMA ? ra : ba;  a2 <= a1;
        v2 <= v1;
        case( fph )
            F_IDLE: if( vb_start ) begin
                fcnt <= 0; v1 <= 0;
                if( !ctrl[4] ) begin fph <= F_DMA; busy <= 1; busy_cnt <= 16'hffff; end
                else fph <= F_CLR;
            end
            F_DMA: begin
                ra <= fcnt[9:0];
                v1 <= !fcnt[10];
                if( v2 ) begin bwa <= a1; bwd <= ram_dq; bwe <= 1; end
                fcnt <= fcnt + 1'd1;
                if( fcnt == 11'd1026 ) begin fph <= F_CLR; fcnt <= 0; v1 <= 0; end
            end
            F_CLR: begin
                owa <= fcnt[6:0]; owd <= 0; owe <= 1;
                fcnt <= fcnt + 1'd1;
                if( fcnt == 11'd127 ) begin fph <= F_SORT; fcnt <= 0; nact <= 0; v1 <= 0; end
            end
            F_SORT: begin
                ba <= { fcnt[6:0], 3'd0 };
                v1 <= !fcnt[7];
                if( v2 && buf_q[7] ) begin
                    owa <= buf_q[6:0] ^ 7'h7f; owd <= { 1'b1, a1[9:3] }; owe <= 1;
                    nact <= nact + 1'd1;
                end
                fcnt <= fcnt + 1'd1;
                if( fcnt == 11'd130 ) begin
                    fph <= F_DEC; dent <= 0; dst <= 0; nrec <= 0; v1 <= 0;

                    if( busy ) busy_cnt <= ({8'd0,nact}*16'd32 + (16'd128-{8'd0,nact})*16'd18) << 3;
                end
            end
            F_DEC: begin
                dst <= dst + 1'd1;
                case( dst )
                    0: ora <= dent;
                    2: if( !ord_q[7] ) dst <= 4'd13;
                       else ba <= { ord_q[6:0], 3'd0 };
                    3,4,5,6,7,8,9: ba <= ba + 1'd1;
                    12: begin
                        rwa <= nrec[6:0]; rwe <= 1; nrec <= nrec + 1'd1;
                        rwd <= { d_code, sb[3][3:0], d_pm, d_sh, d_wl, d_hl, sb[6][0], sb[7], d_oy,
                                 sb[6][1], sb[4][1], d_zx, d_zy };
`ifdef CF_OBJ_DEBUG
                        $display("obj rec %0d: code=%04X wl=%0d hl=%0d ox=%0d oy=%0d zx=%05X zy=%05X z=%0d bytes=%02X %02X %02X %02X %02X %02X %02X %02X",
                            nrec, d_code, d_wl, d_hl, {sb[6][0],sb[7]}, $signed(d_oy), d_zx, d_zy, d_z,
                            sb[0],sb[1],sb[2],sb[3],sb[4],sb[5],sb[6],sb[7]);
`endif
                    end
                    13: begin
                        dst  <= 0;
                        dent <= dent + 1'd1;
                        if( dent == 7'd127 ) begin
                            fph <= F_IDLE; nrec_l <= nrec;
`ifdef CF_OBJ_DEBUG
                            $display("obj: frame preparado: activos=%0d registros=%0d ctrl=%02X", nact, nrec, ctrl);
`endif
                        end
                    end
                    default:;
                endcase
                if( dst>=4 && dst<=11 ) sb[dst-4'd4] <= buf_q;
            end
            default: fph <= F_IDLE;
        endcase
    end
end

function [20:0] recip( input [4:0] z );
    case( z )
        1: recip=21'd1048576; 2: recip=21'd524288; 3: recip=21'd349525; 4: recip=21'd262144;
        5: recip=21'd209715;  6: recip=21'd174762; 7: recip=21'd149796; 8: recip=21'd131072;
        9: recip=21'd116508; 10: recip=21'd104857; 11: recip=21'd95325; 12: recip=21'd87381;
        13: recip=21'd80659; 14: recip=21'd74898;  15: recip=21'd69905; 16: recip=21'd65536;
        default: recip=21'd0;
    endcase
endfunction

wire [12:0] r_code = rq[77:65];
wire [ 3:0] r_col  = rq[64:61];
wire        r_pm   = rq[60], r_sh = rq[59];
wire [ 1:0] r_wl   = rq[58:57], r_hl = rq[56:55];
wire [ 8:0] r_ox   = rq[54:46];
wire [ 9:0] r_oy   = rq[45:36];
wire        r_fx   = rq[35], r_fy = rq[34];
wire [16:0] r_zx   = rq[33:17], r_zy = rq[16:0];
wire [ 3:0] rw = 4'd1 << r_wl, rh = 4'd1 << r_hl;
wire signed [11:0] oy_s = {{2{r_oy[9]}}, r_oy};
wire signed [11:0] ox_s = {3'd0, r_ox};

function [11:0] zpos( input [16:0] z, input [3:0] n );
    reg [20:0] t;
    begin t = {4'd0,z} * {17'd0,n} + 21'd2048; zpos = {3'd0, t[20:12]}; end
endfunction

localparam L_IDLE=0, L_RD=1, L_LAT=2, L_CHK=3, L_YS=4, L_ROW=5, L_CELL=6, L_F0=7, L_F1=8,
           L_ROM=9, L_PIX=10, L_NXC=11, L_NXS=12;
reg  [ 3:0] lst;
reg  [ 6:0] li;
reg  [ 3:0] yi, xi;
reg  signed [11:0] ly, sy, nsy, sx, nsx, destx, c0, c1, col;
reg  [ 4:0] zh, zw;
reg  [20:0] dy, dx;
reg  [ 3:0] srow;
reg  [12:0] ccode;
reg  [31:0] wlo, whi;
reg  [23:0] acc;
reg         wpar, wtag, hs_l;
reg  [NCOL-1:0] f_src, f_sh0, f_sh1;
reg  [ 8:0] lwa;
reg  [12:0] lwd;
reg         lwe;
reg  [19:2] rom_addr_q;
wire [ 2:0] xoff_i = r_fx ? (r_wl==0 ? 3'd0 : (rw[2:0]-3'd1-xi[2:0])) : xi[2:0];
wire [ 2:0] yoff_i = r_fy ? (r_hl==0 ? 3'd0 : (rh[2:0]-3'd1-yi[2:0])) : yi[2:0];

wire [ 5:0] xo = { 1'b0, xoff_i[2], 1'b0, xoff_i[1], 1'b0, xoff_i[0] };
wire [ 5:0] yo = { yoff_i[2], 1'b0, yoff_i[1], 1'b0, yoff_i[0], 1'b0 };
wire signed [11:0] ybot = oy_s + $signed(zpos(r_zy, rh));
wire signed [11:0] cend = destx + $signed({7'd0, zw}) - 12'sd1;
wire [23:0] off_y = {12'd0, ly - sy};
wire [23:0] ry_n  = off_y[4:0] * dy;
wire [23:0] ry_f  = ({19'd0, zh} - 24'd1) * dy - ry_n;
wire [ 3:0] pxc   = acc[19:16];
wire [31:0] wsel  = pxc[3] ? whi : wlo;
wire [ 2:0] bsel  = 3'd7 - pxc[2:0];
wire [ 3:0] pen   = { wsel[24+bsel], wsel[16+bsel], wsel[8+bsel], wsel[bsel] };
wire [ 8:0] ccol  = col[8:0];
wire        is_sh  = r_sh && pen==4'hf;
wire        is_src = pen!=0 && !is_sh;
wire        vis_row = vrender >= ROW0 && vrender < ROW0+9'd224;
wire [23:0] off_x  = {12'd0, c0 - destx};
wire [23:0] acc_n  = off_x[4:0] * dx;
wire [23:0] acc_f  = ({19'd0, zw} - 24'd1) * dx - acc_n;

always @(posedge clk) begin
    lwe <= 0;
    rom_addr_q <= rom_addr;
    if( rst ) begin
        lst <= L_IDLE; rom_cs <= 0; hs_l <= 0; busy_ovr <= 0;
    end else begin
        hs_l <= hs;
        if( hs && !hs_l ) begin
            if( lst != L_IDLE ) busy_ovr <= 1;
            rom_cs <= 0;
            f_src <= 0; f_sh0 <= 0; f_sh1 <= 0;
            wpar <= vrender[0]; wtag <= vrender[1];

            ly   <= flip ? 12'sd239 - ($signed({3'd0, vrender}) - 12'sh110)
                         : $signed({3'd0, vrender}) - 12'sh110 + 12'sd16;
            li   <= 0;
            lst  <= (vis_row && nrec_l!=0) ? L_RD : L_IDLE;
        end else case( lst )
            L_RD:  begin rra <= li; lst <= L_LAT; end
            L_LAT: lst <= L_CHK;
            L_CHK: if( ly < oy_s || ly >= ybot ) lst <= L_NXS;
                   else begin yi <= 0; lst <= L_YS; end
            L_YS: begin
                sy  <= oy_s + $signed(zpos(r_zy, yi));
                nsy <= oy_s + $signed(zpos(r_zy, yi+4'd1));
                lst <= L_ROW;
            end
            L_ROW: begin
                if( ly >= nsy ) begin yi <= yi + 1'd1; lst <= L_YS; end
                else begin
                    zh  <= nsy[4:0] - sy[4:0];
                    dy  <= recip( nsy[4:0] - sy[4:0] );
                    xi  <= 0;
                    lst <= L_CELL;
                end
            end
            L_CELL: begin
                srow <= r_fy ? ry_f[19:16] : ry_n[19:16];
                sx   <= ox_s + $signed(zpos(r_zx, xi));
                nsx  <= ox_s + $signed(zpos(r_zx, xi+4'd1));
                lst  <= L_F0;
            end
            L_F0: begin
                zw    <= nsx[4:0] - sx[4:0];
                dx    <= recip( nsx[4:0] - sx[4:0] );
                destx <= $signed({3'd0, sx[8:0]}) - 12'sd96;
                ccode <= r_code + {7'd0, xo} + {7'd0, yo};
                lst   <= L_F1;
            end
            L_F1: begin
                c0 <= destx < 0 ? 12'sd0 : destx;
                c1 <= cend > 12'sd303 ? 12'sd303 : cend;
                if( zw==0 || destx > 12'sd303 || cend < 0 ) lst <= L_NXC;
                else begin
                    rom_addr <= { ccode, srow[3], 1'b0, srow[2:0] }; rom_cs <= 1;
                    lst <= L_ROM;
                end
            end
            L_ROM: if( rom_cs && rom_ok && rom_addr_q==rom_addr ) begin
                if( !rom_addr[5] ) begin
                    wlo <= rom_data; rom_addr[5] <= 1;
                end else begin
                    whi <= rom_data; rom_cs <= 0;
                    col <= c0;
                    acc <= r_fx ? acc_f : acc_n;
                    lst <= L_PIX;
                end
            end
            L_PIX: begin
                if( !f_src[ccol] ) begin
                    if( is_src ) begin
                        f_src[ccol] <= 1;
                        lwa <= ccol; lwe <= 1;
                        lwd <= { 1'b0, 1'b1, r_col, pen, r_pm, f_sh0[ccol], f_sh1[ccol] };
                    end else if( is_sh ) begin
                        if( r_pm ) f_sh1[ccol] <= 1; else f_sh0[ccol] <= 1;
                        lwa <= ccol; lwe <= 1;
                        lwd <= { 1'b0, 1'b0, 8'd0, 1'b0, f_sh0[ccol] | ~r_pm, f_sh1[ccol] | r_pm };
                    end
                end
                acc <= r_fx ? acc - dx : acc + dx;
                col <= col + 1'd1;
                if( col == c1 ) lst <= L_NXC;
            end
            L_NXC: begin
                if( xi == rw-4'd1 ) lst <= L_NXS;
                else begin xi <= xi + 1'd1; lst <= L_CELL; end
            end
            L_NXS: begin
                if( {1'b0,li} == nrec_l-8'd1 ) lst <= L_IDLE;
                else begin li <= li + 1'd1; lst <= L_RD; end
            end
            default: lst <= L_IDLE;
        endcase
    end
end

wire [11:0] lq;
wire [ 8:0] rcol0 = hdump - HVIS0;
wire [ 8:0] rcol  = flip ? 9'd303 - rcol0 : rcol0;
reg  [ 2:0] rph;
reg  [11:0] pxr;
always @(posedge clk) begin
    rph <= pxl_cen ? 3'd1 : (rph!=0 ? rph + 3'd1 : 3'd0);
    if( rph==3'd3 ) pxr <= lq;
end
wire erase = rph==3'd3;
jtframe_dual_ram #(.DW(12),.AW(10)) u_line(
    .clk0( clk ), .data0( lwd[11:0] ), .addr0( {wpar, lwa} ),       .we0( lwe   ), .q0(    ),
    .clk1( clk ), .data1( 12'd0 ),     .addr1( {vdump[0], rcol} ), .we1( erase ), .q1( lq )
);
assign px_src = pxr[11];
assign px_col = pxr[10:3];
assign px_pm  = pxr[2];
assign px_sh0 = pxr[1];
assign px_sh1 = pxr[0];

endmodule
