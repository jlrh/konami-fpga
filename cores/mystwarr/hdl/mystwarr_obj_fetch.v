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
module mystwarr_obj_fetch(
    input             rst,
    input             clk,

    input             start,
    output            busy,
    output reg        row_ok,

    input      [15:0] code,
    input      [ 3:0] ysub,
    input             vflip,
    input             hflip,

    output    [79:0]  row_pen,

    output reg [18:0] obj_addr,
    output reg        obj_cs,
    input      [63:0] obj_data,
    input             obj_ok,

    output reg [18:0] objx_addr,
    output reg        objx_cs,
    input      [15:0] objx_data,
    input             objx_ok
);

localparam S_IDLE=1'b0, S_FETCH=1'b1;

reg        st;
reg [31:0] obj0, obj1;
reg [15:0] objx_r;
reg        hflip_r;
reg        obj_done, objx_done;

wire [3:0] ysubf = ysub ^ {4{vflip}};

assign busy = st != S_IDLE;

wire obj_last_ok  = obj_cs  && obj_ok;
wire objx_last_ok = objx_cs && objx_ok;
wire obj_done_now  = obj_done  || obj_last_ok;
wire objx_done_now = objx_done || objx_last_ok;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= S_IDLE; obj_cs <= 0; objx_cs <= 0; row_ok <= 0;
        obj_addr <= 0; objx_addr <= 0; obj0 <= 0; obj1 <= 0; objx_r <= 0;
        hflip_r <= 0; obj_done <= 0; objx_done <= 0;
    end else begin
        row_ok <= 0;
        case( st )
            S_IDLE: if( start ) begin
                hflip_r   <= hflip;
                obj_addr  <= { code[14:0], ysubf };
                obj_cs    <= 1;
                obj_done  <= 0;
                objx_addr <= { code[14:0], ysubf };
                objx_cs   <= 1;
                objx_done <= 0;
                st        <= S_FETCH;
            end
            S_FETCH: begin
                if( obj_last_ok ) begin
                    obj0     <= obj_data[31:0];
                    obj1     <= obj_data[63:32];
                    obj_cs   <= 0;
                    obj_done <= 1;
                end
                if( objx_last_ok ) begin
                    objx_r    <= objx_data;
                    objx_cs   <= 0;
                    objx_done <= 1;
                end
                if( obj_done_now && objx_done_now ) begin
                    row_ok <= 1;
                    st     <= S_IDLE;
                end
            end
        endcase
    end
end

function [4:0] pen_of( input [31:0] obj4, input p4, input [2:0] xs );
    reg [7:0] b0,b1,b2,b3;
    begin
        {b3,b2,b1,b0} = obj4;
        pen_of = { p4, b3[7-xs], b2[7-xs], b1[7-xs], b0[7-xs] };
    end
endfunction

genvar gx;
wire [4:0] pen_nat [0:15];
generate
    for( gx=0; gx<8; gx=gx+1 ) begin: PEN_LO
        assign pen_nat[gx]   = pen_of( obj0, objx_r[7-gx],  gx[2:0] );
        assign pen_nat[gx+8] = pen_of( obj1, objx_r[15-gx], gx[2:0] );
    end
endgenerate

wire [4:0] pen_scr [0:15];
generate
    for( gx=0; gx<16; gx=gx+1 ) begin: PEN_OUT
        assign pen_scr[gx] = hflip_r ? pen_nat[15-gx] : pen_nat[gx];
    end
endgenerate

generate
    for( gx=0; gx<16; gx=gx+1 ) begin: PACK
        assign row_pen[gx*5+:5] = pen_scr[gx];
    end
endgenerate

endmodule
