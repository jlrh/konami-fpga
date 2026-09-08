/*  This file is part of JTCORES (fork COWBOYS). GPLv3. Crédito Jose Tejada / JTFRAME.

    jtasterix_k056832 — tilemap Konami K056832 (Moo Mesa). Reemplaza jt052109/jt051962 de X-Men.
    Traduce el algoritmo VALIDADO 0.00% del golden (tools/cowboys_golden_prio.py) a RTL.
    Arquitectura: line-buffer con doble-buffer (ping-pong). 4 capas (FIX + 3 scroll).
    Blueprint: research/K056832-RTL-DESIGN.md. Validar con tb_k056832 (sim==golden).

    Salida por capa: lyrX_pxl[7:0] = { colnib[3:0], pen[3:0] }.
      colnib = (attr>>4)&0xf (fbits=3). El colorbase (K053251, FIX=0x70) lo añade colmix.
      pen==0 => transparente.

    Fetch (por línea 'vrender', para mostrar en la siguiente): por cada capa y tile de la línea:
      Xtm=(40+px+scrollX)&511, Ytm=(vrender+scrollY)&255 ; scrollX=dx[L]-offx[L].
      attr=vram[page*0x1000 + (row*64+col)*2] ; code=vram[+1].
      rom_row = code*8 + (flipY?7:0 ^ ty) ; 32b = 4 bytes (b0..b3) ; pen(tx)=nibble por byte {1,1,0,0,3,3,2,2}.
    Presupuesto: 4 capas*49 tiles*~11 clk ≈ 2156 clk/línea < 3072 (384px*8). OK.

    NOTA sim: la ROM de tiles la sirve el testbench (lyrX_data combinacional). En HW será SDRAM
    con line-fetch (mismo modelo, el margen de línea lo permite).
*/
module jtasterix_k056832(
    input             rst,
    input             clk,
    input             pxl_cen,

    output            lhbl, lvbl, hs, vs,
    output     [ 8:0] hdump, vdump, vrender, vrender1,

    input             vram_cs,
    input      [ 1:0] cpu_dsn,
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

    input             tilebank,
    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

localparam signed [9:0] VX0 = 10'sd40;

function signed [9:0] offx(input [1:0] l);
    case(l) 2'd0: offx=-10'sd7; 2'd1: offx=-10'sd5; 2'd2: offx=-10'sd3; default: offx=-10'sd1; endcase
endfunction

jtframe_vtimer #(
    .HCNT_START(9'h000), .HCNT_END(9'h17F),

    .HB_START(9'h122), .HB_END(9'h002), .HS_START(9'h12C),
    .V_START(9'h0FA), .VB_START(9'h1EF), .VB_END(9'h10F),
    .VS_START(9'h1FF), .VS_END(9'h0FF), .VCNT_END(9'h1FF)
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
`ifdef SIMULATION

integer n_reg=0;
always @(posedge clk) if(reg_cs & cpu_we && n_reg<150) begin
    n_reg <= n_reg+1;
    $display("K56832-REG[%02x] <= %04x", reg_idx, cpu_dout);
end

always @(posedge clk) if(reg_cs & cpu_we && reg_idx==5'h1c)
    $display("K56832-REG1C <= %04x  vrender=%0d", cpu_dout, vrender);

reg tilebank_l=0;
always @(posedge clk) begin
    tilebank_l <= tilebank;
    if(tilebank !== tilebank_l) $display("K56832-TILEBANK <= %b  vrender=%0d", tilebank, vrender);
end

reg [15:0] frame_cnt=0;
reg vs_l=0;
always @(posedge clk) begin
    vs_l <= vs;
    if(vs && !vs_l) frame_cnt <= frame_cnt + 1'b1;
end
always @(posedge clk) if(pf_st==P_ROM3 && rom_ok && flyr==2'd2 && code_p!=16'd0
                          && frame_cnt>=16'd456 && frame_cnt<=16'd457)
    $display("K56832-FIXDUMP frame=%0d ftile=%0d fline=%0d code=%04x bank=%0d get_lookup=%0d ptcode=%04x rom_addr=%05x rom_data=%08x",
              frame_cnt, ftile, fline, code_p, code_p[11:10], get_lookup, ptcode, rom_addr, rom_data);

always @(posedge clk) if(cs_st==C_WRITE && wlyr==2'd2 && wtile>=6'd4 && wtile<=6'd20
                          && frame_cnt>=16'd456 && frame_cnt<=16'd457)
    $display("K56832-FIXWR frame=%0d fbank=%0d wtile=%0d fpx=%0d subc=%0d outpx_s=%0d outpx=%0d ok=%b pen=%0d colnib=%0d",
              frame_cnt, fbank, wtile, fpx, subc, outpx_s, outpx, outpx_ok, pen, colnib_c);
`endif
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

wire [15:0] cpu_vaddr = {cpu_bank, cpu_addr[11:1], 1'b1};
wire [ 1:0] vram_we   = {2{vram_cs & cpu_we}} & ~cpu_dsn;

jtframe_dual_ram16 #(.AW(16)) u_vram(
    .clk0(clk), .data0(cpu_dout), .addr0(cpu_vaddr), .we0(vram_we), .q0(vram_qcpu),
    .clk1(clk), .data1(16'd0),    .addr1(vid_addr),  .we1(2'b0),            .q1(vram_qvid)
);
always @(posedge clk) cpu_din <= vram_cs ? vram_qcpu : reg_cs ? mmr[reg_idx] : 16'hffff;

reg       dispbank;

localparam P_IDLE=0, P_SETUP=1, P_ATTR=2, P_ATTR2=3, P_CODE=4, P_CODE2=5,
           P_ROM=6, P_ROM2=7, P_ROM3=8, P_DEP=9,
           P_RS1=10, P_RS2=11, P_RS3=12;
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

reg [31:0] prevdata_c;
reg [15:0] prevattr_c;

reg        hs_valid;
reg [15:0] h_attr;
reg [31:0] h_rom;
reg [5:0]  h_tile;
reg [1:0]  h_lyr;
reg [2:0]  h_sub;
`ifdef PEINEPROBE

reg [5:0]  h_dbg_curcol, dbg_curcol;
reg [4:0]  h_dbg_frow,   dbg_frow;
reg [2:0]  h_dbg_fty,    dbg_fty;
reg [15:0] h_dbg_codeaddr, dbg_codeaddr;
reg [18:0] h_dbg_romaddr,  dbg_romaddr;
`endif

reg  [1:0] smL;
reg [15:0] dyraw;
always @* case(flyr)
    2'd0: begin smL = mmr[5'h05][1:0]; dyraw = mmr[5'h10]; end
    2'd1: begin smL = mmr[5'h05][3:2]; dyraw = mmr[5'h11]; end
    2'd2: begin smL = mmr[5'h05][5:4]; dyraw = mmr[5'h12]; end
    default: begin smL = mmr[5'h05][7:6]; dyraw = mmr[5'h13]; end
endcase
wire        rowscroll = (smL==2'd0) || (smL==2'd2);
wire [15:0] r18       = mmr[5'h18];
wire [ 3:0] scrollbank= {r18[4], r18[3], r18[1], r18[0]};
wire [ 8:0] sy8  = {1'b0, fline[7:0]};
wire [ 8:0] k2   = (sy8 + {6'd0, dyraw[2:0]}) >> 3;
wire [ 5:0] idx2 = dyraw[8:3] + k2[5:0];
wire [ 8:0] idx0 = dyraw[8:0] + sy8;
wire [ 8:0] so_h = (smL==2'd2) ? {idx2, 3'd0} : idx0;
wire [15:0] rs_addr = {scrollbank, flyr, so_h, 1'b1};
reg  [15:0] rs_dx;

wire signed [11:0] dx_eff = rowscroll ? $signed({3'd0, rs_dx[8:0]}) : $signed(dxL(flyr));
wire signed [11:0] Xbase_s = 12'sd16 + dx_eff - $signed(offx(flyr));
wire [8:0] baseX     = Xbase_s[8:0];
wire [2:0] first_sub = baseX[2:0];
wire [5:0] first_col = baseX[8:3];
wire [5:0] curcol    = first_col + ftile[5:0];

localparam signed [11:0] VY0 = 12'sd0;
wire signed [11:0] Y_s = $signed({3'b0,fline}) + $signed(dyL(flyr)) + VY0;
wire [7:0] Ytm  = Y_s[7:0];
wire [4:0] frow = Ytm[7:3];
wire [2:0] fty  = Ytm[2:0];
wire [11:0] tidx = {frow, curcol, 1'b0};
wire [15:0] attr_addr = {pageL(flyr), tidx};
wire [15:0] code_addr = attr_addr | 16'h1;

wire        cur_tile_bank = tilebank;
reg  [ 3:0] tbk_lut;
always @* case(code_p[11:10])
    2'd0: tbk_lut = mmr[5'h1c][ 3: 0];
    2'd1: tbk_lut = mmr[5'h1c][ 7: 4];
    2'd2: tbk_lut = mmr[5'h1c][11: 8];
    2'd3: tbk_lut = mmr[5'h1c][15:12];
endcase
wire [ 4:0] get_lookup = {1'b0, tbk_lut} | {cur_tile_bank, 4'b0};
wire [14:0] ptcode     = {get_lookup, code_p[9:0]};

wire       flipy_p = 1'b0;
wire [2:0] tyf     = flipy_p ? ~fty : fty;
wire _unused_attr  = &{1'b0, attr_p, 1'b0};

wire       use_prev = fpx < 3'd2;
wire [15:0] attr_eff = use_prev ? prevattr_c : attr_c;
wire [31:0] rom_eff  = use_prev ? prevdata_c : romdata_c;
wire       flipx_c = attr_eff[12];
wire [3:0] colnib_c= {1'b0, attr_eff[15:13]};

wire [2:0] tx0_true = fpx - 3'd2;
wire [2:0] pxf       = flipx_c ? ~tx0_true : tx0_true;
function [3:0] tilepen(input [2:0] tx, input [31:0] d);
    reg [1:0] bs; reg [7:0] b;
    begin

        case(tx) 3'd0,3'd1: bs=2'd1; 3'd2,3'd3: bs=2'd0; 3'd4,3'd5: bs=2'd3; default: bs=2'd2; endcase
        b = d[{bs,3'b000}+:8];
        tilepen = tx[0] ? b[3:0] : b[7:4];
    end
endfunction
wire [3:0] pen = tilepen(pxf, rom_eff);

wire signed [11:0] outpx_s = $signed({3'b0,wtile,3'b0}) - $signed({9'b0,subc}) + $signed({9'b0,fpx});
wire [8:0] outpx  = outpx_s[8:0];
wire       outpx_ok = (outpx_s>=0) && (outpx_s<384);
`ifdef PEINEPROBE

always @(posedge clk) if(cs_st==C_WRITE && wlyr==2'd2 && outpx>=9'd56 && outpx<=9'd72)
    $display("PEINE fline=%0d outpx=%0d wtile=%0d subc=%0d fpx=%0d tx=%0d curcol=%0d frow=%0d fty=%0d code_addr=%05x rom_addr=%05x code=%04x romdata=%08x pen=%0d colnib=%0d",
              fline, outpx, wtile, subc, fpx, pxf, dbg_curcol, dbg_frow, dbg_fty, dbg_codeaddr, dbg_romaddr, attr_c, romdata_c, pen, colnib_c);
`endif

assign rom_cs = (pf_st==P_ROM2);
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
            pf_st<=P_RS1;
        end

        case(pf_st)
        P_IDLE:  ;

        P_RS1:   begin vid_addr<=rs_addr; pf_st<=P_RS2; end
        P_RS2:   pf_st<=P_RS3;
        P_RS3:   begin rs_dx<=vram_qvid; pf_st<=P_SETUP; end
        P_SETUP: begin vid_addr<=attr_addr; pf_st<=P_ATTR; end
        P_ATTR:  pf_st<=P_ATTR2;
        P_ATTR2: begin attr_p<=vram_qvid; vid_addr<=code_addr; pf_st<=P_CODE; end
        P_CODE:  pf_st<=P_CODE2;
        P_CODE2: begin code_p<=vram_qvid; pf_st<=P_ROM; end
        P_ROM:   begin rom_addr<={ptcode,3'b0}+{16'b0,tyf}; rom_lyr<=flyr; pf_st<=P_ROM2; end
        P_ROM2:  pf_st<=P_ROM3;
        P_ROM3:  if(rom_ok) begin romdata_p<=rom_data; pf_st<=P_DEP; end
        P_DEP:   if(!hs_valid) begin
                     h_attr<=code_p; h_rom<=romdata_p; h_tile<=ftile; h_lyr<=flyr; h_sub<=first_sub;
`ifdef PEINEPROBE
                     h_dbg_curcol<=curcol; h_dbg_frow<=frow; h_dbg_fty<=fty;
                     h_dbg_codeaddr<=code_addr; h_dbg_romaddr<=rom_addr;
`endif
                     hs_valid<=1'b1;
                     if(ftile==6'd48) begin
                         ftile<=0;
                         if(flyr==2'd3) pf_st<=P_IDLE;
                         else begin flyr<=flyr+2'd1; pf_st<=P_RS1; end
                     end else begin ftile<=ftile+6'd1; pf_st<=P_SETUP; end
                 end
        default: pf_st<=P_IDLE;
        endcase

        case(cs_st)
        C_IDLE: if(hs_valid) begin
                    prevdata_c<=romdata_c; prevattr_c<=attr_c;
                    attr_c<=h_attr; romdata_c<=h_rom; wtile<=h_tile; wlyr<=h_lyr; subc<=h_sub;
`ifdef PEINEPROBE
                    dbg_curcol<=h_dbg_curcol; dbg_frow<=h_dbg_frow; dbg_fty<=h_dbg_fty;
                    dbg_codeaddr<=h_dbg_codeaddr; dbg_romaddr<=h_dbg_romaddr;
`endif
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
wire [7:0] lb_wd = {colnib_c, pen};
wire       lb_we = (cs_st==C_WRITE) && outpx_ok;

wire [8:0] dpx = hdump + 9'd2;
wire [9:0] rdaddr = {dispbank, dpx};
wire [7:0] lb0_q, lb1_q, lb2_q, lb3_q;

jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf0(
    .clk(clk), .rd_addr(rdaddr), .dout(lb0_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd0) );
jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf1(
    .clk(clk), .rd_addr(rdaddr), .dout(lb1_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd1) );
jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf2(
    .clk(clk), .rd_addr(rdaddr), .dout(lb2_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd2) );
jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf3(
    .clk(clk), .rd_addr(rdaddr), .dout(lb3_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd3) );

assign lyrf_pxl = gfx_en[0] ? lb0_q : 8'd0;
assign lyra_pxl = gfx_en[1] ? lb1_q : 8'd0;
assign lyrb_pxl = gfx_en[2] ? lb2_q : 8'd0;
assign lyrc_pxl = gfx_en[3] ? lb3_q : 8'd0;

endmodule
