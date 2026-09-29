/*  This file is part of JTCORES (fork COWBOYS). GPLv3. Crédito Jose Tejada / JTFRAME. */

module xexex_k056832(
    input             rst,
    input             clk,
    input             pxl_cen,

    output            lhbl, lvbl, hs, vs,
    output     [ 8:0] hdump, vdump, vrender, vrender1,

    input             vram_cs,
    input             reg_cs,
    input             cpu_we,
    input      [12:1] cpu_addr,
    input      [15:0] cpu_dout,
    output reg [15:0] cpu_din,

    output reg [18:0] rom_addr,
    output reg [ 1:0] rom_lyr,
    output            rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    output     [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl,

    output            lyra_mix, lyrb_mix, lyrc_mix,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

localparam signed [9:0] VX0 = 10'sd40;

function signed [9:0] offx(input [1:0] l);

    case(l) 2'd0: offx=-10'sd2; 2'd1: offx=10'sd2; 2'd2: offx=10'sd4; default: offx=10'sd6; endcase
endfunction

jtframe_vtimer #(
    .HCNT_START(9'h000), .HCNT_END(9'h1FF),

    .HB_START(9'h182), .HB_END(9'h002), .HS_START(9'h193),

    .V_START(9'h0DF), .VB_START(9'h1FF), .VB_END(9'h0FF),
    .VS_START(9'h0EB), .VS_END(9'h0F1), .VCNT_END(9'h1FF)
) u_vtimer(
    .clk(clk), .pxl_cen(pxl_cen),
    .vdump(vdump), .vrender(vrender), .vrender1(vrender1),
    .H(hdump), .Hinit(), .Vinit(),
    .LHBL(lhbl), .LVBL(lvbl), .HS(hs), .VS(vs)
);

reg [15:0] mmr[0:31];
wire [4:0] reg_idx = cpu_addr[5:1];

always @(posedge clk, posedge rst) begin : mmr_rst
    integer ri;
    if(rst) for(ri=0;ri<32;ri=ri+1) mmr[ri]<=0;
    else if(reg_cs & cpu_we) mmr[reg_idx]<=cpu_dout;
end
wire [1:0] fbits = mmr[5'h03][7:6];
function signed [9:0] dxL(input [1:0] l);
    case(l) 2'd0: dxL={mmr[5'h14][9],mmr[5'h14][8:0]}; 2'd1: dxL={mmr[5'h15][9],mmr[5'h15][8:0]};
            2'd2: dxL={mmr[5'h16][9],mmr[5'h16][8:0]}; default: dxL={mmr[5'h17][9],mmr[5'h17][8:0]}; endcase
endfunction
function signed [9:0] dyL(input [1:0] l);
    case(l) 2'd0: dyL={mmr[5'h10][9],mmr[5'h10][8:0]}; 2'd1: dyL={mmr[5'h11][9],mmr[5'h11][8:0]};
            2'd2: dyL={mmr[5'h12][9],mmr[5'h12][8:0]}; default: dyL={mmr[5'h13][9],mmr[5'h13][8:0]}; endcase
endfunction
function [3:0] pageL(input [1:0] l);
    case(l) 2'd0: pageL={mmr[5'h08][4:3],mmr[5'h0c][4:3]}; 2'd1: pageL={mmr[5'h09][4:3],mmr[5'h0d][4:3]};
            2'd2: pageL={mmr[5'h0a][4:3],mmr[5'h0e][4:3]}; default: pageL={mmr[5'h0b][4:3],mmr[5'h0f][4:3]}; endcase
endfunction
wire [3:0] cpu_bank = {mmr[5'h19][4:3], mmr[5'h19][1:0]};

reg  [15:0] vid_addr;
wire [15:0] vram_qcpu, vram_qvid;
wire [15:0] cpu_vaddr = {cpu_bank, cpu_addr[12:1]};
jtframe_dual_ram #(.DW(16),.AW(16)) u_vram(
    .clk0(clk), .data0(cpu_dout), .addr0(cpu_vaddr), .we0(vram_cs & cpu_we), .q0(vram_qcpu),
    .clk1(clk), .data1(16'd0),    .addr1(vid_addr),  .we1(1'b0),            .q1(vram_qvid)
);
always @(posedge clk) cpu_din <= vram_cs ? vram_qcpu : reg_cs ? mmr[reg_idx] : 16'hffff;

reg       dispbank;

localparam P_IDLE=0, P_SETUP=1, P_ATTR=2, P_ATTR2=3, P_CODE=4, P_CODE2=5,
           P_ROM=6, P_ROM2=7, P_ROM3=8, P_DEP=9,
           P_SCR0=10, P_SCR1=11, P_SCR2=12;
reg [3:0]  pf_st;
reg [1:0]  flyr;
reg [5:0]  ftile;
reg [15:0] attr_p, code_p;
reg [31:0] romdata_p;
reg        fbank;
reg [8:0]  fline;
reg        prev_lhbl;

localparam [0:0] C_IDLE=1'd0, C_WRITE=1'd1;
reg        cs_st;
reg [2:0]  fpx;
reg [1:0]  wlyr;
reg [5:0]  wtile;
reg [15:0] attr_c;
reg [31:0] romdata_c;
reg [2:0]  subc;

reg        hs_valid;
reg [15:0] h_attr;
reg [31:0] h_rom;
reg [5:0]  h_tile;
reg [1:0]  h_lyr;
reg [2:0]  h_sub;

reg  [9:0] ldx_cur;
wire signed [11:0] Xbase_s = 12'sd40 + $signed(ldx_cur) - $signed(offx(flyr));
wire [8:0] baseX     = Xbase_s[8:0];
wire [2:0] first_sub = baseX[2:0];
wire [5:0] first_col = baseX[8:3];
wire [5:0] curcol    = first_col + ftile[5:0];

localparam signed [11:0] OFFY = 12'sd16;
wire              flipscr_y = mmr[5'h00][5];
wire signed [11:0] corr_y   = flipscr_y ? {{1{mmr[5'h1e][10]}}, mmr[5'h1e][10:0]} : 12'sd0;

wire [1:0]  lh_l  = mmr[5'h08 + {3'd0,flyr}][1:0];
wire [1:0]  my_l  = mmr[5'h08 + {3'd0,flyr}][4:3];
wire [1:0]  mx_l  = mmr[5'h0c + {3'd0,flyr}][4:3];
wire [11:0] hm1   = {lh_l, 8'hff};
wire signed [12:0] ay_s  = $signed(dyL(flyr)) + corr_y - OFFY;
wire signed [12:0] Y_s   = flipscr_y ? ($signed({1'b0,hm1}) - $signed({5'b0,fline[7:0]}) + ay_s)
                                     : ($signed({5'b0,fline[7:0]}) + ay_s);

function [9:0] mod_h(input [13:0] v, input [1:0] h);
    reg [13:0] t; integer k;
    begin
        case(h)
            2'd0: mod_h = {2'b0, v[7:0]};
            2'd1: mod_h = {1'b0, v[8:0]};
            2'd3: mod_h = v[9:0];
            default: begin t = v; for(k=0;k<8;k=k+1) if(t>=14'd768) t = t - 14'd768; mod_h = t[9:0]; end
        endcase
    end
endfunction
wire [13:0] Y_p   = {Y_s[12], Y_s} + 14'd3072;
wire [9:0]  srcrow= mod_h(Y_p, lh_l);
wire [7:0] Ytm  = srcrow[7:0];
wire [4:0] frow = Ytm[7:3];
wire [2:0] fty  = Ytm[2:0];
wire [11:0] tidx = {frow, curcol, 1'b0};
wire [1:0]  prow_l = my_l + srcrow[9:8];
wire [15:0] attr_addr = {prow_l, mx_l, tidx};

wire [1:0]  smode_l = mmr[5'h05] >> {flyr,1'b0};
wire        lscr_l  = smode_l==2'd0 || smode_l==2'd2;
wire [8:0]  sline_l = smode_l==2'd2 ? {srcrow[8:3],3'b0} : srcrow[8:0];
wire [3:0]  sbank   = {mmr[5'h18][4:3], mmr[5'h18][1:0]};
wire [15:0] scr_waddr = {sbank, flyr, sline_l, 1'b1};
wire [15:0] code_addr = attr_addr | 16'h1;
wire       flipy_p = attr_p[1];
wire [2:0] tyf     = flipy_p ? ~fty : fty;

wire       flipx_c = attr_c[0];
wire [3:0] colnib_c= attr_c[7:4];
wire [2:0] pxf     = flipx_c ? ~fpx : fpx;
function [3:0] tilepen(input [2:0] tx, input [31:0] d);
    reg [1:0] bs; reg [7:0] b;
    begin
        case(tx) 3'd0,3'd1: bs=2'd1; 3'd2,3'd3: bs=2'd0; 3'd4,3'd5: bs=2'd3; default: bs=2'd2; endcase
        b = d[{bs,3'b000}+:8];
        tilepen = tx[0] ? b[3:0] : b[7:4];
    end
endfunction
wire [3:0] pen = tilepen(pxf, romdata_c);
wire signed [11:0] outpx_s = $signed({3'b0,wtile,3'b0}) - $signed({9'b0,subc}) + $signed({9'b0,fpx});
wire [8:0] outpx  = outpx_s[8:0];
wire       outpx_ok = (outpx_s>=0) && (outpx_s<384);

assign rom_cs = (pf_st==P_ROM2) || (pf_st==P_ROM3);
always @(posedge clk, posedge rst) begin
    if(rst) begin
        pf_st<=P_IDLE; cs_st<=C_IDLE; flyr<=0; ftile<=0; fpx<=0; dispbank<=0; fbank<=1;
        rom_addr<=0; rom_lyr<=0; vid_addr<=0; prev_lhbl<=1; fline<=0; hs_valid<=0;
        wlyr<=0; wtile<=0;
    end else begin
        prev_lhbl <= lhbl;

        if( prev_lhbl && !lhbl && pf_st==P_IDLE && cs_st==C_IDLE && !hs_valid ) begin
            dispbank<=fbank;
            fbank<=~fbank;
            flyr<=0; ftile<=0;

            fline<=vrender1;
            pf_st<=P_SCR0;
        end

        case(pf_st)
        P_IDLE:  ;
        P_SCR0:  begin vid_addr<=scr_waddr; pf_st<=P_SCR1; end
        P_SCR1:  pf_st<=P_SCR2;
        P_SCR2:  begin ldx_cur <= lscr_l ? vram_qvid[9:0] : dxL(flyr); pf_st<=P_SETUP; end
        P_SETUP: begin vid_addr<=attr_addr; pf_st<=P_ATTR; end
        P_ATTR:  pf_st<=P_ATTR2;
        P_ATTR2: begin attr_p<=vram_qvid; vid_addr<=code_addr; pf_st<=P_CODE; end
        P_CODE:  pf_st<=P_CODE2;
        P_CODE2: begin code_p<=vram_qvid; pf_st<=P_ROM; end
        P_ROM:   begin rom_addr<={code_p[15:0],3'b0}+{16'b0,tyf}; rom_lyr<=flyr; pf_st<=P_ROM2; end
        P_ROM2:  pf_st<=P_ROM3;
        P_ROM3:  if(rom_ok) begin romdata_p<=rom_data; pf_st<=P_DEP; end
        P_DEP:   if(!hs_valid) begin
                     h_attr<=attr_p; h_rom<=romdata_p; h_tile<=ftile; h_lyr<=flyr; h_sub<=first_sub;
                     hs_valid<=1'b1;
                     if(ftile==6'd48) begin
                         ftile<=0;
                         if(flyr==2'd3) pf_st<=P_IDLE;
                         else begin flyr<=flyr+2'd1; pf_st<=P_SCR0; end
                     end else begin ftile<=ftile+6'd1; pf_st<=P_SETUP; end
                 end
        default: pf_st<=P_IDLE;
        endcase

        case(cs_st)
        C_IDLE: if(hs_valid) begin
                    attr_c<=h_attr; romdata_c<=h_rom; wtile<=h_tile; wlyr<=h_lyr; subc<=h_sub;
                    fpx<=0; hs_valid<=1'b0; cs_st<=C_WRITE;
                end
        C_WRITE: begin

                    if(fpx==3'd7) cs_st<=C_IDLE;
                    else fpx<=fpx+3'd1;
                 end
        endcase
    end
end

wire [9:0] lb_wa = {fbank, outpx};

wire [8:0] lb_wd = {attr_c[2], colnib_c, pen};
wire       lb_we = (cs_st==C_WRITE) && outpx_ok;

wire [8:0] dpx = hdump;
wire [9:0] rdaddr = {dispbank, dpx};
wire [8:0] lb0_q, lb1_q, lb2_q, lb3_q;

jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf0(
    .clk(clk), .rd_addr(rdaddr), .dout(lb0_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd0) );
jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf1(
    .clk(clk), .rd_addr(rdaddr), .dout(lb1_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd1) );
jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf2(
    .clk(clk), .rd_addr(rdaddr), .dout(lb2_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd2) );
jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf3(
    .clk(clk), .rd_addr(rdaddr), .dout(lb3_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd3) );

assign lyrf_pxl = gfx_en[0] ? lb0_q[7:0] : 8'd0;
assign lyra_pxl = gfx_en[1] ? lb1_q[7:0] : 8'd0;
assign lyrb_pxl = gfx_en[2] ? lb2_q[7:0] : 8'd0;
assign lyrc_pxl = gfx_en[3] ? lb3_q[7:0] : 8'd0;

assign lyra_mix = gfx_en[1] & lb1_q[8];
assign lyrb_mix = gfx_en[2] & lb2_q[8];
assign lyrc_mix = gfx_en[3] & lb3_q[8];

endmodule
