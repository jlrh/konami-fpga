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
module mystwarr_obj_bank3 #(parameter
    SDRAMW = 22,
    OBJX_OFFSET = 22'd0
)(
    input               rst,
    input               clk,

    input      [18:0]  obj_addr,
    output     [63:0]  obj_dout,
    input               obj_cs,
    output              obj_ok,

    input      [18:0]  objx_addr,
    output     [15:0]  objx_dout,
    input               objx_cs,
    output              objx_ok,

    input               sdram_ack,
    output              sdram_rd,
    output [SDRAMW-1:0] sdram_addr,
    input                data_dst,
    input                data_rdy,
    input       [15:0]   data_read
);

localparam SW = 2;

wire [SW-1:0] req, ok, slot_sel;
wire [SDRAMW-1:0] slot0_addr_req, slot1_addr_req;

assign obj_ok  = ok[0];
assign objx_ok = ok[1];

mystwarr_obj_bcache64 #(
    .SDRAMW ( SDRAMW ),
    .AW     ( 19     ),
    .DW     ( 64     )
) u_slot0(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .offset     ( {SDRAMW{1'b0}} ),
    .din        ( data_read      ),
    .din_ok     ( data_rdy       ),
    .dst        ( data_dst       ),
    .we         ( slot_sel[0]    ),
    .req        ( req[0]         ),
    .sdram_addr ( slot0_addr_req ),
    .addr       ( obj_addr       ),
    .addr_ok    ( obj_cs         ),
    .data_ok    ( ok[0]          ),
    .dout       ( obj_dout       )
);

jtframe_romrq #(
    .SDRAMW  ( SDRAMW      ),
    .AW      ( 19          ),
    .DW      ( 16          ),
    .OKLATCH ( 0           )
) u_slot1(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .clr        ( 1'b0             ),
    .offset     ( OBJX_OFFSET[SDRAMW-1:0] ),
    .din        ( data_read        ),
    .din_ok     ( data_rdy         ),
    .dst        ( data_dst         ),
    .we         ( slot_sel[1]      ),
    .req        ( req[1]           ),
    .sdram_addr ( slot1_addr_req   ),
    .addr       ( objx_addr        ),
    .addr_ok    ( objx_cs          ),
    .data_ok    ( ok[1]            ),
    .dout       ( objx_dout        )
);

jtframe_ramslot_ctrl #(
    .SDRAMW ( SDRAMW ),
    .SW     ( SW     ),
    .WRSW   ( 0      )
) u_ctrl(
    .rst            ( rst        ),
    .clk            ( clk        ),
    .req            ( req        ),
    .slot_addr_req  ({slot1_addr_req, slot0_addr_req}),
    .slot_sel       ( slot_sel   ),
    .sdram_ack      ( sdram_ack  ),
    .sdram_rd       ( sdram_rd   ),
    .sdram_addr     ( sdram_addr ),
    .data_rdy       ( data_rdy   ),
    .erase_bsy      ( 1'b0       ),
    .req_rnw        ( 1'b1       ),
    .slot_din       ( 16'd0      ),
    .wrmask         ( 2'd0       ),
    .sdram_wr       (            ),
    .data_write     (            ),
    .sdram_wrmask   (            )
);

endmodule
