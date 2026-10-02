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

module mtlchamp_obj_fetch2(
    input             rst,
    input             clk,

    input             start,
    output            busy,
    output reg        row_ok,
    output            envuelo,

    input      [15:0] code,
    input      [ 3:0] ysub,
    input             vflip,
    input             hflip,

    output    [79:0]  row_pen,

    output reg [20:0] obj_addr,
    output reg        obj_cs,
    input      [31:0] obj_data,
    input             obj_ok,

    output reg [20:0] objb_addr,
    output reg        objb_cs,
    input      [31:0] objb_data,
    input             objb_ok,

    output reg [19:0] objx_addr,
    output reg        objx_cs,
    input      [15:0] objx_data,
    input             objx_ok,

    output reg [20:0] objc_addr,
    output reg        objc_cs,
    input      [31:0] objc_data,
    input             objc_ok,

    output reg [20:0] objd_addr,
    output reg        objd_cs,
    input      [31:0] objd_data,
    input             objd_ok,

    output reg [19:0] objxb_addr,
    output reg        objxb_cs,
    input      [15:0] objxb_data,
    input             objxb_ok
);

reg  [1:0] ocup;
reg        wr, rd;
reg  [1:0] hflip_ctx;

reg [31:0] obj0, obj1;
reg [15:0] objx_r;
reg        hflip_r;

wire [3:0] ysubf = ysub ^ {4{vflip}};

wire ok_ctx0 = obj_ok  & objb_ok & objx_ok;
wire ok_ctx1 = objc_ok & objd_ok & objxb_ok;
wire ok_rd   = rd ? ok_ctx1 : ok_ctx0;

assign busy    = ocup[wr];
assign envuelo = |ocup;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        ocup <= 2'b00; wr <= 0; rd <= 0; row_ok <= 0; hflip_ctx <= 0;
        obj_cs <= 0; objb_cs <= 0; objx_cs  <= 0;
        objc_cs<= 0; objd_cs <= 0; objxb_cs <= 0;
        obj_addr <= 0; objb_addr <= 0; objx_addr  <= 0;
        objc_addr<= 0; objd_addr<= 0; objxb_addr <= 0;
        obj0 <= 0; obj1 <= 0; objx_r <= 0; hflip_r <= 0;
    end else begin
        row_ok <= 0;

        if( ocup[rd] && ok_rd ) begin
            if( !rd ) begin
                obj0 <= obj_data;  obj1 <= objb_data; objx_r <= objx_data;
                obj_cs <= 0; objb_cs <= 0; objx_cs <= 0;
            end else begin
                obj0 <= objc_data; obj1 <= objd_data; objx_r <= objxb_data;
                objc_cs <= 0; objd_cs <= 0; objxb_cs <= 0;
            end
            hflip_r   <= hflip_ctx[rd];
            ocup[rd]  <= 1'b0;
            rd        <= ~rd;
            row_ok    <= 1'b1;
        end

        if( start && !ocup[wr] ) begin
            hflip_ctx[wr] <= hflip;
            if( !wr ) begin
                obj_addr  <= { code, ysubf, 1'b0 };
                objb_addr <= { code, ysubf, 1'b1 };
                objx_addr <= { code, ysubf };
                obj_cs <= 1; objb_cs <= 1; objx_cs <= 1;
            end else begin
                objc_addr  <= { code, ysubf, 1'b0 };
                objd_addr  <= { code, ysubf, 1'b1 };
                objxb_addr <= { code, ysubf };
                objc_cs <= 1; objd_cs <= 1; objxb_cs <= 1;
            end
            ocup[wr] <= 1'b1;
            wr       <= ~wr;
        end
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
