module k054539 #(parameter VOLSHIFT=0, parameter EFXGAIN=32) (
    input               rst,
    input               clk,
    input               cen,
    output              timeout,
    output reg          nmi_toggle,

    input      [ 9:0]   addr,
    input               we,
    input               rd,
    input               cs,
    input      [ 7:0]   din,
    output     [ 7:0]   dout,

    output reg          rom_cs,
    output reg [23:0]   rom_addr,
    input      [ 7:0]   rom_data,
    input               rom_ok,

    output reg signed [15:0] left,
    output reg signed [15:0] right,

    input      [ 7:0]   debug_bus,
    output     [ 7:0]   st_dout
);

reg  [7:0] regs [0:1023];
integer    gi;
initial for (gi=0; gi<1024; gi=gi+1) regs[gi] = 8'd0;

always @(posedge clk) begin
    if (cs && we) regs[addr] <= din;
end

reg  [7:0] active;

localparam [9:0] R_22C = 10'h22C,
                 R_22D = 10'h22D,
                 R_22E = 10'h22E,
                 R_22F = 10'h22F;

reg  [7:0]  k39ram [0:16383];
reg  [13:0] cur_ptr;
reg  [7:0]  ram_q;

reg  acc_l, inc_pend;
wire acc   = cs & (we | rd);
wire acc_1 = acc & ~acc_l;
wire acc_0 = ~acc & acc_l;

always @(posedge clk) begin
    acc_l <= acc;
    ram_q <= k39ram[cur_ptr];
    if (rst) begin
        cur_ptr  <= 0;
        inc_pend <= 0;
    end else begin
        if (acc_1) begin
            if (we && addr==R_22E) begin
                cur_ptr  <= 0;
                inc_pend <= 0;
            end else if (addr==R_22D) begin

                if (we) begin
                    if (regs[R_22E]==8'h80) k39ram[cur_ptr] <= din;
                    inc_pend <= 1;
                end else if (rd && regs[R_22F][4]) begin
                    inc_pend <= 1;
                end
            end
        end

        if (acc_0 && inc_pend) begin

            cur_ptr  <= cur_ptr + 14'd1;
            inc_pend <= 0;
        end
    end
end

assign dout    = addr==R_22D ? (regs[R_22F][4] ? ram_q : 8'd0) :
                 addr==R_22C ? active                          : regs[addr];
assign timeout = 1'b0;

reg [15:0] voltab [0:255];
reg [16:0] pantab [0:14];
initial begin
    $readmemh("voltab.hex", voltab);
    $readmemh("pantab.hex", pantab);
end

reg [23:0] cpos   [0:7];
reg [15:0] cpfrac [0:7];
reg signed [15:0] cval  [0:7];
reg signed [15:0] cpval [0:7];

reg  [7:0] restart;

localparam [3:0]
    S_IDLE = 4'd0, S_LOAD = 4'd1, S_ACC = 4'd2,
    S_R8   = 4'd3, S_R16L = 4'd4, S_R16H = 4'd5, S_RD = 4'd6,
    S_MIX  = 4'd7, S_NEXT = 4'd8, S_DONE = 4'd9,
    S_REVRD= 4'd10, S_RVWR = 4'd11;

reg [3:0]  state;
reg [8:0]  sample_cnt;
reg [2:0]  ch;
reg [15:0] ovr_cnt;

reg [24:0] w_pos;
reg [31:0] w_pfrac;
reg signed [15:0] w_val, w_pval;
reg [23:0] w_loop;
reg [7:0]  w_lo;
reg [7:0]  w_vol;
reg [3:0]  w_pan;
reg [1:0]  w_type;
reg        w_loopen;
reg        w_rev;
reg        w_looped;

reg signed [39:0] accL, accR;

reg  signed [15:0] rram [0:8191];
initial $readmemh("rram_zero.hex", rram);
reg  [12:0] reverb_pos;
reg  [12:0] rr_addr;
reg         rr_we;
reg  signed [15:0] rr_din;
reg  signed [15:0] rr_dout;

wire [12:0] rd_addr = (state==S_MIX) ? widx : reverb_pos;
always @(posedge clk) begin
    rr_dout <= rram[rd_addr];
    if (rr_we) rram[rr_addr] <= rr_din;
end

wire [16:0] vt   = {1'b0, voltab[w_vol]};
wire [16:0] pl   = pantab[w_pan];
wire [16:0] pr   = pantab[4'd14 - w_pan];
wire [33:0] lfull= vt * pl;
wire [33:0] rfull= vt * pr;
wire [16:0] lvol = lful_clamp(lfull[32:16]);
wire [16:0] rvol = lful_clamp(rfull[32:16]);
function [16:0] lful_clamp(input [16:0] v);
    lful_clamp = (v > 17'h1CCCC) ? 17'h1CCCC : v;
endfunction

wire efx_ch = (ch >= 3'd4) && (EFXGAIN != 32);

wire [23:0] lvol_x = lvol * EFXGAIN[6:0];
wire [23:0] rvol_x = rvol * EFXGAIN[6:0];
wire [18:0] lvol_g = efx_ch ? lvol_x[23:5] : {2'b0, lvol};
wire [18:0] rvol_g = efx_ch ? rvol_x[23:5] : {2'b0, rvol};

reg [18:0] lvol_gq, rvol_gq;
always @(posedge clk) begin
    lvol_gq <= lvol_g;
    rvol_gq <= rvol_g;
end

wire signed [35:0] cprodL = $signed(w_val) * $signed({1'b0, lvol_gq});
wire signed [35:0] cprodR = $signed(w_val) * $signed({1'b0, rvol_gq});
wire signed [39:0] contribL = {{4{cprodL[35]}}, cprodL};
wire signed [39:0] contribR = {{4{cprodR[35]}}, cprodR};

wire [12:0] rrd  = {regs[b1+10'd7], regs[b1+10'd6]} >> 3;
wire [13:0] rd14 = ({1'b0,rrd} + {1'b0,reverb_pos}) & 14'h3fff;
wire [14:0] wsum = {1'b0,rd14} + {2'b0,reverb_pos};
wire [12:0] widx = wsum[12:0];

wire [7:0]  rvvol    = regs[b1+10'd4];
wire [7:0]  rb_idx_l = {rvvol[3:0], 3'b111};
wire [7:0]  rb_idx_r = {rvvol[7:4], 3'b111};
wire [7:0]  rb_idx   = (rb_idx_l < rb_idx_r) ? rb_idx_l : rb_idx_r;
wire [15:0] rbvol = {1'b0, voltab[rb_idx][15:1]};

wire [22:0] rbvol_x = rbvol * EFXGAIN[6:0];
wire [17:0] rbvol_g = efx_ch ? rbvol_x[22:5] : {2'b0, rbvol};
wire signed [34:0] rprod = $signed(w_val) * $signed({1'b0, rbvol_g});

wire signed [15:0] rev_contrib = rprod[31:16];

wire [9:0] b1 = {2'b0, ch, 5'b0};
wire [9:0] b2 = 10'h200 + {6'b0, ch, 1'b0};
wire [23:0] delta_now = {regs[b1+10'd2], regs[b1+10'd1], regs[b1+10'd0]};
wire [1:0]  type_now  = (regs[b2] & 8'h0c)==8'h00 ? 2'd0 :
                        (regs[b2] & 8'h0c)==8'h04 ? 2'd1 : 2'd2;

wire        type_bad  = (regs[b2] & 8'h0c)==8'h0c;

wire        rev_now   = regs[b2][5];

wire [31:0] dsign     = rev_now ? (32'd0 - {8'b0, delta_now}) : {8'b0, delta_now};

function signed [15:0] dpcm_step(input [3:0] n);
    case (n)
        4'd0:  dpcm_step =  16'sd0;      4'd1:  dpcm_step =  16'sd256;
        4'd2:  dpcm_step =  16'sd512;    4'd3:  dpcm_step =  16'sd1024;
        4'd4:  dpcm_step =  16'sd2048;   4'd5:  dpcm_step =  16'sd4096;
        4'd6:  dpcm_step =  16'sd8192;   4'd7:  dpcm_step =  16'sd16384;
        4'd8:  dpcm_step =  16'sd0;      4'd9:  dpcm_step = -16'sd16384;
        4'd10: dpcm_step = -16'sd8192;   4'd11: dpcm_step = -16'sd4096;
        4'd12: dpcm_step = -16'sd2048;   4'd13: dpcm_step = -16'sd1024;
        4'd14: dpcm_step = -16'sd512;    4'd15: dpcm_step = -16'sd256;
    endcase
endfunction

function signed [15:0] clip16(input signed [23:0] v);
    clip16 = (v >  24'sd32767) ? 16'sd32767 :
             (v < -24'sd32768) ? -16'sd32768 : v[15:0];
endfunction

function signed [15:0] trimg(input signed [15:0] pcm16, input [4:0] pg);
    trimg = clip16( (pcm16*$signed({1'b0,pg})) >>> 3 );
endfunction
function [3:0] pan_idx(input [7:0] p);
    if      (p >= 8'h81 && p <= 8'h8f) pan_idx = p[3:0] - 4'd1;
    else if (p >= 8'h11 && p <= 8'h1f) pan_idx = p[3:0] - 4'd1;
    else                               pan_idx = 4'd7;
endfunction

wire [3:0] dnib = w_pos[0] ? rom_data[7:4] : rom_data[3:0];
wire signed [15:0] ds = dpcm_step(dnib);

wire [4:0] pcm_g = (debug_bus[7:4]==4'd0) ? 5'd8 : {1'b0, debug_bus[7:4]};

wire [24:0] npos1 = w_rev ? (w_pos - 25'd1) : (w_pos + 25'd1);
wire [24:0] npos2 = w_rev ? (w_pos - 25'd2) : (w_pos + 25'd2);

localparam [21:0] NMI_PERIOD_UNITS = 22'd2_764_800;
reg         nmi_armed;
reg [21:0]  nmi_acc;
wire [8:0]  nmi_step = 9'd38 + {1'b0, regs[10'h227]};

always @(posedge clk) begin
    if (rst) begin
        nmi_armed <= 1'b0; nmi_acc <= 22'd0; nmi_toggle <= 1'b0;
    end else begin
        if (cs && we && addr==10'h227) nmi_armed <= 1'b1;
        if (cs && we && addr==10'h22f && !din[5]) nmi_toggle <= 1'b0;
        if (cen && nmi_armed) begin
            if ({1'b0,nmi_acc} + {13'b0,nmi_step} >= {1'b0,NMI_PERIOD_UNITS}) begin
                nmi_acc    <= nmi_acc + {13'b0,nmi_step} - NMI_PERIOD_UNITS;
                nmi_toggle <= ~nmi_toggle;
            end else begin
                nmi_acc <= nmi_acc + {13'b0,nmi_step};
            end
        end
    end
end

integer ci;
always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE; sample_cnt <= 0; ch <= 0; ovr_cnt <= 0;
        rom_cs <= 0; rom_addr <= 0;
        left <= 0; right <= 0; accL <= 0; accR <= 0;
        active <= 0; restart <= 0;
        reverb_pos <= 0; rr_we <= 0; rr_addr <= 0; rr_din <= 0;
        for (ci=0; ci<8; ci=ci+1) begin
            cpos[ci] <= 0; cpfrac[ci] <= 0; cval[ci] <= 0; cpval[ci] <= 0;
        end
    end else begin

        if (cs && we) begin
            case (addr)
                10'h214: begin restart <= restart | (din & ~active); active <= active | din; end
                10'h215: active <= active & ~din;
                R_22C : active <= din;
                default: ;
            endcase
        end

        if (cen) begin
            sample_cnt <= (sample_cnt == 9'd383) ? 9'd0 : sample_cnt + 9'd1;

            rom_cs <= (state==S_R8 || state==S_R16L || state==S_R16H || state==S_RD) && !rom_ok;
            rr_we  <= 1'b0;

            if (sample_cnt == 9'd0) begin
                left  <= trimg( clip16($signed(accL[39:16])), pcm_g );
                right <= trimg( clip16($signed(accR[39:16])), pcm_g );

                if (state != S_IDLE && !(&ovr_cnt)) ovr_cnt <= ovr_cnt + 16'd1;
                rom_cs <= 1'b0;
                ch     <= 0;
                if (regs[10'h22f][0]) begin
                    state <= S_REVRD;
                end else begin
                    accL <= 0; accR <= 0; state <= S_LOAD;
                end
            end else
            case (state)
            S_IDLE: ;

            S_REVRD: begin
                accL <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };
                accR <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };
                rr_addr <= reverb_pos; rr_din <= 16'sd0; rr_we <= 1'b1;
                reverb_pos <= reverb_pos + 13'd1;
                state <= S_LOAD;
            end

            S_LOAD: begin
                if (!active[ch] || !regs[10'h22f][0]) begin
                    state <= S_NEXT;
                end else begin
                    w_vol    <=  regs[b1+3];
                    w_loop   <= {regs[b1+10'ha], regs[b1+10'h9], regs[b1+10'h8]};
                    w_loopen <=  regs[b2+1][0];
                    w_pan    <=  pan_idx(regs[b1+5]);

                    w_type   <=  type_bad ? 2'd0 : type_now;
                    w_rev    <=  rev_now;
                    w_looped <=  1'b0;

                    if (type_bad) begin

                        if (restart[ch]) begin
                            w_pos   <= {1'b0, regs[b1+10'he], regs[b1+10'hd], regs[b1+10'hc]};
                            w_pfrac <= 32'd0;
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin
                            w_pos   <= {1'b0, cpos[ch]};
                            w_pfrac <= {16'b0, cpfrac[ch]};
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                        state <= S_MIX;
                    end else if (type_now == 2'd2) begin

                        if (restart[ch]) begin
                            w_pos   <= {regs[b1+10'he], regs[b1+10'hd], regs[b1+10'hc]} << 1;
                            w_pfrac <= dsign;
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin

                            w_pos   <= ({cpos[ch],1'b0}) | (cpfrac[ch][15] ? 25'd1 : 25'd0);
                            w_pfrac <= {15'b0, cpfrac[ch], 1'b0} + dsign
                                       - (cpfrac[ch][15] ? 32'h0001_0000 : 32'd0);
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end else begin
                        if (restart[ch]) begin
                            w_pos   <= {1'b0, regs[b1+10'he], regs[b1+10'hd], regs[b1+10'hc]};
                            w_pfrac <= dsign;
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin
                            w_pos   <= {1'b0, cpos[ch]};
                            w_pfrac <= {16'b0, cpfrac[ch]} + dsign;
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end
                    state <= S_ACC;
                end
            end

            S_ACC: begin
                if (|w_pfrac[31:16]) begin
                    w_pfrac  <= w_rev ? (w_pfrac + 32'h0001_0000) : (w_pfrac - 32'h0001_0000);
                    w_looped <= 1'b0;
                    case (w_type)
                    2'd0: begin
                        w_pos    <= npos1;
                        rom_addr <= npos1[23:0];
                        rom_cs   <= 1'b1; state <= S_R8;
                    end
                    2'd1: begin
                        w_pos    <= npos2;
                        rom_addr <= npos2[23:0];
                        rom_cs   <= 1'b1; state <= S_R16L;
                    end
                    default: begin
                        w_pos    <= npos1;
                        rom_addr <= npos1[24:1];
                        rom_cs   <= 1'b1; state <= S_RD;
                    end
                    endcase
                end else begin
                    state <= S_MIX;
                end
            end

            S_R8: if (rom_ok) begin
                w_pval <= w_val;
                if (rom_data == 8'h80) begin
                    if (w_loopen && !w_looped) begin
                        w_looped <= 1'b1;
                        w_pos <= {1'b0, w_loop}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_R8;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, 8'h00}); state <= S_ACC;
                end
            end

            S_R16L: if (rom_ok) begin
                w_lo     <= rom_data;
                rom_addr <= w_pos[23:0] + 24'd1;
                rom_cs   <= 1'b1; state <= S_R16H;
            end
            S_R16H: if (rom_ok) begin
                w_pval <= w_val;
                if ({rom_data, w_lo} == 16'h8000) begin
                    if (w_loopen && !w_looped) begin
                        w_looped <= 1'b1;
                        w_pos <= {1'b0, w_loop}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_R16L;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, w_lo}); state <= S_ACC;
                end
            end

            S_RD: if (rom_ok) begin

                w_pval <= w_val;
                if (rom_data == 8'h88) begin
                    if (w_loopen && !w_looped) begin
                        w_looped <= 1'b1;
                        w_pos <= {w_loop, 1'b0}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_RD;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val  <= clip16( {{8{w_val[15]}}, w_val} + {{8{ds[15]}}, ds} );
                    state  <= S_ACC;
                end
            end

            S_MIX: begin
                accL <= accL + contribL;
                accR <= accR + contribR;
                if (w_type == 2'd2) begin
                    cpos[ch]   <= w_pos[24:1];
                    cpfrac[ch] <= {1'b0, w_pfrac[15:1]} | (w_pos[0] ? 16'h8000 : 16'h0);
                end else begin
                    cpos[ch]   <= w_pos[23:0];
                    cpfrac[ch] <= w_pfrac[15:0];
                end
                cval[ch]  <= w_val;
                cpval[ch] <= w_pval;
                state <= S_RVWR;
            end

            S_RVWR: begin
                rr_addr <= widx;
                rr_din  <= rr_dout + rev_contrib;
                rr_we   <= 1'b1;
                state   <= S_NEXT;
            end

            S_NEXT: begin
                if (ch == 3'd7) state <= S_DONE;
                else begin ch <= ch + 3'd1; state <= S_LOAD; end
            end

            S_DONE: state <= S_IDLE;

            default: state <= S_IDLE;
            endcase
        end
    end
end

reg  [7:0]  ctrl_22f;
reg  [15:0] cen_cnt, ok_cnt, stall_cnt, peak_l, wr_cnt;
reg         rom_ok_l;
wire [15:0] left_u   = left;
wire [15:0] left_abs = left[15] ? (~left_u + 16'd1) : left_u;

always @(posedge clk) begin
    if (rst) begin
        ctrl_22f <= 0; cen_cnt <= 0; ok_cnt <= 0; stall_cnt <= 0; peak_l <= 0; rom_ok_l <= 0;
        wr_cnt   <= 0;
    end else begin
        if (cs && we) wr_cnt <= wr_cnt + 16'd1;
        if (cs && we && addr==R_22F) ctrl_22f <= din;
        rom_ok_l <= rom_ok;
        if (cen) cen_cnt <= cen_cnt + 16'd1;
        if (rom_ok && !rom_ok_l) ok_cnt <= ok_cnt + 16'd1;
        if (rom_cs && !rom_ok && !(&stall_cnt)) stall_cnt <= stall_cnt + 16'd1;
        if (left_abs > peak_l) peak_l <= left_abs;
    end
end

assign st_dout = debug_bus[2:0]==3'd0 ? active          :
                 debug_bus[2:0]==3'd1 ? ctrl_22f        :
                 debug_bus[2:0]==3'd2 ? cen_cnt  [15:8] :
                 debug_bus[2:0]==3'd3 ? ok_cnt   [15:8] :
                 debug_bus[2:0]==3'd4 ? peak_l   [15:8] :
                 debug_bus[2:0]==3'd5 ? stall_cnt[15:8] :
                 debug_bus[2:0]==3'd6 ? wr_cnt   [15:8] :
                 debug_bus[2:0]==3'd7 ? ovr_cnt  [15:8] : 8'd0;

endmodule
