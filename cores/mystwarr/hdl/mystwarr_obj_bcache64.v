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
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.  */
module mystwarr_obj_bcache64 #(parameter
    SDRAMW = 22,
    AW     = 19,
    DW     = 64
)(
    input               rst,
    input               clk,

    input [SDRAMW-1:0]  offset,

    input  [15:0]        din,
    input                din_ok,
    input                dst,
    input                we,
    output               req,
    output [SDRAMW-1:0]  sdram_addr,

    input  [AW-1:0]      addr,
    input                addr_ok,
    output               data_ok,
    output [DW-1:0]      dout
);

reg [AW-1:0] cached_addr;
reg [DW-1:0] cached_data;
reg          good;
reg          cap_run;
reg  [1:0]   wc;

wire hit = good && (cached_addr === addr);

assign req        = !hit && addr_ok;
assign data_ok    = addr_ok && hit;
assign sdram_addr = offset + { {(SDRAMW-AW-2){1'b0}}, addr, 2'b00 };
assign dout       = cached_data;

wire capturing = (we & dst) | cap_run;

always @(posedge clk) begin
    if( rst ) begin
        good <= 0; cap_run <= 0; wc <= 0; cached_data <= 0; cached_addr <= 0;
    end else begin
        if( capturing ) cached_data <= { din, cached_data[DW-1:16] };

        if( we & dst ) begin
            good        <= 0;
            cap_run     <= 1;
            wc          <= 2'd1;
            cached_addr <= addr;
        end else if( cap_run ) begin
            wc <= wc + 2'd1;
            if( wc == 2'd3 ) begin
                cap_run <= 0;
                good    <= 1;
            end
        end
    end
end

`ifdef SIMULATION
`ifndef VERILATOR
`ifndef JTFRAME_SIM_ROMRQ_NOCHECK
reg waiting, last_req;
always @(posedge clk) begin
    if( rst ) begin waiting<=0; last_req<=0; end else begin
        last_req <= req;
        if( req && !last_req ) begin
            if( waiting ) begin $display("ERROR: %m new request without finishing the previous"); $finish; end
            waiting <= 1;
        end
        if( we & dst ) waiting <= 0;
        if( waiting && !addr_ok ) begin $display("ERROR: %m address changed at time %t",$time); $finish; end
    end
end
`endif
`endif
`endif

wire _unused = &{1'b0, din_ok, 1'b0};

endmodule
