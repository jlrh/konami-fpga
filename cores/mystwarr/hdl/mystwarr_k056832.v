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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.  */

module mystwarr_k056832(
    input             rst,
    input             clk,

    input             lhbl,
    input      [ 8:0] hdump,
    input      [ 8:0] vrender1,

    input             vram_cs,
    input             reg_cs,
    input             regb_cs,
    input             cpu_we,
    input      [ 1:0] cpu_dsn,
    input      [12:1] cpu_addr,
    input      [15:0] cpu_dout,
    output reg [15:0] cpu_din,

    output reg [18:0] scr_addr,
    output            scr_cs,
    input      [31:0] scr_data,
    input             scr_ok,
    output reg [18:0] scrx_addr,
    output            scrx_cs,
    input      [ 7:0] scrx_data,
    input             scrx_ok,

    output     [ 8:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl,
    output     [ 1:0] lyra_mix, lyrb_mix, lyrc_mix,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout
);

localparam [11:0] VX0 = 12'd24;
function [11:0] offx(input [1:0] l);
    case(l)
        2'd0:    offx = -12'd5;
        2'd1:    offx = -12'd3;
        2'd2:    offx = -12'd1;
        default: offx =  12'd0;
    endcase
endfunction

localparam [11:0] ACTIVE_PX = 12'd288;
localparam [ 5:0] LAST_TILE =  6'd36;

localparam [11:0] VY_ADJ = -12'd256;

reg [15:0] mmr [0:31];
reg [15:0] mmrb[0: 3];
wire [4:0] reg_idx  = cpu_addr[5:1];
wire [1:0] regb_idx = cpu_addr[2:1];
wire [1:0] cpu_wen  = {2{cpu_we}} & ~cpu_dsn;

always @(posedge clk, posedge rst) begin : mmr_rst
    integer ri;
    if(rst) begin
        for(ri=0;ri<32;ri=ri+1) mmr[ri]  <= 16'd0;
        for(ri=0;ri< 4;ri=ri+1) mmrb[ri] <= 16'd0;
    end else begin
        if( reg_cs ) begin
            if(cpu_wen[1]) mmr[reg_idx][15:8] <= cpu_dout[15:8];
            if(cpu_wen[0]) mmr[reg_idx][ 7:0] <= cpu_dout[ 7:0];
        end

        if( regb_cs ) begin
            if(cpu_wen[1]) mmrb[regb_idx][15:8] <= cpu_dout[15:8];
            if(cpu_wen[0]) mmrb[regb_idx][ 7:0] <= cpu_dout[ 7:0];
        end
    end
end

wire [1:0] fbits = mmr[5'h03][7:6];

function [1:0] attr_flip(input [15:0] a);
    case(fbits)
        2'd0:    attr_flip = a[7:6];
        2'd1:    attr_flip = a[5:4];
        2'd2:    attr_flip = a[3:2];
        default: attr_flip = a[1:0];
    endcase
endfunction

function [5:0] attr_col(input [15:0] a);
    case(fbits)
        2'd0:    attr_col =  a[5:0];
        2'd1:    attr_col = {a[7:6],a[3:0]};
        2'd2:    attr_col = {a[7:4],a[1:0]};
        default: attr_col =  a[7:2];
    endcase
endfunction

function [1:0] ybaseL(input [1:0] l); ybaseL = mmr[{3'b010,l}][4:3]; endfunction
function [1:0] hspanL(input [1:0] l); hspanL = mmr[{3'b010,l}][1:0]; endfunction
function [1:0] xbaseL(input [1:0] l); xbaseL = mmr[{3'b011,l}][4:3]; endfunction
function [1:0] wspanL(input [1:0] l); wspanL = mmr[{3'b011,l}][1:0]; endfunction
function [11:0] dyL(input [1:0] l);   dyL    = mmr[{3'b100,l}][11:0]; endfunction
function [11:0] dxL(input [1:0] l);   dxL    = mmr[{3'b101,l}][11:0]; endfunction

function [1:0] flipenL(input [1:0] l);
    case(l) 2'd0: flipenL=mmr[5'h01][1:0]; 2'd1: flipenL=mmr[5'h01][3:2];
            2'd2: flipenL=mmr[5'h01][5:4]; default: flipenL=mmr[5'h01][7:6]; endcase
endfunction

wire [3:0] cpu_bank = {mmr[5'h19][4:3], mmr[5'h19][1:0]};

reg  [15:0] vid_addr;
wire [15:0] vram_qcpu, vram_qvid;
wire [15:0] cpu_vaddr = {cpu_bank, cpu_addr[12:1]};

jtframe_dual_ram16 #(.AW(16)) u_vram(
    .clk0   ( clk       ), .data0( cpu_dout ), .addr0( cpu_vaddr ),
    .we0    ( {2{vram_cs}} & cpu_wen ), .q0( vram_qcpu ),
    .clk1   ( clk       ), .data1( 16'd0    ), .addr1( vid_addr  ),
    .we1    ( 2'd0      ), .q1   ( vram_qvid )
);
always @(posedge clk) cpu_din <= vram_cs ? vram_qcpu : reg_cs ? mmr[reg_idx] : 16'hffff;

localparam P_IDLE=0, P_SETUP=1, P_ATTR=2, P_ATTR2=3, P_CODE=4, P_CODE2=5,
           P_ROM=6, P_ROM2=7, P_ROM3=8, P_DEP=9,
           P_ROM4=10, P_ROM5=11, P_ROM6=12, P_ROMW=13;
reg [3:0]  pf_st;
reg [1:0]  flyr;
reg [5:0]  ftile;
reg [1:0]  c_lyr;
reg [5:0]  c_tile;
reg [2:0]  c_sub;
reg        c_last;
reg [15:0] attr_q, code_q;
reg [15:0] attr_p, code_p;
reg [31:0] romdata_p;
reg [ 7:0] romx_p;
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
reg [ 7:0] romx_c;
reg [2:0]  subc;

reg        hs_valid;
reg [15:0] h_attr;
reg [31:0] h_rom;
reg [ 7:0] h_romx;
reg [ 5:0] h_tile;
reg [ 1:0] h_lyr;
reg [ 2:0] h_sub;

reg        dispbank;

wire        hsel = hspanL(flyr)!=2'd0;
wire        wsel = wspanL(flyr)!=2'd0;

wire [11:0] Xbase_s   = VX0 + dxL(flyr) - offx(flyr);
wire [ 9:0] baseX     = wsel ? Xbase_s[9:0] : {1'b0,Xbase_s[8:0]};
wire [ 2:0] first_sub = baseX[2:0];
wire [ 6:0] first_col = baseX[9:3];
wire [ 6:0] curcol    = first_col + {1'b0,ftile};
wire [ 6:0] colw      = wsel ? curcol : {1'b0,curcol[5:0]};

wire [11:0] Y_s  = {3'd0,fline} + dyL(flyr) + VY_ADJ;
wire [ 8:0] Ytm  = hsel ? Y_s[8:0] : {1'b0,Y_s[7:0]};
wire [ 5:0] rowh = Ytm[8:3];
wire [ 3:0] fpage= { ybaseL(flyr) + {1'b0, hsel & rowh[5]},
                     xbaseL(flyr) + {1'b0, wsel & colw[6]} };
wire [ 2:0] fty  = Ytm[2:0];
wire [15:0] attr_addr = {fpage, rowh[4:0], colw[5:0], 1'b0};
wire [15:0] code_addr = attr_addr | 16'h1;
wire [ 1:0] flip_p    = flipenL(flyr) & attr_flip(attr_p);
wire [ 2:0] tyf       = flip_p[1] ? ~fty : fty;

wire [ 1:0] flip_c   = flipenL(wlyr) & attr_flip(attr_c);
wire [ 5:0] color6_c = attr_col(attr_c);
wire [ 3:0] colnib_c = color6_c[4:1];
wire [ 1:0] mix_c    = attr_c[3:2];
wire [ 2:0] pxf      = flip_c[0] ? ~fpx : fpx;

function [3:0] tilenib(input [2:0] tx, input [31:0] d);
    reg [1:0] bs; reg [7:0] b;
    begin
        bs = tx[2:1];
        b = d[{bs,3'b000}+:8];
        tilenib = tx[0] ? b[3:0] : b[7:4];
    end
endfunction

wire [4:0] pen = { romx_c[~pxf], tilenib(pxf, romdata_c) };

wire signed [11:0] outpx_s = $signed({3'b0,wtile,3'b0}) - $signed({9'b0,subc}) + $signed({9'b0,fpx});
wire        [ 8:0] outpx   = outpx_s[8:0];
wire               outpx_ok= (outpx_s>=0) && (outpx_s<$signed(ACTIVE_PX));

assign scr_cs  = (pf_st==P_ROM2) || (pf_st==P_ROM3) || (pf_st==P_ROM4) ||
                 (pf_st==P_ROM5) || (pf_st==P_ROM6) || (pf_st==P_ROMW);
assign scrx_cs = scr_cs;

always @(posedge clk, posedge rst) begin
    if(rst) begin
        pf_st<=P_IDLE; cs_st<=C_IDLE; flyr<=0; ftile<=0; fpx<=0; dispbank<=0; fbank<=1;
        scr_addr<=0; scrx_addr<=0; vid_addr<=0; prev_lhbl<=1; fline<=0; hs_valid<=0;
        wlyr<=0; wtile<=0; attr_p<=0; code_p<=0; romdata_p<=0; romx_p<=0;
        c_lyr<=0; c_tile<=0; c_sub<=0; c_last<=0; attr_q<=0; code_q<=0;
        attr_c<=0; romdata_c<=0; romx_c<=0; subc<=0;
        h_attr<=0; h_rom<=0; h_romx<=0; h_tile<=0; h_lyr<=0; h_sub<=0;
    end else begin
        prev_lhbl <= lhbl;

        if( prev_lhbl && !lhbl && pf_st==P_IDLE && cs_st==C_IDLE && !hs_valid ) begin
            dispbank <= fbank;
            fbank    <= ~fbank;
            flyr     <= 2'd0;
            ftile    <= 6'd0;
            fline    <= vrender1;
            pf_st    <= P_SETUP;
        end

        case(pf_st)
        P_IDLE:  ;
        P_SETUP: begin vid_addr<=attr_addr; pf_st<=P_ATTR; end
        P_ATTR:  pf_st<=P_ATTR2;
        P_ATTR2: begin attr_p<=vram_qvid; vid_addr<=code_addr; pf_st<=P_CODE; end
        P_CODE:  pf_st<=P_CODE2;
        P_CODE2: begin code_p<=vram_qvid; pf_st<=P_ROM; end

        P_ROM:   begin
                     scr_addr <= {code_p,tyf};
                     scrx_addr<= {code_p,tyf};
                     c_lyr    <= flyr;
                     c_tile   <= ftile;
                     c_sub    <= first_sub;
                     c_last   <= (ftile==LAST_TILE) && (flyr==2'd3);
                     if( ftile==LAST_TILE ) begin ftile<=6'd0; flyr<=flyr+2'd1; end
                     else                        ftile<=ftile+6'd1;
                     pf_st    <= P_ROM2;
                 end

        P_ROM2:  begin vid_addr<=attr_addr; pf_st<=P_ROM3; end
        P_ROM3:  pf_st<=P_ROM4;
        P_ROM4:  begin attr_q<=vram_qvid; vid_addr<=code_addr; pf_st<=P_ROM5; end
        P_ROM5:  pf_st<=P_ROM6;
        P_ROM6:  begin code_q<=vram_qvid; pf_st<=P_ROMW; end
        P_ROMW:  if(scr_ok && scrx_ok) begin
                     romdata_p<=scr_data; romx_p<=scrx_data; pf_st<=P_DEP;
                 end
        P_DEP:   if(!hs_valid) begin
                     h_attr<=attr_p; h_rom<=romdata_p; h_romx<=romx_p;
                     h_tile<=c_tile; h_lyr<=c_lyr;     h_sub  <=c_sub;
                     hs_valid<=1'b1;
                     if( c_last ) pf_st<=P_IDLE;
                     else begin
                         attr_p<=attr_q; code_p<=code_q;
                         pf_st <=P_ROM;
                     end
                 end
        default: pf_st<=P_IDLE;
        endcase

        case(cs_st)
        C_IDLE: if(hs_valid) begin
                    attr_c<=h_attr; romdata_c<=h_rom; romx_c<=h_romx;
                    wtile <=h_tile; wlyr    <=h_lyr; subc  <=h_sub;
                    fpx<=3'd0; hs_valid<=1'b0; cs_st<=C_WRITE;
                end
        C_WRITE: begin

                    if(fpx==3'd7) cs_st<=C_IDLE; else fpx<=fpx+3'd1;
                 end
        endcase
    end
end

wire [ 9:0] lb_wa = {fbank, outpx};
wire [10:0] lb_wd = {mix_c, colnib_c, pen};
wire        lb_we = (cs_st==C_WRITE) && outpx_ok;
wire [ 8:0] dpx    = hdump;
wire [ 9:0] rdaddr = {dispbank, dpx};
wire [10:0] lb0_q, lb1_q, lb2_q, lb3_q;

jtframe_rpwp_ram #(.DW(11),.AW(10)) u_lbuf0(
    .clk(clk), .rd_addr(rdaddr), .dout(lb0_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd0) );
jtframe_rpwp_ram #(.DW(11),.AW(10)) u_lbuf1(
    .clk(clk), .rd_addr(rdaddr), .dout(lb1_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd1) );
jtframe_rpwp_ram #(.DW(11),.AW(10)) u_lbuf2(
    .clk(clk), .rd_addr(rdaddr), .dout(lb2_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd2) );
jtframe_rpwp_ram #(.DW(11),.AW(10)) u_lbuf3(
    .clk(clk), .rd_addr(rdaddr), .dout(lb3_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd3) );

assign lyrf_pxl = gfx_en[0] ? lb0_q[8:0] : 9'd0;
assign lyra_pxl = gfx_en[1] ? lb1_q[8:0] : 9'd0;
assign lyrb_pxl = gfx_en[2] ? lb2_q[8:0] : 9'd0;
assign lyrc_pxl = gfx_en[3] ? lb3_q[8:0] : 9'd0;

assign lyra_mix = gfx_en[1] ? lb1_q[10:9] : 2'd0;
assign lyrb_mix = gfx_en[2] ? lb2_q[10:9] : 2'd0;
assign lyrc_mix = gfx_en[3] ? lb3_q[10:9] : 2'd0;

assign st_dout  = debug_bus[0] ? {1'b0, fbits, mmrb[2][3], cpu_bank} : {pf_st, cs_st, wlyr, hs_valid};

`ifdef SIMULATION
integer warn_l;
reg [1:0] smode;
always @(posedge clk) begin
    if( reg_cs && |cpu_wen ) begin
        for(warn_l=0; warn_l<4; warn_l=warn_l+1) begin

            if( hspanL(warn_l[1:0])>2'd1 || wspanL(warn_l[1:0])>2'd1 )
                $display("WARN %m: capa %0d con span NO potencia de 2 (h=%0d w=%0d) — no soportado",
                         warn_l, hspanL(warn_l[1:0]), wspanL(warn_l[1:0]));

            smode = mmr[5'h05][warn_l*2 +: 2];
            if( smode==2'd0 || smode==2'd2 )
                $display("WARN %m: capa %0d en %s — solo se soporta xyscroll",
                         warn_l, smode==2'd0 ? "linescroll" : "rowscroll");
        end

        if( mmr[5'h00][5:4]!=2'd0 )
            $display("WARN %m: flip GLOBAL de pantalla activo (regs[0]=%02x) — no implementado",
                     mmr[5'h00][7:0]);
    end
end
`endif

endmodule
