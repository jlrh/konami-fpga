/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 2-5-2020 */

module xexex_vtimer(
    input               clk,
    input               pxl_cen,
    input       [1:0]   vmode,
    output  reg [1:0]   vm = 0,
    output  reg [8:0]   vdump,
    output  reg [8:0]   vrender,
    output  reg [8:0]   vrender1,
    output  reg [8:0]   H,
    output  reg         LHBL,
    output  reg         LVBL,
    output  reg         HS,
    output  reg         VS
);

reg LVBL2, LVBL1;

parameter [8:0] HB_START = 9'h182,
                HB_END   = 9'h002,
                HS_START = 9'h193,
                HS_END   = HS_START+9'd27,
                H_VB     = HB_START,
                H_VNEXT  = HS_START,
                HCNT_START=9'h000,
                HCNT_END = 9'h1FF;

localparam [1:0] M_50=2'd1, M_60=2'd2;

function [8:0] v_start(input [1:0] m);
    case(m) M_50: v_start=9'h0C8; M_60: v_start=9'h0F2; default: v_start=9'h0DF; endcase
endfunction

reg [8:0] vcnt_end, vb_start, vb_end, vs_start, vs_end;

always @* begin
    case(vm)
        M_50:    begin vcnt_end=9'h1FF; vb_start=9'h1FF; vb_end=9'h0FF; vs_start=9'h0DB; vs_end=9'h0DE; end
        M_60:    begin vcnt_end=9'h1F7; vb_start=9'h1F7; vb_end=9'h107; vs_start=9'h0F5; vs_end=9'h0F8; end
        default: begin vcnt_end=9'h1FF; vb_start=9'h1FF; vb_end=9'h0FF; vs_start=9'h0EB; vs_end=9'h0F1; end
    endcase
end

`ifdef SIMULATION
initial begin
    LVBL     = 0;
    LVBL1    = LVBL;
    LVBL2    = LVBL;
    HS       = 0;
    VS       = 0;
    LHBL     = 1;
    H        = HB_START;
    vdump    = 9'h1FF;
    vrender  = vdump+1'd1;
    vrender1 = vrender+1'd1;
end
`endif

always @(posedge clk) if(pxl_cen) begin
    H <= H == HCNT_END ? HCNT_START : (H+9'd1);
end

always @(posedge clk) if(pxl_cen) begin
    if( H == H_VNEXT ) begin
        if( vrender1==vcnt_end ) begin
            vm       <= vmode;
            vrender1 <= v_start(vmode);
        end else begin
            vrender1 <= vrender1 + 9'd1;
        end
        vrender  <= vrender1;
        vdump    <= vrender;
    end
    if( H == HB_START ) begin
        LHBL <= 0;
    end else if( H == HB_END ) LHBL <= 1;
    if( H == H_VB ) begin
        { LVBL, LVBL1 } <= { LVBL1, LVBL2 };
        if( vrender1==vb_start ) LVBL2 <= 0;
        if( vrender1==vb_end   ) LVBL2 <= 1;
    end
    if (H==HS_START) begin
        HS <= 1;
    end
    if (H==HS_END) begin
        HS <= 0;
        if (vdump==vs_start) VS <= 1;
        if (vdump==vs_end  ) VS <= 0;
    end
end

endmodule
