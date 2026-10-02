module jthotchase_obj(
    input             rst,
    input             clk,
    input      [ 8:0] vdump,
    input             start,
    input      [ 8:0] v,
    output reg        busy,

    output reg [10:0] ram_addr,
    input      [15:0] ram_q,

    output reg [21:2] rom_addr,
    output reg        rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    output reg [ 8:0] lb_addr,
    output reg [13:0] lb_din,
    output reg        lb_we,
    output reg        lb_shwe,
    input             en
);

parameter [8:0] PRE_LINE = 9'd240;
parameter       SWAP32   = 0;

reg  [10:0] tb_waddr, tb_raddr;
reg  [31:0] tb_din;
reg         tb_we;
wire [31:0] tb_q;
jtframe_dual_ram #(.DW(32),.AW(11)) u_tab(
    .clk0(clk), .data0(tb_din), .addr0(tb_waddr), .we0(tb_we), .q0(),
    .clk1(clk), .data1(32'd0),  .addr1(tb_raddr), .we1(1'b0),  .q1(tb_q) );
reg  [ 7:0] so_waddr, so_raddr, idx_din, key_din;
reg         so_we;
wire [ 7:0] idx_q, key_q;
jtframe_dual_ram #(.DW(8),.AW(8)) u_idx(
    .clk0(clk), .data0(idx_din), .addr0(so_waddr), .we0(so_we), .q0(),
    .clk1(clk), .data1(8'd0),    .addr1(so_raddr), .we1(1'b0),  .q1(idx_q) );
jtframe_dual_ram #(.DW(8),.AW(8)) u_key(
    .clk0(clk), .data0(key_din), .addr0(so_waddr), .we0(so_we), .q0(),
    .clk1(clk), .data1(8'd0),    .addr1(so_raddr), .we1(1'b0),  .q1(key_q) );

reg  [31:0] dv_n, dv_nin, dv_q;
reg  [15:0] dv_d;
reg  [16:0] dv_r;
reg  [ 5:0] dv_cnt;
reg         dv_go;
wire        dv_busy = dv_cnt != 0;
wire [16:0] dv_sh  = { dv_r[15:0], dv_n[31] };
wire [16:0] dv_try = dv_sh - { 1'b0, dv_d };
always @(posedge clk) begin
    if( dv_go ) begin
        dv_cnt <= 6'd32; dv_r <= 0; dv_q <= 0; dv_n <= dv_nin;
    end else if( dv_busy ) begin
        dv_cnt <= dv_cnt - 1'd1;
        dv_n   <= { dv_n[30:0], 1'b0 };
        if( !dv_try[16] ) begin dv_r <= dv_try; dv_q <= { dv_q[30:0], 1'b1 }; end
        else begin dv_r <= dv_sh; dv_q <= { dv_q[30:0], 1'b0 }; end
    end
end

reg  [ 5:0] st;
reg  [ 2:0] wk;
reg  [ 8:0] n, cnt;
reg  [15:0] w0, w1, w2, w3, w4, w7;
reg  [ 1:0] wt;
reg         frame_done, vpre_l;

reg  signed [11:0] sy0, total_h, sx0;
reg  [ 7:0] tw8;
reg  signed [25:0] gfx;
reg  [15:0] th;
reg  signed [15:0] total_w;
reg         flipx, flipy, shadow;
reg  signed [11:0] x1, x2, y1, y2;
reg  [10:0] xc0, yc0;
reg  [31:0] fdy, f0y, fdx, f0x;
reg  [ 2:0] tw_i;

reg  [ 7:0] sj, si, src_idx, low_val, hi_idx, low_pos, key_j, ij_idx, low_key;

reg  [ 8:0] k;
reg  [ 7:0] m;
reg  [31:0] p_f0y, p_fdy, p_f0x, p_fdx, p_w4, p_w5, p_w6;
reg  [ 2:0] ldw;
reg  [31:0] fpx, frow, lastx;
reg  [22:0] base;
reg  [ 9:0] dst;
reg  [ 8:0] left;
reg  [18:0] blk;
reg         blk_ok;
reg  [63:0] blk_d;
reg  [ 3:0] fwait;

localparam S_IDLE=0, S_RD=1, S_CHK=2, S_TH=3, S_THW=4, S_BND=5, S_CLIP=6, S_FDYW=7, S_FDXW=8, S_WTAB=9,
           S_WNEXT=10, S_SORT=11, S_SJW=12, S_SIW=13, S_SWAP0=14, S_SWAP=15, S_SWAP1=16, S_SWAP2=17,
           S_SWAP3=18, S_LREADY=19,
           L_IDX=20, L_IDXW=21, L_W6W=22, L_WRDW=23, L_ROW=24, L_ROW1=25, L_PIX=26, L_SETTLE=27,
           L_FETCHA=28, L_FETCHB=29, L_NEXT=30, L_END=31, L_ROW2=32;

reg         f_req, f_pf, f_busy, f_done, f_pf_l, nxt_ok;
reg  [18:0] f_blk, f_blkl, nxt_blk, last_blk;
reg  [63:0] f_d, nxt_d;
reg  [ 1:0] f_st;
reg  [ 3:0] f_w;
always @(posedge clk) begin
    f_done <= 0;
    if( rst ) begin
        f_st <= 0; f_busy <= 0; rom_cs <= 0;
    end else case( f_st )
        0: if( f_req ) begin
            f_busy <= 1; f_blkl <= f_blk; f_pf_l <= f_pf;
            rom_addr <= { f_blk, 1'b0 }; rom_cs <= 1; f_w <= 0; f_st <= 1;
        end
        1: begin
            if( f_w!=4'hf ) f_w <= f_w + 1'd1;
            if( f_w>1 && rom_ok ) begin f_d[31:0] <= rom32; rom_addr[2] <= 1; f_w <= 0; f_st <= 2; end
        end
        2: begin
            if( f_w!=4'hf ) f_w <= f_w + 1'd1;
            if( f_w>1 && rom_ok ) begin f_d[63:32] <= rom32; rom_cs <= 0; f_busy <= 0; f_done <= 1; f_st <= 0; end
        end
        default: f_st <= 0;
    endcase
end

wire [31:0] rom32 = SWAP32 ? { rom_data[15:0], rom_data[31:16] } : rom_data;
wire [10:0] tw     = { tw8, 3'd0 };
wire [19:0] twzl   = tw * w4[7:0];
wire signed [15:0] tw_w = $signed({5'd0, tw}) - $signed({3'd0, twzl[19:7]});
wire [31:0] tw_th  = tw * th;
wire [ 8:0] nrow   = p_w6[12] ? (p_w6[31:23] - v) : (v - p_w6[31:23]);
wire signed [24:0] rowoff = $signed(frow[31:20]) * $signed({1'b0, p_w4[7:0], 3'd0});
wire [22:0] pix_i  = base + { 11'd0, fpx[31:20] };
wire [ 3:0] pv;

function [3:0] blk_pix(input [63:0] d, input [3:0] q);
    reg [7:0] by;
    begin
        case( q[3:1] )

            0: by = d[15: 8]; 1: by = d[ 7: 0]; 2: by = d[31:24]; 3: by = d[23:16];
            4: by = d[47:40]; 5: by = d[39:32]; 6: by = d[63:56]; 7: by = d[55:48];
        endcase
        blk_pix = q[0] ? by[3:0] : by[7:4];
    end
endfunction
assign pv = blk_pix( blk_d, pix_i[3:0] );

wire shadow_spr = p_w5[9];
wire [11:0] pen = { p_w5[8:1], 4'd0 } + { 8'd0, pv };

always @(posedge clk) begin
    tb_we <= 0; so_we <= 0; lb_we <= 0; lb_shwe <= 0; dv_go <= 0;
    vpre_l <= vdump==PRE_LINE;
    if( rst ) begin
        st <= S_IDLE; busy <= 0; frame_done <= 0; cnt <= 0; blk_ok <= 0; nxt_ok <= 0; f_req <= 0;
    end else begin
      f_req <= 0;

      if( f_done && f_pf_l ) begin nxt_d <= f_d; nxt_blk <= f_blkl; nxt_ok <= 1; end
      if( (st==L_PIX || st==L_SETTLE) && blk_ok && !f_busy && !f_req && !(nxt_ok && nxt_blk==blk+1'd1) && left>9'd1 ) begin
          f_req <= 1; f_pf <= 1; f_blk <= blk + 1'd1;
      end
      case( st )

        S_IDLE: begin
            if( vdump==PRE_LINE && !vpre_l ) begin
                n <= 0; cnt <= 0; wk <= 0; ram_addr <= 0; wt <= 0; st <= S_RD; frame_done <= 0;
            end else if( start ) begin
                busy <= 1; k <= 0; st <= frame_done ? L_IDX : L_END;
            end
        end

        S_RD: begin
            wt <= wt + 1'd1;
            if( wt==2 ) begin
                wt <= 0;
                case( wk )
                    0: w0 <= ram_q; 1: w1 <= ram_q; 2: w2 <= ram_q; 3: w3 <= ram_q; 4: w4 <= ram_q;
                    7: w7 <= ram_q; default:;
                endcase
                if( wk==0 && ram_q==16'hffff ) st <= S_LREADY;
                else if( wk==7 ) st <= S_CHK;
                else begin
                    wk <= wk==4 ? 3'd7 : wk + 1'd1;
                    ram_addr <= { n[7:0], wk==4 ? 3'd7 : wk + 3'd1 };
                end
            end
        end
        S_CHK: begin
            sy0     <= { 4'd0, w0[7:0] };
            total_h <= $signed({4'd0, w0[15:8]}) - $signed({4'd0, w0[7:0]});
            sx0     <= { 3'd0, w1[8:0] };
            tw8     <= w2[7:0];
            shadow  <= w2[14];
            flipx   <= w3[15];
            flipy   <= w1[9];

            gfx     <= $signed({ 5'd0, w1[15:10] >= 6'd48 ? w1[15:10] - 6'd48 : w1[15:10], 15'd0 }) + $signed({ 11'd0, w3[14:0] });
            st <= S_TH;
        end
        S_TH: begin
            if( total_h < 1 || w1[15:10]==6'h3f || tw8==0 || w4[15:8] >= 8'h80 ) st <= S_WNEXT;
            else begin
                if( flipx ) gfx <= gfx + 26'sd1 - $signed({18'd0, tw8});
                dv_nin <= { 17'd0, total_h[7:0], 7'd0 };
                dv_d <= { 8'd0, 8'h80 - w4[15:8] };
                dv_go <= 1; st <= S_THW;
            end
        end
        S_THW: if( !dv_go && !dv_busy ) begin
            th      <= dv_q[15:0];
            gfx     <= gfx <<< 3;
            total_w <= tw_w;
            st <= S_BND;
        end
        S_BND: begin
            if( gfx + $signed({1'b0,tw_th[24:0]}) - 26'sd1 >= 26'sh600000 ) st <= S_WNEXT;
            else st <= S_CLIP;
        end
        S_CLIP: begin : clip
            reg signed [11:0] x, y, a1, a2, b1, b2;
            reg [10:0] xc, yc;
            reg vis;
            x = sx0 - 12'sd192 + 12'sd8;
            y = sy0 + 12'sd8;
            xc = 0; yc = 0; vis = 1;
            if( flipx ) begin
                a2 = x; a1 = x + total_w[11:0];
                if( a2 < 8 ) a2 = 8;
                if( a1 > 327 ) begin xc = a1 - 12'sd327; a1 = 327; end
                if( a2 >= a1 ) vis = 0;
                a1 = a1 - 12'sd1; a2 = a2 - 12'sd1;
            end else begin
                a1 = x; a2 = x + total_w[11:0];
                if( a1 < 8 ) begin xc = 12'sd8 - a1; a1 = 8; end
                if( a2 > 327 ) a2 = 327;
                if( a1 >= a2 ) vis = 0;
            end
            if( flipy ) begin
                b2 = y; b1 = y + total_h + 12'sd1;
                if( b2 < 8 ) b2 = 8;
                if( b1 > 231 ) begin yc = 11'd231; b1 = 231; end
                if( b2 >= b1 ) vis = 0;
                b1 = b1 - 12'sd1; b2 = b2 - 12'sd1;
            end else begin
                b1 = y; b2 = y + total_h + 12'sd1;
                if( b1 < 8 ) begin yc = 12'sd8 - b1; b1 = 8; end
                if( b2 > 231 ) b2 = 231;
                if( b1 >= b2 ) vis = 0;
            end
            if( a1 > 8 ) begin
                if( flipx ) begin a1 = a1 + 12'sd1; a2 = a2 + 12'sd1; end
                else        begin a1 = a1 - 12'sd1; a2 = a2 - 12'sd1; end
            end
            x1 <= a1; x2 <= a2; y1 <= b1; y2 <= b2; xc0 <= xc; yc0 <= yc;
            if( !vis || total_w <= 0 ) st <= S_WNEXT;
            else begin
                dv_nin <= { th[11:0], 20'd0 };
                dv_d <= { 4'd0, total_h + 12'sd1 };
                dv_go <= 1; st <= S_FDYW;
            end
        end
        S_FDYW: if( !dv_go && !dv_busy ) begin
            fdy  <= dv_q;
            f0y  <= dv_q * yc0 + 32'h80000;
            dv_nin <= { 1'd0, tw, 20'd0 };
            dv_d <= total_w[15:0];
            dv_go <= 1; st <= S_FDXW;
        end
        S_FDXW: if( !dv_go && !dv_busy ) begin
            fdx <= dv_q;
            f0x <= dv_q * xc0;
            tw_i <= 0; st <= S_WTAB;
        end
        S_WTAB: begin : wtab
            reg signed [11:0] len;
            len = flipy ? 12'sd0 : 12'sd0;
            len = flipx ? (x1 - x2) : (x2 - x1);
            tb_we    <= 1;
            tb_waddr <= { cnt[7:0], tw_i };
            case( tw_i )
                0: tb_din <= f0y;
                1: tb_din <= fdy;
                2: tb_din <= f0x;
                3: tb_din <= fdx;
                4: tb_din <= { gfx[22:0], 1'b0, tw8 };
                5: tb_din <= { x1[9:0], len[8:0], flipx, 2'd0, shadow, w7[7:0], 1'b0 };
                6: tb_din <= { y1[8:0], y2[8:0], 1'b0, flipy, 12'd0 };
                default: tb_din <= 0;
            endcase
            if( tw_i==6 ) begin
                so_we <= 1; so_waddr <= cnt[7:0]; idx_din <= cnt[7:0]; key_din <= w7[15:8];
                cnt <= cnt + 1'd1; st <= S_WNEXT;
            end else tw_i <= tw_i + 1'd1;
        end
        S_WNEXT: begin
            if( n==9'd255 ) st <= S_LREADY;
            else begin n <= n + 1'd1; wk <= 0; ram_addr <= { n[7:0] + 8'd1, 3'd0 }; wt <= 0; st <= S_RD; end
        end

        S_SORT: begin
            sj <= 0;
            if( cnt < 2 ) st <= S_LREADY;
            else begin so_raddr <= 0; wt <= 0; st <= S_SJW; end
        end
        S_SJW: begin
            wt <= wt + 1'd1;
            if( wt==2 ) begin
                src_idx <= idx_q; low_val <= key_q; hi_idx <= idx_q; key_j <= key_q; low_pos <= sj;
                si <= sj + 1'd1; so_raddr <= sj + 1'd1; wt <= 0; st <= S_SIW;
            end
        end
        S_SIW: begin
            wt <= wt + 1'd1;
            if( wt==2 ) begin
                wt <= 0;
                if( low_val > key_q ) begin low_val <= key_q; low_pos <= si; end
                else if( low_val == key_q && hi_idx <= idx_q ) begin hi_idx <= idx_q; low_pos <= si; end
                if( si == cnt[7:0]-8'd1 ) st <= S_SWAP0;
                else begin si <= si + 1'd1; so_raddr <= si + 1'd1; end
            end
        end
        S_SWAP0: begin so_raddr <= low_pos; wt <= 0; st <= S_SWAP; end
        S_SWAP: begin
            wt <= wt + 1'd1;
            if( wt==2 ) begin ij_idx <= idx_q; low_key <= key_q; st <= S_SWAP1; end
        end
        S_SWAP1: begin so_we <= 1; so_waddr <= low_pos; idx_din <= src_idx; key_din <= key_j; st <= S_SWAP2; end
        S_SWAP2: begin so_we <= 1; so_waddr <= sj;      idx_din <= ij_idx;  key_din <= low_key; st <= S_SWAP3; end
        S_SWAP3: begin
            if( sj == cnt[7:0]-8'd2 ) st <= S_LREADY;
            else begin sj <= sj + 1'd1; so_raddr <= sj + 1'd1; wt <= 0; st <= S_SJW; end
        end
        S_LREADY: begin frame_done <= 1; st <= S_IDLE; end

        L_IDX: begin
            if( k >= cnt ) st <= L_END;
            else begin m <= k[7:0]; tb_raddr <= { k[7:0], 3'd6 }; ldw <= 0; st <= L_W6W; end
        end
        L_IDXW: begin
            wt <= wt + 1'd1;
            if( wt==2 ) begin m <= idx_q; tb_raddr <= { idx_q, 3'd6 }; ldw <= 0; st <= L_W6W; end
        end

        L_W6W: begin
            ldw <= ldw + 1'd1;
            if( ldw < 3'd6 ) tb_raddr <= { m, ldw };

            case( ldw )
                1: p_w6  <= tb_q;
                2: p_f0y <= tb_q;
                3: p_fdy <= tb_q;
                4: p_f0x <= tb_q;
                5: p_fdx <= tb_q;
                6: p_w4  <= tb_q;
                7: p_w5  <= tb_q;
                default:;
            endcase
            if( ldw==3'd7 ) st <= L_WRDW;

            if( ldw==3'd2 && !(p_w6[12] ? (v <= p_w6[31:23] && v > p_w6[22:14]) : (v >= p_w6[31:23] && v < p_w6[22:14])) )
                st <= L_NEXT;
        end
        L_WRDW: begin

            if( p_w6[12] ? (v <= p_w6[31:23] && v > p_w6[22:14]) : (v >= p_w6[31:23] && v < p_w6[22:14]) )
                st <= L_ROW;
            else st <= L_NEXT;
        end
        L_ROW: begin frow <= p_f0y + p_fdy * nrow; st <= L_ROW1; end
        L_ROW1: begin
            base  <= p_w4[31:9] + rowoff[22:0];
            lastx <= p_f0x + p_fdx * ({1'b0,p_w5[21:13]} - 10'd1);
            fpx   <= p_f0x;
            dst   <= p_w5[31:22];
            left  <= p_w5[21:13];
            fwait <= 0;
            st    <= L_ROW2;
        end
        L_ROW2: begin last_blk <= (base + { 10'd0, lastx[31:20] }) >> 4; st <= L_PIX; end
        L_SETTLE: begin fwait <= fwait + 1'd1; if( fwait==2 ) st <= L_PIX; end
        L_PIX: begin
            if( left==0 ) st <= L_NEXT;
            else if( !blk_ok || pix_i[22:4] != blk ) begin
                if( nxt_ok && pix_i[22:4]==nxt_blk ) begin
                    blk <= nxt_blk; blk_d <= nxt_d; blk_ok <= 1; nxt_ok <= 0;
                end else begin
                    blk <= pix_i[22:4]; blk_ok <= 0; nxt_ok <= 0; st <= L_FETCHA;
                end
            end else begin
                lb_addr <= dst[8:0];
                if( pv!=0 && en ) begin
                    lb_shwe <= 1;
                    if( shadow_spr && pv==4'ha )
                        lb_din <= { 13'd0, 1'b1 };
                    else begin
                        lb_we  <= 1;
                        lb_din <= { 1'b1, pen, 1'b0 };
                    end
                end
                fpx  <= fpx + p_fdx;
                dst  <= p_w5[12] ? dst - 1'd1 : dst + 1'd1;
                left <= left - 1'd1;
            end
        end
        L_FETCHA: begin
            if( nxt_ok && nxt_blk==blk ) begin
                blk_d <= nxt_d; blk_ok <= 1; nxt_ok <= 0; st <= L_PIX;
            end else if( !f_busy && !f_req && !f_done ) begin f_req <= 1; f_pf <= 0; f_blk <= blk; st <= L_FETCHB; end
        end
        L_FETCHB: begin
            if( f_done && !f_pf_l ) begin blk_d <= f_d; blk_ok <= 1; st <= L_PIX; end
        end
        L_NEXT: begin k <= k + 1'd1; st <= L_IDX; end
        L_END: begin busy <= 0; st <= S_IDLE; end
        default: st <= S_IDLE;
      endcase
    end
end

`ifdef SIMULATION

integer nblk=0, lat_sum=0, lat_max=0, lat=0, lin=0, lin_max=0, ndbg=0;
always @(posedge clk) if( start && busy && ndbg<6 ) begin ndbg<=ndbg+1;
    $display("OBJ atascado: st=%0d f_st=%0d f_busy=%0d f_req=%0d f_done=%0d rom_cs=%0d rom_ok=%0d blk=%05X nxt=%0d/%05X left=%0d", st, f_st, f_busy, f_req, f_done, rom_cs, rom_ok, blk, nxt_ok, nxt_blk, left); end
always @(posedge clk) begin
    if( f_st!=0 ) lat <= lat + 1;
    if( f_st==2 && f_w>1 && rom_ok ) begin
        nblk <= nblk + 1; lat_sum <= lat_sum + lat + 1; if( lat+1 > lat_max ) lat_max <= lat+1; lat <= 0;
    end
    if( busy ) lin <= lin + 1; else lin <= 0;
    if( busy && lin+1 > lin_max ) lin_max <= lin+1;
    if( st==S_IDLE && vdump==PRE_LINE && !vpre_l ) begin
        if( nblk>0 ) $display("OBJSTAT lecturas=%0d lat_media=%0d lat_max=%0d peor_linea=%0d clk (presupuesto 3200)",
            nblk, lat_sum/nblk, lat_max, lin_max);
        nblk <= 0; lat_sum <= 0; lat_max <= 0; lin_max <= 0;
    end
end
`endif
endmodule
