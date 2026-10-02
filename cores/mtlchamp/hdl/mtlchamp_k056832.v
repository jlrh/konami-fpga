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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module mtlchamp_k056832(
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

    output reg [18:0] scrb_addr,
    output            scrb_cs,
    input      [31:0] scrb_data,
    input             scrb_ok,
    output reg [18:0] scrxb_addr,
    output            scrxb_cs,
    input      [ 7:0] scrxb_data,
    input             scrxb_ok,

    output     [ 8:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl,
    output     [ 1:0] lyra_mix, lyrb_mix, lyrc_mix,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout
);

localparam [11:0] VX0 = 12'd32;
function [11:0] offx(input [1:0] l);
    case(l)
        2'd0:    offx = -12'd6;
        2'd1:    offx = -12'd4;
        2'd2:    offx = -12'd2;
        default: offx = -12'd1;
    endcase
endfunction

localparam [11:0] ACTIVE_PX = 12'd384;
localparam [ 5:0] LAST_TILE =  6'd48;

localparam [11:0] VY_ADJ = -12'd257;

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

localparam P_IDLE=0, P_SETUP=1, P_ATTR=2, P_ATTR2=3, P_CODE=4, P_CODE2=5, P_DEP=6;

localparam P_LSCR=7, P_LSCR1=8, P_LSCR2=9;
localparam B_IDLE=0, B_ROM=1, B_ROM2=2, B_ROM3=3, B_DEP=4;
reg [3:0]  pf_st;

reg [2:0]  b0_st, b1_st;
reg        bload, bdep;

wire       fetch_libre = b0_st==B_IDLE && b1_st==B_IDLE;

reg        av_valid;
reg [15:0] a2b_code, a2b_attr;
reg [ 2:0] a2b_tyf, a2b_sub;
reg [ 5:0] a2b_tile;
reg [ 1:0] a2b_lyr;

reg [15:0] b0_attr_r, b1_attr_r;
reg [ 5:0] b0_tile_r, b1_tile_r;
reg [ 1:0] b0_lyr_r,  b1_lyr_r;
reg [ 2:0] b0_sub_r,  b1_sub_r;
reg [1:0]  flyr;
reg [5:0]  ftile;
reg [15:0] attr_p, code_p;
reg [31:0] romdata0_p, romdata1_p;
reg [ 7:0] romx0_p,    romx1_p;
reg        fbank;
reg [8:0]  fline;
reg        prev_lhbl;
reg [11:0] dx_line;
reg        dx_line_en;

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

reg [7:0] skip_cnt, skip_lat;
reg [8:0] prev_vr1;

wire        hsel = hspanL(flyr)!=2'd0;
wire        wsel = wspanL(flyr)!=2'd0;

localparam signed [11:0] LSCR_D = -12'sd14;
wire [ 3:0] lscr_bank = {mmr[5'h18][4:3], mmr[5'h18][1:0]};
wire [ 1:0] lscr_modo = (mmr[5'h05] >> {flyr,1'b0}) & 2'd3;
wire        lscr_on   = lscr_modo==2'd0;

wire [11:0] Xbase_s   = VX0 + (dx_line_en ? dx_line : dxL(flyr)) + corr_x - offx(flyr);
wire [ 9:0] baseX     = wsel ? Xbase_s[9:0] : {1'b0,Xbase_s[8:0]};
wire [ 2:0] first_sub = baseX[2:0];
wire [ 6:0] first_col = baseX[9:3];
wire [ 6:0] curcol    = first_col + {1'b0,ftile};
wire [ 6:0] colw      = wsel ? curcol : {1'b0,curcol[5:0]};

wire gflipy = mmr[5'h00][5];
wire gflipx = mmr[5'h00][4];

wire signed [11:0] corr_y = gflipy ? {mmr[5'h1e][10], mmr[5'h1e][10:0]} : 12'sd0;
wire signed [11:0] corr_x = gflipx ?  mmr[5'h1d][11:0]                  : 12'sd0;

wire [11:0] ay_sum = dyL(flyr) + corr_y;
wire [ 8:0] ay_raw = hsel ? ay_sum[8:0] : {1'b0, ay_sum[7:0]};
wire [ 8:0] ay_inv = 9'd256 - ay_raw;

localparam AY0_DESEMPATE = 1'b0;

wire [11:0] bmy_s     = {3'd0,fline} + VY_ADJ;
wire [ 8:0] lscr_e    = ay_raw - bmy_s[8:0] - 9'd1 + LSCR_D[8:0];
wire [15:0] lscr_addr = {lscr_bank, flyr, lscr_e, 1'b1};

wire [ 8:0] ayL    = (gflipy & (AY0_DESEMPATE ? (|ay_raw[7:0]) : 1'b1))
                     ? (hsel ? ay_inv : {1'b0, ay_inv[7:0]})
                     : ay_raw;

wire [11:0] Y_s  = {3'd0,fline} + VY_ADJ + {3'd0, ayL};
wire [ 8:0] Ytm  = hsel ? Y_s[8:0] : {1'b0,Y_s[7:0]};

localparam [11:0] DELTA12 = 12'd0;

wire [11:0] Y_s12 = Y_s + DELTA12;
wire [ 8:0] Ytm12 = hsel ? Y_s12[8:0] : {1'b0,Y_s12[7:0]};

wire [ 7:0] yp   = gflipy ? ~Ytm[7:0] : Ytm[7:0];

wire [ 3:0] fpage= { ybaseL(flyr) + {1'b0, hsel & Ytm12[8]},
                     xbaseL(flyr) + {1'b0, wsel & colw[6]} };
wire [ 4:0] rowh = yp[7:3];
wire [ 2:0] fty  = yp[2:0];
wire [15:0] attr_addr = {fpage, rowh, colw[5:0], 1'b0};
wire [15:0] code_addr = attr_addr | 16'h1;
wire [ 1:0] flip_p    = flipenL(flyr) & attr_flip(attr_p);
wire [ 2:0] tyf       = flip_p[1] ? ~fty : fty;

wire [ 1:0] flip_c   = flipenL(wlyr) & attr_flip(attr_c);
wire [ 5:0] color6_c = attr_col(attr_c);
wire [ 3:0] colnib_c = color6_c[4:1];

localparam TILE_MIX_EN = 1'b1;
wire [ 1:0] mix_c    = TILE_MIX_EN ? attr_c[3:2] : 2'd0;
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

assign scr_cs   = (b0_st==B_ROM2) || (b0_st==B_ROM3);
assign scrx_cs  = scr_cs;
assign scrb_cs  = (b1_st==B_ROM2) || (b1_st==B_ROM3);
assign scrxb_cs = scrb_cs;

always @(posedge clk, posedge rst) begin
    if(rst) begin
        pf_st<=P_IDLE; b0_st<=B_IDLE; b1_st<=B_IDLE; bload<=0; bdep<=0;
        dx_line<=12'd0; dx_line_en<=1'b0;
        cs_st<=C_IDLE; flyr<=0; ftile<=0; fpx<=0;
        dispbank<=0; fbank<=1;
        scr_addr<=0; scrx_addr<=0; scrb_addr<=0; scrxb_addr<=0;
        vid_addr<=0; prev_lhbl<=1; fline<=0; hs_valid<=0;
        wlyr<=0; wtile<=0; attr_p<=0; code_p<=0;
        romdata0_p<=0; romx0_p<=0; romdata1_p<=0; romx1_p<=0;
        attr_c<=0; romdata_c<=0; romx_c<=0; subc<=0;
        h_attr<=0; h_rom<=0; h_romx<=0; h_tile<=0; h_lyr<=0; h_sub<=0;
        av_valid<=0; a2b_code<=0; a2b_attr<=0; a2b_tyf<=0; a2b_sub<=0; a2b_tile<=0; a2b_lyr<=0;
        b0_attr_r<=0; b0_tile_r<=0; b0_lyr_r<=0; b0_sub_r<=0;
        b1_attr_r<=0; b1_tile_r<=0; b1_lyr_r<=0; b1_sub_r<=0;
        skip_cnt<=0; skip_lat<=0; prev_vr1<=0;
    end else begin
        prev_lhbl <= lhbl;

        prev_vr1 <= vrender1;
        if( vrender1 < prev_vr1 ) begin
            skip_lat <= skip_cnt; skip_cnt <= 8'd0;
        end else if( prev_lhbl && !lhbl && !(pf_st==P_IDLE && fetch_libre && !av_valid
                      && cs_st==C_IDLE && !hs_valid) && skip_cnt!=8'hff ) begin
            skip_cnt <= skip_cnt + 8'd1;
        end
        if( prev_lhbl && !lhbl && pf_st==P_IDLE && fetch_libre && !av_valid
                      && cs_st==C_IDLE && !hs_valid ) begin
            dispbank <= fbank;
            fbank    <= ~fbank;
            flyr     <= 2'd0;
            ftile    <= 6'd0;
            fline    <= vrender1;
            pf_st    <= P_LSCR;
        end

        case(pf_st)
        P_IDLE:  ;

        P_LSCR:  if(lscr_on) begin vid_addr<=lscr_addr; pf_st<=P_LSCR1; end
                 else begin dx_line_en<=1'b0; pf_st<=P_SETUP; end
        P_LSCR1: pf_st<=P_LSCR2;
        P_LSCR2: begin dx_line<=vram_qvid[11:0]; dx_line_en<=1'b1; pf_st<=P_SETUP; end
        P_SETUP: begin vid_addr<=attr_addr; pf_st<=P_ATTR; end
        P_ATTR:  pf_st<=P_ATTR2;
        P_ATTR2: begin attr_p<=vram_qvid; vid_addr<=code_addr; pf_st<=P_CODE; end
        P_CODE:  pf_st<=P_CODE2;
        P_CODE2: begin code_p<=vram_qvid; pf_st<=P_DEP; end
        P_DEP:   if(!av_valid) begin

                     a2b_attr<=attr_p; a2b_code<=code_p; a2b_tyf<=tyf;
                     a2b_tile<=ftile;  a2b_lyr <=flyr;   a2b_sub<=first_sub;
                     av_valid<=1'b1;
                     if(ftile==LAST_TILE) begin
                         ftile<=6'd0;
                         if(flyr==2'd3) pf_st<=P_IDLE;
                         else begin flyr<=flyr+2'd1; pf_st<=P_LSCR; end
                     end else begin ftile<=ftile+6'd1; pf_st<=P_SETUP; end
                 end
        default: pf_st<=P_IDLE;
        endcase

        case(b0_st)
        B_IDLE:  if(av_valid && bload==1'b0) begin
                     scr_addr  <= {a2b_code, a2b_tyf};
                     scrx_addr <= {a2b_code, a2b_tyf};
                     b0_attr_r <= a2b_attr; b0_tile_r<=a2b_tile;
                     b0_lyr_r  <= a2b_lyr;  b0_sub_r <=a2b_sub;
                     av_valid  <= 1'b0;
                     bload     <= 1'b1;
                     b0_st     <= B_ROM2;
                 end
        B_ROM:   b0_st<=B_ROM2;
        B_ROM2:  b0_st<=B_ROM3;
        B_ROM3:  if(scr_ok && scrx_ok) begin
                     romdata0_p<=scr_data; romx0_p<=scrx_data; b0_st<=B_DEP;
                 end
        B_DEP:   if(!hs_valid && bdep==1'b0) begin
                     h_attr<=b0_attr_r; h_rom<=romdata0_p; h_romx<=romx0_p;
                     h_tile<=b0_tile_r; h_lyr<=b0_lyr_r;   h_sub  <=b0_sub_r;
                     hs_valid<=1'b1;
                     bdep  <=1'b1;
                     b0_st <=B_IDLE;
                 end
        default: b0_st<=B_IDLE;
        endcase
        case(b1_st)
        B_IDLE:  if(av_valid && bload==1'b1) begin
                     scrb_addr  <= {a2b_code, a2b_tyf};
                     scrxb_addr <= {a2b_code, a2b_tyf};
                     b1_attr_r  <= a2b_attr; b1_tile_r<=a2b_tile;
                     b1_lyr_r   <= a2b_lyr;  b1_sub_r <=a2b_sub;
                     av_valid   <= 1'b0;
                     bload      <= 1'b0;
                     b1_st      <= B_ROM2;
                 end
        B_ROM:   b1_st<=B_ROM2;
        B_ROM2:  b1_st<=B_ROM3;
        B_ROM3:  if(scrb_ok && scrxb_ok) begin
                     romdata1_p<=scrb_data; romx1_p<=scrxb_data; b1_st<=B_DEP;
                 end
        B_DEP:   if(!hs_valid && bdep==1'b1) begin
                     h_attr<=b1_attr_r; h_rom<=romdata1_p; h_romx<=romx1_p;
                     h_tile<=b1_tile_r; h_lyr<=b1_lyr_r;   h_sub  <=b1_sub_r;
                     hs_valid<=1'b1;
                     bdep  <=1'b0;
                     b1_st <=B_IDLE;
                 end
        default: b1_st<=B_IDLE;
        endcase

        case(cs_st)
        C_IDLE: if(hs_valid) begin
                    attr_c<=h_attr; romdata_c<=h_rom; romx_c<=h_romx;
                    wtile <=h_tile; wlyr    <=h_lyr; subc  <=h_sub;
                    fpx<=3'd0; hs_valid<=1'b0; cs_st<=C_WRITE;
                end
        C_WRITE: begin

                    if(fpx==3'd7) begin
                        if(hs_valid) begin
                            attr_c<=h_attr; romdata_c<=h_rom; romx_c<=h_romx;
                            wtile <=h_tile; wlyr    <=h_lyr; subc  <=h_sub;
                            fpx<=3'd0; hs_valid<=1'b0;
                        end else cs_st<=C_IDLE;
                    end else fpx<=fpx+3'd1;
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

assign st_dout  = debug_bus[1] ? skip_lat :
                  debug_bus[0] ? {1'b0, fbits, mmrb[2][3], cpu_bank} :
                                 {pf_st, cs_st, wlyr, hs_valid};

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

        if( mmr[5'h00][4] )
            $display("WARN %m: flip HORIZONTAL de pantalla activo (regs[0]=%02x) — NO implementado",
                     mmr[5'h00][7:0]);
    end
end
`endif

endmodule
