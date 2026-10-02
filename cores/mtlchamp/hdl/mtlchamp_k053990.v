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

module mtlchamp_k053990(
    input               rst,
    input               clk,
    input               cen,

    input               cs,
    input               we,
    input        [ 4:1] addr,
    input        [15:0] din,
    input        [ 1:0] dsn,

    output reg          busy,
    output reg          bus_req,
    output reg          bus_we,
    output reg   [23:1] bus_addr,
    output reg   [ 1:0] bus_dsn,
    output reg   [15:0] bus_dout,
    input        [15:0] bus_din,
    input               bus_ok
);

reg [15:0] mmr[0:15];
integer    i;

wire [15:0] wmask = { {8{~dsn[1]}}, {8{~dsn[0]}} };

wire        trigger = cs & we & (addr==4'hc) & ~dsn[1];

wire [15:0] mode = { mmr[13][7:0], mmr[15][7:0] };

localparam [15:0] MODE_COPY_BYTE = 16'hff00,
                  MODE_COPY_WORD = 16'hffff,
                  MODE_SPR_LIST  = 16'h00ff;

reg [23:0] src, dst, mdp;
reg [15:0] sskip, dskip, mskip;
reg [ 8:0] cnt;
reg        wide;
reg        listmode;
reg [15:0] acc;

localparam [3:0] ST_IDLE=0, ST_MOD=1, ST_MOD_W=2, ST_SRC=3, ST_SRC_W=4,
                 ST_DST=5, ST_DST_W=6, ST_NEXT=7;
reg [3:0] st;

function [1:0] dsn_of; input a0; input w;
    dsn_of = w ? 2'b00 : (a0 ? 2'b10 : 2'b01);
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        busy <= 0; bus_req <= 0; bus_we <= 0; st <= ST_IDLE;
        bus_addr <= 0; bus_dsn <= 2'b11; bus_dout <= 0;
        src <= 0; dst <= 0; mdp <= 0; cnt <= 0;
        sskip <= 0; dskip <= 0; mskip <= 0; wide <= 0; listmode <= 0; acc <= 0;
        for( i=0; i<16; i=i+1 ) mmr[i] <= 0;
    end else begin

        if( cs & we ) mmr[addr] <= (mmr[addr] & ~wmask) | (din & wmask);

        case( st )
        ST_IDLE: begin
            bus_req <= 0; bus_we <= 0; busy <= 0;
            if( trigger ) begin

                src <= { mmr[ 1][7:0], mmr[ 0] };
                dst <= { mmr[ 3][7:0], mmr[ 2] };
                mdp <= { mmr[ 5][7:0], mmr[ 4] };
                case( mode )
                MODE_COPY_BYTE, MODE_COPY_WORD: begin
                    listmode <= 0;
                    wide     <= mode==MODE_COPY_WORD;

                    cnt      <= mmr[8][15:8]==0 ? 9'd0 :
                                ( mmr[8][7:0]==8'd2 ? {mmr[8][15:8],1'b0} : {1'b0,mmr[8][15:8]} );

                    sskip    <= { 8'd0, mmr[10][7:0] } + (mode==MODE_COPY_WORD ? 16'd2 : 16'd1);
                    dskip    <= { 8'd0, mmr[11][7:0] } + (mode==MODE_COPY_WORD ? 16'd2 : 16'd1);
                    busy     <= 1;
                    st       <= ST_SRC;
                end
                MODE_SPR_LIST: begin
                    listmode <= 1;
                    wide     <= 1;
                    cnt      <= 9'd256;

                    sskip    <= { 8'd0, mmr[ 1][15:8] };
                    dskip    <= { 8'd0, mmr[ 3][15:8] };
                    mskip    <= { 8'd0, mmr[ 5][15:8] };

                    src      <= { mmr[1][7:0], mmr[0] } + { 15'd0, mmr[8][7:0], 1'b0 };
                    dst      <= { mmr[3][7:0], mmr[2] } + { 15'd0, mmr[8][7:0], 1'b0 };
                    busy     <= 1;
                    st       <= ST_MOD;
                end
                default: st <= ST_IDLE;
                endcase
            end
        end

        ST_MOD: begin
            bus_addr <= mdp[23:1]; bus_dsn <= 2'b00; bus_we <= 0; bus_req <= 1;
            st <= ST_MOD_W;
        end
        ST_MOD_W: if( bus_ok ) begin
            acc <= bus_din;
            mdp <= mdp + { 8'd0, mskip };
            bus_req <= 0;
            st <= ST_SRC;
        end

        ST_SRC: begin
            bus_addr <= src[23:1]; bus_dsn <= dsn_of(src[0], wide); bus_we <= 0; bus_req <= 1;
            st <= ST_SRC_W;
        end
        ST_SRC_W: if( bus_ok ) begin

            acc <= listmode ? (bus_din + acc) :
                   wide     ?  bus_din        :
                   ( src[0] ? {8'd0, bus_din[7:0]} : {8'd0, bus_din[15:8]} );
            src <= src + { 8'd0, sskip };
            bus_req <= 0;
            st <= ST_DST;
        end

        ST_DST: begin
            bus_addr <= dst[23:1];
            bus_dsn  <= dsn_of(dst[0], wide);

            bus_dout <= wide ? acc : { acc[7:0], acc[7:0] };
            bus_we   <= 1; bus_req <= 1;
            st <= ST_DST_W;
        end
        ST_DST_W: if( bus_ok ) begin
            dst <= dst + { 8'd0, dskip };
            bus_req <= 0; bus_we <= 0;
            st <= ST_NEXT;
        end
        ST_NEXT: begin
            cnt <= cnt - 9'd1;
            st  <= (cnt<=9'd1) ? ST_IDLE : (listmode ? ST_MOD : ST_SRC);
        end
        default: st <= ST_IDLE;
        endcase
    end
end

endmodule
