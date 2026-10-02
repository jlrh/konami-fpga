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

module mystwarr_obj_scan(
    input             rst,
    input             clk,

    output reg        done,

    output reg [15:0] code,
    output reg [ 9:0] attr,
    output            hflip,
    output reg        vflip,
    output reg [ 9:0] hpos,
    output     [ 3:0] ysub,
    output reg [11:0] hzoom,
    output reg        hz_keep,

    output reg        zfill,

    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input      [ 9:0] voffset,
    input             hs,

    input      [15:0] scan_even,
    input      [15:0] scan_odd,
    input      [ 9:0] xoffset,
    input      [ 9:0] yoffset,
    input             ghf, gvf,
    output     [ 9:0] scan_addr,

    output reg [ 1:0] shd,

    output reg        dr_start,
    input             dr_busy,

    output reg [ 7:0] dbg_nofin,
    output reg [ 7:0] dbg_worst,

    output reg [ 7:0] dbg_drcut,
    output reg [ 7:0] dbg_startmax,

    output reg [ 7:0] dbg_stallmax,

    input      [ 7:0] debug_bus
);
parameter [7:0] SCAN_START = 8'd0;
parameter [8:0] BOTTOM     = 9'h1EF;

parameter [9:0] HOFFSET    = 10'd950;

localparam [11:0] MAX_ZOOMIN= 6;

localparam [ 9:0] HDUMP_MIN = 10'h000,
                  HADJ      = 10'h008;

reg  [18:0] yz_add;
reg  [11:0] vzoom;
reg  [ 9:0] y, y2, x, ydiff, ydiff_b, xadj, yadj, x2;
reg  [ 8:0] vlatch, ymove, vscl, hscl;
reg  [ 7:0] scan_obj;
reg  [ 3:0] size;
reg  [ 2:0] hstep, hcode, hsum, vsum;
reg  [ 1:0] scan_sub, reserved;
reg         inzone, hs_l, hdone,
            vmir, hmir, sq, pre_vf, pre_hf, indr,
            hmir_eff, vmir_eff, vflip_nx, hhalf, left_wrap;

wire [ 1:0] nx_mir, hsz, vsz;
wire        last_obj;

reg  [ 8:0] zoffset [0:255];
reg  [ 3:0] pzoffset[0:15 ];
integer     missing;
reg  [ 7:0] nofin, worst;
reg  [ 7:0] drcut, startmax;
reg  [ 7:0] starts;
reg  [10:0] stall;
reg  [ 7:0] stallmax;

`ifndef SYNTHESIS

integer     dbg_inzone, dbg_stall, dbg_lines, dbg_objs, dbg_busy, dbg_starts;
integer     tot_inzone, tot_stall, tot_lines, tot_objs, tot_busy, tot_starts;
integer     dbg_skip, dbg_setup, dbg_draw, dbg_nozone, dbg_avail;
integer     tot_skip, tot_setup, tot_draw, tot_nozone, tot_avail;
`endif

assign hflip     = ghf ^ (hmir ? 1'b0 : pre_hf) ^ hmir_eff;
assign scan_addr = { scan_obj, scan_sub };
assign ysub      = ydiff[3:0];
assign last_obj  = &scan_obj[7:0];
assign nx_mir    = scan_even[15:14];
assign {vsz,hsz} = size;

always @(posedge clk) begin
    xadj <= xoffset - HOFFSET;
    yadj <= yoffset + voffset;
    vscl <= rd_pzoffset(vzoom[9:0]);
    hscl <= rd_pzoffset(hzoom[9:0]);
    ydiff_b <= y2 + { vlatch[8], vlatch };
    /* verilator lint_off WIDTH */
    yz_add  <= vzoom[9:0]*ydiff_b;
    /* verilator lint_on WIDTH */
end

function [8:0] zmove( input [1:0] sz, input[8:0] scl );
    case( sz )
        0: zmove = scl>>2;
        1: zmove = scl>>1;
        2: zmove = scl;
        3: zmove = scl<<1;
    endcase
endfunction

function [8:0] rd_pzoffset( input [9:0] zoom );
    case( zoom[9:8] )
        0:       rd_pzoffset =        zoffset[zoom[7:0]];
        1:       rd_pzoffset = {5'b0,pzoffset[zoom[7:4]]};
        2:       rd_pzoffset =  9'd3;
        3:       rd_pzoffset =  9'd2;
    endcase
endfunction

always @* begin : B
    ymove     = zmove( vsz, vscl );
    y2        = y + {1'b0,ymove};

    ydiff     = vzoom==0 ? (10'd8<<vsz) : yz_add[6+:10];
    x2        = x - zmove( hsz, hscl );
    /* verilator lint_off UNSIGNED */
    left_wrap = x2 < HDUMP_MIN;
    /* verilator lint_on UNSIGNED */

    case( vsz )
        0: vmir_eff = vmir && !ydiff[3];
        1: vmir_eff = vmir && !ydiff[4];
        2: vmir_eff = vmir && !ydiff[5];
        3: vmir_eff = vmir && !ydiff[6];
    endcase
    vflip_nx = pre_vf ^ gvf ^ vmir_eff;
    hmir_eff = hmir & hhalf;
    case( vsz )
        0: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:4]==0;
        1: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:5]==0;
        2: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:6]==0;
        3: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:7]==0;
    endcase
    if( |yz_add[17:16] ) inzone=0;
    if( vzoom==0 ) inzone=1;
    case( hsz )
        0: hdone = 1;
        1: hdone = hstep==1;
        2: hdone = hstep==3;
        3: hdone = hstep==7;
    endcase
    if( hzoom==0 ) hdone = 1;
    case( hsz )
        0: hsum = 0;
        1: hsum = hmir ? 3'd0                           : {2'd0,hstep[0]^hflip};
        2: hsum = hmir ? {2'd0,hstep[0]^hflip}          : {1'd0,hstep[1:0]^{2{hflip}}};
        3: hsum = hmir ? ({1'b0,hstep[1:0]^{2{hflip}}}) : hstep[2:0]^{3{hflip}};
    endcase

    case( vsz )
        0: vsum = 0;
        1: vsum = { 2'd0, ydiff[4]^vflip_nx   };
        2: vsum = { 1'd0, ydiff[5:4]^{2{vflip_nx}} };
        3: vsum = ydiff[6:4]^{3{vflip_nx}};
    endcase
end

(* direct_enable *) reg cen2_div=0;
wire cen2 = cen2_div;
always @(negedge clk) cen2_div <= ~cen2_div;

always @(posedge clk) begin : A
    if( rst ) begin
        nofin        <= 0;
        worst        <= 8'hff;
        drcut        <= 0;
        startmax     <= 0;
        starts       <= 0;
        stall        <= 0;
        stallmax     <= 0;
        dbg_stallmax <= 0;
        dbg_nofin    <= 0;
        dbg_worst    <= 8'hff;
        dbg_drcut    <= 0;
        dbg_startmax <= 0;
        hs_l     <= 0;
        scan_obj <= 0;
        scan_sub <= 0;
        hstep    <= 0;
        code     <= 0;
        attr     <= 0;
        pre_vf   <= 0;
        pre_hf   <= 0;
        vflip    <= 0;
        vzoom    <= 0;
        hzoom    <= 0;
        hz_keep  <= 0;
        zfill    <= 0;
        indr     <= 0;
        hhalf    <= 0;
        shd      <= 0;
        done     <= 0;
    end else if( cen2 ) begin
        hs_l <= hs;
`ifndef SYNTHESIS
        if( dr_busy  ) dbg_busy   <= dbg_busy + 1;
        if( dr_start ) dbg_starts <= dbg_starts + 1;
        dbg_avail <= dbg_avail + 1;
`endif

        if( dr_start && starts != 8'hff ) starts <= starts + 8'd1;
        dr_start <= 0;
        if( hs && !hs_l && vdump>9'h10D && vdump<=BOTTOM) begin
`ifndef SYNTHESIS
            if( scan_obj!=0 ) begin
                tot_inzone <= tot_inzone + dbg_inzone; tot_stall <= tot_stall + dbg_stall;
                tot_objs   <= tot_objs   + dbg_objs;   tot_lines <= tot_lines + 1;
                tot_busy   <= tot_busy   + dbg_busy;   tot_starts<= tot_starts + dbg_starts;
                tot_skip   <= tot_skip   + dbg_skip;   tot_setup <= tot_setup + dbg_setup;
                tot_draw   <= tot_draw   + dbg_draw;   tot_nozone<= tot_nozone+ dbg_nozone;
                tot_avail  <= tot_avail  + dbg_avail;
            end
            dbg_inzone <= 0; dbg_stall <= 0; dbg_objs <= 0; dbg_lines <= dbg_lines + 1;
            dbg_busy <= 0; dbg_starts <= 0;
            dbg_skip <= 0; dbg_setup <= 0; dbg_draw <= 0; dbg_nozone <= 0; dbg_avail <= 0;
`endif
            done     <= 0;
            scan_obj <= SCAN_START;
            scan_sub <= 0;
            indr     <= 0;
            vlatch   <= vdump;
            if( scan_obj!=0 ) begin
                $display("[MYSTWARR] Obj scan did not finish. Last obj %X",scan_obj);
                missing <= missing + 1;

                if( nofin != 8'hff ) nofin <= nofin + 8'd1;
                if( scan_obj[7:0] < worst ) worst <= scan_obj[7:0];
            end

            if( dr_busy && drcut != 8'hff ) drcut <= drcut + 8'd1;
            if( starts > startmax ) startmax <= starts;
            starts <= 0;
            if( stall[10:3] > stallmax ) stallmax <= stall[10:3];
            stall <= 0;

            if( vdump==BOTTOM ) begin
                dbg_nofin    <= nofin;
                dbg_worst    <= worst;
                dbg_drcut    <= drcut;
                dbg_startmax <= startmax;
                dbg_stallmax <= stallmax;
                stallmax     <= 0;
                nofin        <= 0;
                worst        <= 8'hff;
                drcut        <= 0;
                startmax     <= 0;
            end
            if(vdump==BOTTOM && missing!=0 ) begin
                missing <= 0;
                $display("%d uncompleted lines",missing);
`ifndef SYNTHESIS
                if( tot_lines>0 )
                    $display("[MYSTWARR] presupuesto/linea: objetos=%0d en_zona=%0d ciclos_parado_por_dr_busy=%0d (media de %0d lineas)",
                        tot_objs/tot_lines, tot_inzone/tot_lines, tot_stall/tot_lines, tot_lines);
                if( tot_starts>0 )
                    $display("[MYSTWARR] dibujante: enviados/linea=%0d  ocupado/linea=%0d cen2  => %0d cen2 POR OBJETO",
                        tot_starts/tot_lines, tot_busy/tot_lines, tot_busy/tot_starts);
                if( tot_lines>0 )
                    $display("[MYSTWARR] reparto pasos/linea: skip(obj inactivo)=%0d setup=%0d draw+espera=%0d (fuera_de_zona=%0d) TOTAL=%0d de %0d disponibles",
                        tot_skip/tot_lines, tot_setup/tot_lines, tot_draw/tot_lines, tot_nozone/tot_lines,
                        (tot_skip+tot_setup+tot_draw)/tot_lines, tot_avail/tot_lines);
                tot_objs<=0; tot_inzone<=0; tot_stall<=0; tot_lines<=0; tot_busy<=0; tot_starts<=0;
                tot_skip<=0; tot_setup<=0; tot_draw<=0; tot_nozone<=0; tot_avail<=0;
`endif
            end
        end else if( !done ) begin
`ifndef SYNTHESIS
            if( {indr,scan_sub}>=3'd5 )          dbg_draw  <= dbg_draw  + 1;
            else if( {indr,scan_sub}==0 )
                if( !scan_even[15] )             dbg_skip  <= dbg_skip  + 1;
                else                             dbg_setup <= dbg_setup + 1;
            else begin                           dbg_setup <= dbg_setup + 1;
                if( {indr,scan_sub}==3'd4 && ~inzone ) dbg_nozone <= dbg_nozone + 1;
            end
`endif
            {indr, scan_sub} <= {indr, scan_sub} + 1'd1;
            case( {indr, scan_sub} )
                0: begin
                    hhalf <= 0;
                    { sq, pre_vf, pre_hf, size } <= scan_even[14:8];
                    code    <= scan_odd;
                    hstep   <= 0;
                    hz_keep <= 0;
                    if( !scan_even[15] ) begin
                        scan_sub <= 0;
                        scan_obj <= scan_obj + 1'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                1: begin
                    y <= gvf ? -scan_even[9:0] : scan_even[9:0];
                    x <= ghf ? -scan_odd[ 9:0] : scan_odd[ 9:0];
                    hcode <= {code[4],code[2],code[0]};
                    hstep <= 0;
                end
                2: begin
                    x <= x-xadj;
                    y <= y+yadj;
                    vzoom <= {2'b0, scan_even[9:0]};
                    hzoom <= sq ? {2'b0, scan_even[9:0]} : {2'b0, scan_odd[9:0]};
                end
                3: begin
                    { vmir, hmir } <= nx_mir;
                    { reserved, shd, attr } <= scan_even[13:0];

                    zfill <= hzoom==0;

                    if( hzoom==0 ) begin
                        case( hsz )
                            0: hstep <= 3'd0;
                            1: hstep <= 3'd1;
                            2: hstep <= 3'd2;
                            3: hstep <= 3'd4;
                        endcase
                        hhalf <= hsz!=0;
                    end
                    if( hzoom!=0 && hzoom < MAX_ZOOMIN ) begin
                        { indr, scan_sub } <= 0;
                        scan_obj <= scan_obj + 1'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                4: begin
                    vflip <= vflip_nx;
                    {code[5],code[3],code[1]} <= {code[5],code[3],code[1]} + vsum;
                    if( ~inzone ) begin
                        { indr, scan_sub } <= 0;
                        scan_obj <= scan_obj + 1'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                default: begin
                    case( hsz )
                        1: if(hstep>=1) hhalf <= 1;
                        2: if(hstep>=2) hhalf <= 1;
                        3: if(hstep>=4) hhalf <= 1;
                    endcase
                    {indr, scan_sub} <= 5;
`ifndef SYNTHESIS
                    if( !((!dr_start && !dr_busy) || !inzone) ) dbg_stall <= dbg_stall + 1;
`endif

                    if( !((!dr_start && !dr_busy) || !inzone) ) stall <= stall + 11'd1;
                    if( (!dr_start && !dr_busy) || !inzone ) begin
                        {code[4],code[2],code[0]} <= hcode + hsum;
                        if( zfill ) begin

                            hpos    <= 0;
                            hz_keep <= 0;
                        end else if( hstep==0 ) begin
                            hpos    <= x2 + (left_wrap ? HADJ : 10'b0 );
                        end else begin
                            hpos    <= hpos + 10'h10;
                            hz_keep <= 1;
                        end
                        hstep <= hstep + 1'd1;
                        dr_start <= inzone;
                        if( hdone || !inzone ) begin
`ifndef SYNTHESIS
                            dbg_objs <= dbg_objs + 1;
                            if( inzone ) dbg_inzone <= dbg_inzone + 1;
`endif
                            { indr, scan_sub } <= 0;
                            scan_obj <= scan_obj + 1'd1;
                            indr     <= 0;
                            if( last_obj ) done <= 1;
                        end
                    end
                end
            endcase
        end
    end
end

initial pzoffset ='{
    8, 7, 7, 6, 6, 6, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4
};

initial zoffset ='{
    511, 511, 511, 511, 511, 410, 341, 293,
    256, 228, 205, 186, 171, 158, 146, 137,
    128, 120, 114, 108, 102,  98,  93,  89,
     85,  82,  79,  76,  73,  71,  68,  66,
     64,  62,  60,  59,  57,  55,  54,  53,
     51,  50,  49,  48,  47,  46,  45,  44,
     43,  42,  41,  40,  39,  39,  38,  37,
     37,  36,  35,  35,  34,  34,  33,  33,
     32,  32,  31,  31,  30,  30,  29,  29,
     28,  28,  28,  27,  27,  27,  26,  26,
     26,  25,  25,  25,  24,  24,  24,  24,
     23,  23,  23,  23,  22,  22,  22,  22,
     21,  21,  21,  21,  20,  20,  20,  20,
     20,  20,  19,  19,  19,  19,  19,  18,
     18,  18,  18,  18,  18,  18,  17,  17,
     17,  17,  17,  17,  17,  16,  16,  16,
     16,  16,  16,  16,  16,  15,  15,  15,
     15,  15,  15,  15,  15,  15,  14,  14,
     14,  14,  14,  14,  14,  14,  14,  14,
     13,  13,  13,  13,  13,  13,  13,  13,
     13,  13,  13,  13,  12,  12,  12,  12,
     12,  12,  12,  12,  12,  12,  12,  12,
     12,  12,  12,  11,  11,  11,  11,  11,
     11,  11,  11,  11,  11,  11,  11,  11,
     11,  11,  11,  11,  10,  10,  10,  10,
     10,  10,  10,  10,  10,  10,  10,  10,
     10,  10,  10,  10,  10,  10,  10,  10,
      9,   9,   9,   9,   9,   9,   9,   9,
      9,   9,   9,   9,   9,   9,   9,   9,
      9,   9,   9,   9,   9,   9,   9,   9,
      9,   8,   8,   8,   8,   8,   8,   8,
      8,   8,   8,   8,   8,   8,   8,   8
};

endmodule
