/*  This file is part of the xexex core (konami-fpga). GPLv3. */

module xexex_k053250(
    input             rst,
    input             clk,
    input             pxl_cen,

    input             ram_cs,
    input             reg_cs,
    input             rom_cs,
    input             cpu_we,
    input      [12:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    output     [15:0] cpu_din,
    output            cpu_ok,

    output     [17:2] rom0_addr,
    output            rom0_cs,
    input      [31:0] rom0_data,
    input             rom0_ok,
    output     [17:2] rom1_addr,
    output            rom1_cs,
    input      [31:0] rom1_data,
    input             rom1_ok,

    input             lhbl,
    input      [ 8:0] hdump,
    input      [ 8:0] vrender1,
    input      [ 8:0] pc_line,
    output     [ 8:0] pxl
);

localparam signed [15:0] OFFX = -16'sd5, OFFY = -16'sd16;

reg  [18:2] rom_addr;
reg         rom_cs_o;
wire        sw_cs0, sw_cs1;
wire [17:2] sw_a0, sw_a1;
wire [31:0] rom_data = rom_addr[2] ? rom1_data : rom0_data;
wire        rom_ok   = rom_addr[2] ? rom1_ok   : rom0_ok;
assign rom0_cs   = (rom_cs_o & ~rom_addr[2]) | sw_cs0;
assign rom1_cs   = (rom_cs_o &  rom_addr[2]) | sw_cs1;
assign rom0_addr = sw_cs0 ? sw_a0 : rom_addr[18:3];
assign rom1_addr = sw_cs1 ? sw_a1 : rom_addr[18:3];

reg  [33:0] q0 [0:15];
reg  [33:0] q1 [0:15];
reg  [ 3:0] qw0, qr0, qw1, qr1;
reg  [ 4:0] q_n0, q_n1;
wire        q_full0 = q_n0==5'd16, q_full1 = q_n1==5'd16;
reg         enq0, enq1, deq0, deq1;
reg         e_bsy0, e_bsy1, e_pl0, e_pl1, e_pc0, e_pc1;
reg  [33:0] e_en0, e_en1;
reg  [33:0] r_en0, r_en1;
reg  [31:0] e_d0, e_d1;
function [3:0] nibpen(input [31:0] d, input [2:0] n);
    reg [7:0] b;
    begin b = d[{n[2:1],3'b000}+:8]; nibpen = n[0] ? b[3:0] : b[7:4]; end
endfunction
wire [ 3:0] e_pen0 = nibpen(e_d0, r_en0[24:22]);
wire [ 3:0] e_pen1 = nibpen(e_d1, r_en1[24:22]);
assign sw_cs0 = e_bsy0, sw_a0 = e_en0[21:6];
assign sw_cs1 = e_bsy1, sw_a1 = e_en1[21:6];
wire        swp_idle = q_n0==5'd0 && q_n1==5'd0 && !e_bsy0 && !e_bsy1 && !e_pl0 && !e_pl1 && !e_pc0 && !e_pc1;
localparam [8:0] VX0 = 9'd40, VX1 = 9'd423, VY0 = 9'd0, VY1 = 9'd255;

reg  [7:0] regs[0:7];
wire [15:0] ram_q;
wire [ 1:0] ram_we = {2{ram_cs & cpu_we}} & ~cpu_dsn;
reg        page;
reg        r4b1_l;

always @(posedge clk, posedge rst) begin : regs_rst
    integer ri;
    if( rst ) for( ri=0; ri<8; ri=ri+1 ) regs[ri] <= 8'd0;
    else if( reg_cs && cpu_we && !cpu_dsn[0] ) regs[cpu_addr[3:1]] <= cpu_dout[7:0];
end

reg        dma_bsy;
reg [10:0] dma_a;
reg        dma_ph;
wire       r4b1 = regs[4][1];
always @(posedge clk, posedge rst) begin
    if( rst ) begin dma_bsy<=0; dma_a<=0; dma_ph<=0; page<=0; r4b1_l<=0; end
    else begin
        r4b1_l <= r4b1;
        if( r4b1_l && !r4b1 && !dma_bsy ) begin dma_bsy<=1; dma_a<=0; dma_ph<=0; end
        else if( dma_bsy ) begin
            dma_ph <= ~dma_ph;
            if( dma_ph ) begin
                if( dma_a==11'h7ff ) begin dma_bsy<=0; page<=~page; end
                dma_a <= dma_a + 11'd1;
            end
        end
    end
end

wire [15:0] ram_dma_q;
jtframe_dual_ram16 #(.AW(12)) u_ram(
    .clk0   ( clk       ), .data0( cpu_dout  ), .addr0( cpu_addr[12:1] ), .we0( ram_we ), .q0( ram_q ),
    .clk1   ( clk       ), .data1( 16'd0     ), .addr1( {1'b0, dma_a} ),  .we1( 2'b00  ), .q1( ram_dma_q )
);

reg  [10:0] lr_a;
wire [15:0] lr_q;
jtframe_dual_ram16 #(.AW(12)) u_lbuf(
    .clk0   ( clk ), .data0( ram_dma_q ), .addr0( {page, dma_a} ), .we0( {2{dma_bsy & dma_ph}} ), .q0( ),
    .clk1   ( clk ), .data1( 16'd0     ), .addr1( {page, lr_a}  ), .we1( 2'b00 ),                   .q1( lr_q )
);

wire [18:0] cpu_byte = { regs[7], cpu_addr[12:2] };
reg         cpu_srv;
reg  [ 7:0] cpu_byte_q;
reg         cpu_ok_r;
assign cpu_ok = cpu_ok_r;
reg [15:0] rd_r;
always @(posedge clk) rd_r <= ram_cs ? ram_q : { 8'h00, regs[cpu_addr[3:1]] };
assign cpu_din = rom_cs ? { 8'h00, cpu_byte_q } : rd_r;

wire [7:0] ctrl  = regs[4];
wire       swp   = ~ctrl[0];
wire       fx    = ctrl[3];
wire       fy    = ctrl[4];
wire       flip  = swp ? fy : fx;
wire [2:0] mode  = ctrl[7:5];
wire [9:0] clipm = ctrl[2] ? 10'd0 : (mode==3'd0 || mode==3'd4) ? 10'h0ff : mode==3'd1 ? 10'h1ff : 10'h3ff;
wire [9:0] wrapm = (mode==3'd0 || mode==3'd4) ? 10'h0ff : mode==3'd1 ? 10'h1ff : 10'h3ff;
wire       twop  = swp && clipm!=10'd0;
wire [9:0] dhgt  = mode==3'd0 ? 10'd256 : 10'd512;
wire signed [15:0] mscx = $signed({regs[0],regs[1]}) - OFFX;
wire signed [15:0] mscy = $signed({regs[2],regs[3]}) - OFFY;
wire signed [15:0] scorr= swp ? (fy ? 16'sh100 - mscy - 16'sd2 : mscy)
                              : (fx ? -mscx : mscx);

wire signed [23:0] dmin = swp ? $signed({15'd0,VY0}) : $signed({15'd0,VX0});
wire signed [23:0] dmax = swp ? $signed({15'd0,VY1}) : $signed({15'd0,VX1});

localparam R_IDLE=0, R_E0=1, R_E1=2, R_E2=3, R_E3=4, R_E4=5, R_CALC=6, R_DIV=7, R_CLIP=8, R_MUL=9,
           R_FLIP=10, R_PIX=11, R_WAIT=12, R_STORE=13, R_S0=14, R_S1=15, R_S2=16, R_S3=17, R_SW=18,
           R_PF=19, R_PFW=20, R_WE=21, R_PCF=22, R_RC1=23, R_RC2=24, R_SDN=25;

wire [8:0] PC_LINE = pc_line;

parameter  [11:0] PF_LIM = 12'd2300;
reg  [4:0]  rst_st;
reg  [8:0]  rline;
reg         rbank, dbank;
reg         prev_lhbl;
reg  [15:0] e_color, e_offs, e_zoom, e_scroll;
reg  signed [23:0] scroll_v;
reg  signed [23:0] dst_start, dst_len;
reg  signed [47:0] src_fx, src_fdx;
reg  [16:0] div_n, div_q; reg [16:0] div_r; reg [4:0] div_i;
reg  [23:0] k;
reg  [16:0] c_waddr;
reg         c_valid;
reg  [31:0] c_data;

reg  [127:0] rc_v;
reg  [  6:0] rc_ra, rc_wi;
reg          rc_ok;
wire [ 31:0] rc_q;
jtframe_dual_ram #(.DW(32),.AW(7)) u_rowc(
    .clk0( clk ), .data0( rom_data ), .addr0( rc_wi ), .we0( rst_st==R_WAIT && rom_ok && rc_ok ), .q0( ),
    .clk1( clk ), .data1( 32'd0 ),    .addr1( rc_ra ), .we1( 1'b0 ),                             .q1( rc_q )
);

reg         pc;
reg  [8:0]  col;
reg         pass, pv;
reg         cempty;
reg  [8:0]  wa;
reg  [77:0] p0_st;
reg  [25:0] fxe;

wire [15:0] ofs_base = swp ? ((fy ? mscx - 16'sd5 : mscx) + (fx ? {7'd0,VX1} : 16'd0))
                           : (fy ? (mscy + 16'sd255) : mscy);
wire [8:0]  lpos     = swp ? VX0 + col : {1'b0, rline[7:0]};
wire        lneg     = swp ? fx : fy;
wire [10:0] ofs_line = ({ofs_base[8:0],2'b0}) + (lneg ? -{lpos,2'b0} : {lpos,2'b0});

reg  [8:0]  lb_wa; reg [8:0] lb_wd; reg lb_we;
wire [8:0]  lb0_q, lb1_q;

wire signed [47:0] fx_k = src_fx;
wire [31:0] idx_raw = fx_k[47:16];
wire [19:0] idx_m   = (clipm!=10'd0) ? idx_raw[19:0] : {10'd0, idx_raw[9:0] & wrapm};
wire [19:0] nib_now = {e_offs[11:0],8'd0} + idx_m;
wire [16:0] waddr_now = nib_now[19:3];
wire [7:0]  byte_now  = c_data[{nib_now[2:1],3'b000}+:8];
wire [3:0]  pen_now   = nib_now[0] ? byte_now[3:0] : byte_now[7:4];
wire signed [23:0] dpos = dst_start + $signed(k);

localparam CSTW = 191;

reg  [8:0] rcol;
always @* rcol = (rst_st==R_S0) ? col : col + 9'd1;
wire [CSTW-1:0] cst_q;
reg  [CSTW-1:0] cst_d;
reg             cst_we;
jtframe_dual_ram #(.DW(CSTW),.AW(9)) u_cst(
    .clk0( clk ), .data0( cst_d ), .addr0( wa ), .we0( cst_we ), .q0( ),
    .clk1( clk ), .data1( {CSTW{1'b0}} ), .addr1( rcol ), .we1( 1'b0 ), .q1( cst_q )
);

wire [99:0] cc_q;
reg  [99:0] cc_d;
reg         cc_we;
jtframe_dual_ram #(.DW(100),.AW(9)) u_ccache(
    .clk0( clk ), .data0( cc_d ), .addr0( wa ), .we0( cc_we ), .q0( ),
    .clk1( clk ), .data1( 100'd0 ), .addr1( rcol ), .we1( 1'b0 ), .q1( cc_q )
);
reg  [CSTW-1:0] ce;
wire            ce_v    = ce[190];
wire [ 4:0]     ce_col  = ce[189:185];
wire [11:0]     ce_offs = ce[184:173];
wire [15:0]     ce_zoom = ce[172:157];
wire            ce_flip = ce[156];
wire [77:0]     ce_p0   = ce[155:78], ce_p1 = ce[77:0];
wire [77:0]     ce_p    = pass ? ce_p1 : ce_p0;
wire            cp_v    = ce_p[77];
wire [ 7:0]     cp_ds   = ce_p[76:69];
wire [ 8:0]     cp_dl   = ce_p[68:60];
wire [25:0]     cp_fx   = ce_p[59:34];
wire [16:0]     cp_we   = ce_p[16:0];
wire [ 9:0]     smask   = (clipm!=10'd0) ? 10'h3ff : wrapm;

function [16:0] wordof(input [25:0] f);
    reg [19:0] n;
    begin n = {e_offs[11:0],8'd0} + {10'd0, f[25:16] & smask}; wordof = n[19:3]; end
endfunction
wire [ 7:0]     sy      = rline[7:0];
wire            cp_hit  = cp_v && sy >= cp_ds && {2'b0,sy} < {2'b0,cp_ds} + {1'b0,cp_dl};
wire [ 7:0]     cp_k    = sy - cp_ds;
wire [25:0]     cp_step = {cp_k, 10'd0} * ce_zoom;
reg  [25:0]     sfx;
wire [ 9:0]     s_idx   = sfx[25:16] & smask;
wire [19:0]     s_nib   = {ce_offs,8'd0} + {10'd0,s_idx};
wire [16:0]     s_wa    = s_nib[19:3];
reg             s_cv;  reg [16:0] s_ctag;  reg [31:0] s_cw;
reg             s_bv;  reg [16:0] s_btag;  reg [31:0] s_bw;
reg             cdirty;
reg             pf_ok;
reg  [16:0]     pf_wa;
reg  [11:0]     lcyc;

wire            up0     = ce_p0[77] && ce_p0[76:69] > sy;
wire            up1     = ce_p1[77] && ce_p1[76:69] > sy;
wire [16:0]     up_w    = (up0 && (!up1 || ce_p0[76:69] <= ce_p1[76:69])) ? ce_p0[33:17] : ce_p1[33:17];
wire [16:0]     pf_tgt  = pf_ok ? pf_wa : up_w;
wire [13:0]     pf_rsv  = {3'd0, 9'd383 - col, 2'd0};
wire            pf_need = (pf_ok || up0 || up1) && ({2'd0,lcyc} + pf_rsv) < {2'd0,PF_LIM} &&
                          !(s_cv && s_ctag==pf_tgt) && !(s_bv && s_btag==pf_tgt);
wire [ 7:0]     s_byte  = s_cw[{s_nib[2:1],3'b000}+:8];
wire [ 3:0]     s_pen   = s_nib[0] ? s_byte[3:0] : s_byte[7:4];
wire            pl_wr   = rst_st==R_S3 && s_cv && s_ctag==s_wa && s_pen!=4'd0;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        rst_st<=R_IDLE; rbank<=0; dbank<=1; prev_lhbl<=1; rline<=0; lr_a<=0;
        rom_cs_o<=0; rom_addr<=0; cpu_srv<=0; cpu_ok_r<=0; cpu_byte_q<=0; c_valid<=0; lb_we<=0;
        pc<=0; col<=0; pass<=0; pv<=0; cempty<=0; wa<=0; cst_we<=0; cc_we<=0;
        qw0<=0; qr0<=0; q_n0<=0; qw1<=0; qr1<=0; q_n1<=0;
        e_bsy0<=0; e_pl0<=0; e_pc0<=0; e_bsy1<=0; e_pl1<=0; e_pc1<=0;
    end else begin
        enq0 = 1'b0; enq1 = 1'b0; deq0 = 1'b0; deq1 = 1'b0;
        prev_lhbl <= lhbl;
        lcyc   <= (prev_lhbl && !lhbl) ? 12'd0 : (lcyc==12'hfff ? lcyc : lcyc + 12'd1);
        lb_we  <= 0;
        cst_we <= 0;
        cc_we  <= 0;

        if( !rom_cs ) cpu_ok_r <= 0;
        if( rom_cs && !cpu_ok_r && rst_st==R_IDLE && !cpu_srv && !rom_cs_o ) begin
            cpu_srv<=1; rom_cs_o<=1; rom_addr<=cpu_byte[18:2];
        end
        if( cpu_srv && rom_ok ) begin
            cpu_byte_q <= rom_data[{cpu_byte[1:0],3'b000}+:8];
            cpu_ok_r<=1; cpu_srv<=0; rom_cs_o<=0; c_valid<=0;
        end

        if( prev_lhbl && !lhbl && rst_st==R_IDLE && !cpu_srv ) begin
            dbank<=rbank; rbank<=~rbank; rline<=vrender1;
            if( !swp ) rst_st<=R_E0;
            else if( vrender1==PC_LINE ) begin pc<=1; col<=0; rst_st<=R_E0; end
            else if( vrender1[8] ) begin col<=0; rst_st<=R_S0; end
        end
        case( rst_st )
        R_IDLE: ;
        R_E0: begin lr_a <= ofs_line; rc_v <= 128'd0; rst_st<=R_E1; end
        R_E1: begin lr_a <= ofs_line + 11'd1; rst_st<=R_E2; end
        R_E2: begin e_color <= lr_q; lr_a <= ofs_line + 11'd2; rst_st<=R_E3; end
        R_E3: begin e_offs  <= lr_q; lr_a <= ofs_line + 11'd3; rst_st<=R_E4; end
        R_E4: begin e_zoom  <= lr_q; rst_st<=R_CALC; end
        R_CALC: begin
            e_scroll <= lr_q;
            pass <= 0;
            if( e_color==16'hffff || (e_color[7:0]==8'd0 && e_offs==16'd0) || (!pc && rline[8]==1'b0) ) begin
                if( pc ) begin cempty <= 1; pv <= 0; rst_st <= R_STORE; end
                else rst_st <= R_IDLE;
            end else begin
                cempty <= 0;

                begin : sc
                    reg signed [23:0] s;
                    s = $signed({{8{lr_q[15]}},lr_q})
                      - ((mode==3'd4 && $signed(lr_q) >= 16'sh0500) ? 24'sd2048 : 24'sd0)
                      + $signed({{8{scorr[15]}},scorr});
                    scroll_v <= twop ? $signed({14'd0, s[9:0] & (dhgt-10'd1)}) : s;
                end
                src_fdx  <= $signed({22'd0, e_zoom, 10'd0});

                div_n <= ({7'd0,clipm} + 17'd1) << 6; div_r <= 0; div_q <= 0; div_i <= 5'd16;
                rst_st <= (clipm!=10'd0) ? R_DIV : R_MUL;
            end
        end
        R_DIV: begin
            begin : divstep
                reg [17:0] t;
                t = {div_r[16:0], div_n[div_i]};
                if( e_zoom!=16'd0 && t >= {2'b0,e_zoom} ) begin div_r <= t - {2'b0,e_zoom}; div_q[div_i] <= 1'b1; end
                else begin div_r <= t[16:0]; div_q[div_i] <= 1'b0; end
            end
            if( div_i==5'd0 ) rst_st <= R_CLIP; else div_i <= div_i - 5'd1;
        end
        R_CLIP: begin

            src_fdx <= $signed({22'd0, e_zoom, 10'd0});
            pv <= 0;
            begin : clipc
                reg signed [23:0] ds, dl, ep;
                ds = -scroll_v;
                dl = (e_zoom!=16'd0) ? $signed({7'd0,div_q}) : $signed({14'd0,clipm}+24'd1);
                if( ds > dmax ) rst_st <= pc ? R_STORE : R_IDLE;
                else begin
                    ep = ds + dl - 24'sd1;
                    if( ep < dmin ) rst_st <= pc ? R_STORE : R_IDLE;
                    else begin
                        ep = ep - dmax;
                        if( ep > 0 ) dl = dl - ep;
                        if( dl <= 0 ) rst_st <= pc ? R_STORE : R_IDLE;
                        else begin
                            ep = dmin - ds;
                            if( ep > 0 ) begin
                                dl = dl - ep; ds = dmin;
                                src_fx <= $signed({{24{ep[23]}},ep}) * $signed({22'd0,e_zoom,10'd0}) + 48'sd32768;
                            end else src_fx <= 48'sd32768;
                            dst_start <= ds; dst_len <= dl;
                            pv <= 1;
                            rst_st <= R_FLIP;
                        end
                    end
                end
            end
        end
        R_MUL: begin
            dst_start <= dmin;
            dst_len   <= dmax - dmin + 24'sd1;
            src_fx    <= ($signed(scroll_v) + (flip ? dmax : dmin)) * $signed({22'd0,e_zoom,10'd0})
                         + 48'sd32768 - (flip ? 48'sd1 : 48'sd0);
            if( flip ) src_fdx <= -$signed({22'd0, e_zoom, 10'd0});
            k <= 0; c_valid <= 0; pv <= 1;
            rst_st <= pc ? R_WE : R_PIX;
        end
        R_FLIP: begin
            if( flip ) begin
                dst_start <= dmax + dmin - dst_start - (dst_len - 24'sd1);
                src_fx    <= src_fx + $signed(dst_len - 24'sd1) * src_fdx - 48'sd1;
                src_fdx   <= -src_fdx;
            end
            k <= 0; c_valid <= 0;
            rst_st <= pc ? R_WE : R_PIX;
        end
        R_WE: begin
            fxe    <= src_fx[25:0] + (dst_len[8:0] - 9'd1) * src_fdx[25:0];
            rst_st <= R_STORE;
        end
        R_STORE: begin
            if( !pass && twop && !cempty ) begin
                p0_st    <= { pv, dst_start[7:0], dst_len[8:0], src_fx[25:0], wordof(src_fx[25:0]), wordof(fxe) };
                pass     <= 1;
                scroll_v <= scroll_v - $signed({14'd0,dhgt});
                rst_st   <= R_CLIP;
            end else begin
                begin : st
                    reg [77:0] pa, pb, pcur;
                    reg        v;
                    pcur = { pv, dst_start[7:0], dst_len[8:0], src_fx[25:0], wordof(src_fx[25:0]), wordof(fxe) };
                    pa = pass ? p0_st : pcur;
                    pb = pass ? pcur  : 78'd0;
                    v  = !cempty && (pa[77] || pb[77]);
                    cst_d <= { v, e_color[4:0], e_offs[11:0], e_zoom, flip, pa, pb };
                    cst_we <= 1; wa <= col;
                    if( v ) begin
                        rom_addr <= pa[77] ? pa[33:17] : pb[33:17]; rom_cs_o <= 1; rst_st <= R_PCF;
                    end else begin
                        cc_d <= 100'd0; cc_we <= 1;
                        if( col==9'd383 ) begin pc <= 0; rst_st <= R_IDLE; end
                        else begin col <= col + 9'd1; rst_st <= R_E0; end
                    end
                end
            end
        end
        R_PCF: if( rom_ok ) begin
            rom_cs_o <= 0;
            cc_d <= { 1'b1, rom_addr, rom_data, 50'd0 }; cc_we <= 1; wa <= col;
            if( col==9'd383 ) begin pc <= 0; rst_st <= R_IDLE; end
            else begin col <= col + 9'd1; rst_st <= R_E0; end
        end
        R_PIX: begin
            if( k >= dst_len[23:0] ) rst_st <= R_IDLE;
            else if( !c_valid || c_waddr != waddr_now ) begin
                if( idx_m[19:10]==10'd0 && rc_v[idx_m[9:3]] ) begin
                    rc_ra <= idx_m[9:3]; rst_st <= R_RC1;
                end else begin
                    rom_addr <= waddr_now; rom_cs_o <= 1; rst_st <= R_WAIT;
                    rc_wi <= idx_m[9:3]; rc_ok <= idx_m[19:10]==10'd0;
                end
            end else begin
                if( pen_now!=4'd0 && dpos >= $signed({15'd0,VX0}) && dpos <= $signed({15'd0,VX1}) ) begin
                    lb_wa <= dpos[8:0] - VX0; lb_wd <= {e_color[4:0], pen_now}; lb_we <= 1;
                end
                src_fx <= src_fx + src_fdx;
                k <= k + 24'd1;
            end
        end
        R_WAIT: if( rom_ok ) begin
            c_data <= rom_data; c_waddr <= rom_addr; c_valid <= 1; rom_cs_o <= 0; rst_st <= R_PIX;
            if( rc_ok ) rc_v[rc_wi] <= 1'b1;
        end
        R_RC1: rst_st <= R_RC2;
        R_RC2: begin c_data <= rc_q; c_waddr <= waddr_now; c_valid <= 1; rst_st <= R_PIX; end

        R_S0: rst_st <= R_S1;
        R_S1: begin
            ce <= cst_q;
            { s_cv, s_ctag, s_cw, s_bv, s_btag, s_bw } <= cc_q;
            pass <= 0; cdirty <= 0; pf_ok <= 0;
            if( cst_q[CSTW-1] ) rst_st <= R_S2;
            else if( col==9'd383 ) rst_st <= R_SDN;
            else begin col <= col + 9'd1; rst_st <= R_S1; end
        end
        R_S2: begin
            if( cp_hit ) begin
                sfx    <= ce_flip ? cp_fx - cp_step : cp_fx + cp_step;
                rst_st <= R_S3;
            end else if( !pass ) pass <= 1;
            else rst_st <= R_PF;
        end

        R_S3: begin
            if( s_cv && s_ctag == s_wa ) begin
                if( s_pen!=4'd0 ) begin lb_wa <= col; lb_wd <= {ce_col, s_pen}; lb_we <= 1; end
                if( !pass ) begin pass <= 1; rst_st <= R_S2; end
                else rst_st <= R_PF;
            end else if( s_wa[0] ? !q_full1 : !q_full0 ) begin
                if( s_wa[0] ) begin q1[qw1] <= {col, s_nib[2:0], s_wa, ce_col}; qw1 <= qw1 + 4'd1; enq1 = 1'b1; end
                else          begin q0[qw0] <= {col, s_nib[2:0], s_wa, ce_col}; qw0 <= qw0 + 4'd1; enq0 = 1'b1; end
                if( !pass ) begin pass <= 1; rst_st <= R_S2; end
                else rst_st <= R_PF;
            end
        end
        R_PF: begin
            if( col==9'd383 ) rst_st <= R_SDN;
            else begin col <= col + 9'd1; rst_st <= R_S1; end
        end
        R_SDN: if( swp_idle ) rst_st <= R_IDLE;
        default: rst_st <= R_IDLE;
        endcase

        begin : motores
            reg cap0, cap1;
            cap0 = e_bsy0 && rom0_ok && !e_pl0 && !e_pc0;
            cap1 = e_bsy1 && rom1_ok && !e_pl1 && !e_pc1;
            if( cap0 ) begin r_en0 <= e_en0; e_d0 <= rom0_data; e_pl0 <= 1; e_pc0 <= 1; e_bsy0 <= 0; end
            if( (!e_bsy0 || cap0) && q_n0!=5'd0 ) begin e_en0 <= q0[qr0]; qr0 <= qr0 + 4'd1; deq0 = 1'b1; e_bsy0 <= 1; end
            if( cap1 ) begin r_en1 <= e_en1; e_d1 <= rom1_data; e_pl1 <= 1; e_pc1 <= 1; e_bsy1 <= 0; end
            if( (!e_bsy1 || cap1) && q_n1!=5'd0 ) begin e_en1 <= q1[qr1]; qr1 <= qr1 + 4'd1; deq1 = 1'b1; e_bsy1 <= 1; end
        end
        q_n0 <= q_n0 + {4'd0,enq0} - {4'd0,deq0};
        q_n1 <= q_n1 + {4'd0,enq1} - {4'd0,deq1};

        if( e_pl0 && !pl_wr ) begin
            if( e_pen0!=4'd0 ) begin lb_wa <= r_en0[33:25]; lb_wd <= {r_en0[4:0], e_pen0}; lb_we <= 1; end
            e_pl0 <= 0;
        end else if( e_pl1 && !pl_wr ) begin
            if( e_pen1!=4'd0 ) begin lb_wa <= r_en1[33:25]; lb_wd <= {r_en1[4:0], e_pen1}; lb_we <= 1; end
            e_pl1 <= 0;
        end

        if( e_pc0 ) begin cc_d <= {1'b1, r_en0[21:5], e_d0, 50'd0}; cc_we <= 1; wa <= r_en0[33:25]; e_pc0 <= 0; end
        else if( e_pc1 ) begin cc_d <= {1'b1, r_en1[21:5], e_d1, 50'd0}; cc_we <= 1; wa <= r_en1[33:25]; e_pc1 <= 0; end
    end
end

`ifdef VERILATOR

integer sw_cyc=0, sw_max=0, sw_lost=0;
integer n_sw=0, n_pf=0, c_sw=0, c_pf=0;
reg [4:0] st_l=0;
always @(posedge clk) if( !rst ) begin
    st_l <= rst_st;
    if( rst_st==R_SW  ) begin c_sw <= c_sw + 1; if( st_l!=R_SW  ) n_sw <= n_sw + 1; end
    if( rst_st==R_PFW ) begin c_pf <= c_pf + 1; if( st_l!=R_PFW ) n_pf <= n_pf + 1; end
    if( prev_lhbl && !lhbl && swp && rline>=9'h1E8 && rline[8] )
        $display("K053250 SWAP fila %03x: %0d ciclos, oblig %0d (%0d clk), precarga %0d (%0d clk)", rline, sw_cyc, n_sw, c_sw, n_pf, c_pf);
    if( prev_lhbl && !lhbl ) begin n_sw<=0; n_pf<=0; c_sw<=0; c_pf<=0; end
    if( rst_st>=R_S0 ) sw_cyc <= sw_cyc + 1;
    if( prev_lhbl && !lhbl ) begin
        if( sw_cyc > sw_max ) sw_max <= sw_cyc;
        sw_cyc <= 0;
        if( swp && vrender1[8] && rst_st!=R_IDLE ) begin sw_lost <= sw_lost + 1;
            $display("K053250 SWAP: fila %03x perdida (render de %03x en estado %0d, col %0d)", vrender1, rline, rst_st, col); end
        if( swp && vrender1==PC_LINE )
            $display("K053250 SWAP: max %0d ciclos/fila, %0d filas perdidas", sw_max, sw_lost);

        if( !swp && rst_st!=R_IDLE )
            $display("K053250: linea %03x perdida (render de %03x en estado %0d, k=%0d de dst_len=%0d, %0d ciclos)",
                     vrender1, rline, rst_st, k, dst_len, lcyc);
    end
end
`endif

reg  [8:0] rd_x;
always @(posedge clk) if( pxl_cen ) rd_x <= hdump;
wire clr0 = dbank==1'b0 && pxl_cen, clr1 = dbank==1'b1 && pxl_cen;
jtframe_rpwp_ram #(.DW(9),.AW(9)) u_out0(.clk(clk), .rd_addr(hdump), .dout(lb0_q),
    .wr_addr( rbank==1'b0 ? lb_wa : rd_x ), .din( rbank==1'b0 ? lb_wd : 9'd0 ), .we( rbank==1'b0 ? lb_we : clr0 ));
jtframe_rpwp_ram #(.DW(9),.AW(9)) u_out1(.clk(clk), .rd_addr(hdump), .dout(lb1_q),
    .wr_addr( rbank==1'b1 ? lb_wa : rd_x ), .din( rbank==1'b1 ? lb_wd : 9'd0 ), .we( rbank==1'b1 ? lb_we : clr1 ));
assign pxl = dbank ? lb1_q : lb0_q;

endmodule
