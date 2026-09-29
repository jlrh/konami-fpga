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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 30-7-2023 */

module k053246(
    input             rst,
    input             clk,
    input             pxl2_cen,
    input             pxl_cen,
    input             simson,

    output            ln_done,

    input             cs,
    input             cpu_we,
    input      [ 3:0] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,

    output     [22:1] rmrd_addr,

    output     [13:1] dma_addr,
    input      [15:0] dma_data,
    output            dma_bsy,

    output reg [15:0] code,

    output reg [ 9:0] attr,
    output            hflip,
    output reg        vflip,
    output reg [ 9:0] hpos,
    output     [ 3:0] ysub,
    output reg [11:0] hzoom,
    output reg        hz_keep,

    input      [ 8:0] hdump,
    input      [ 8:0] vdump,

    input      [ 9:0] voffset,
    input             lvbl,
    input             hs,

    input      [ 8:0] pxl,
    output reg [ 1:0] shd,

    output reg        dr_start,
    input             dr_busy,

    input      [ 7:0] debug_bus,
    input      [ 7:0] st_addr,
    output     [ 7:0] st_dout
);
parameter       K55673=0, K55673_DESC_SORT=0, EDGE_TRIGGER=0;
parameter [9:0] HOFFSET   = 10'd62;

localparam [2:0] REG_XOFF  = 0,
                 REG_YOFF  = 1,
                 REG_CFG   = 2;

localparam [7:0] SCAN_START = K55673==1 ? 8'h40 : 8'h0;

wire [15:0] scan_even, scan_odd, dma_din;
wire [11:2] scan_addr;
wire [11:1] dma_wr_addr;
wire [ 9:0] xoffset, yoffset;
wire [ 7:0] cfg;
wire        dma_wel, dma_weh, cpu_bsy,
            ghf, gvf, mode8, dma_en, flicker;

assign ghf       = cfg[0];
assign gvf       = cfg[1];
assign mode8     = cfg[2];
assign cpu_bsy   = cfg[3];
assign dma_en    = cfg[4];

k053246_scan #(.HOFFSET(HOFFSET),.SCAN_START(SCAN_START)) u_scan(
    .rst       ( rst        ),
    .clk       ( clk        ),
    .done      ( ln_done    ),
    .code      ( code       ),
    .attr      ( attr       ),
    .hflip     ( hflip      ),
    .vflip     ( vflip      ),
    .hpos      ( hpos       ),
    .ysub      ( ysub       ),
    .hzoom     ( hzoom      ),
    .hz_keep   ( hz_keep    ),
    .hdump     ( hdump      ),
    .vdump     ( vdump      ),
    .voffset   ( voffset    ),
    .hs        ( hs         ),
    .scan_even ( scan_even  ),
    .scan_odd  ( scan_odd   ),
    .xoffset   ( xoffset    ),
    .yoffset   ( yoffset    ),
    .ghf       ( ghf        ),
    .gvf       ( gvf        ),
    .scan_addr ( scan_addr  ),
    .shd       ( shd        ),
    .dr_start  ( dr_start   ),
    .dr_busy   ( dr_busy    ),
    .debug_bus ( debug_bus  )
);

k053246_dma #(
    .K55673          ( K55673           ),
    .K55673_DESC_SORT( K55673_DESC_SORT ),
    .EDGE_TRIGGER    ( EDGE_TRIGGER     )
)u_dma(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),

    .mode8      ( mode8     ),
    .dma_en     ( dma_en    ),
    .dma_trig   ( 1'b0      ),
    .k44_en     ( 1'b0      ),
    .simson     ( simson    ),

    .hs         ( hs        ),
    .lvbl       ( lvbl      ),

    .dma_addr   ( dma_addr  ),
    .dma_data   ( dma_data  ),
    .dma_bsy    ( dma_bsy   ),

    .dma_weh    ( dma_weh   ),
    .dma_wel    ( dma_wel   ),
    .dma_wr_addr(dma_wr_addr),
    .dma_din    ( dma_din   ),

    .flicker    ( flicker   )
);

k053246_mmr u_mmr(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .k44_en     ( 1'b0      ),
    .cs         ( cs        ),
    .cpu_we     ( cpu_we    ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cfg        ( cfg       ),
    .xoffset    ( xoffset   ),
    .yoffset    ( yoffset   ),
    .rmrd_addr  ( rmrd_addr ),
    .st_addr    ( st_addr   ),
    .st_dout    ( st_dout   )
);

jtframe_dual_ram16 #(.AW(10)) u_even(

    .clk0   ( clk            ),
    .data0  ( dma_din        ),
    .addr0  (dma_wr_addr[11:2]),
    .we0    ( {2{dma_wel}}   ),
    .q0     (                ),

    .clk1   ( clk            ),
    .data1  ( 16'd0          ),
    .addr1  ( scan_addr      ),
    .we1    ( 2'b0           ),
    .q1     ( scan_even      )
);

jtframe_dual_ram16 #(.AW(10)) u_odd(

    .clk0   ( clk            ),
    .data0  ( dma_din        ),
    .addr0  (dma_wr_addr[11:2]),
    .we0    ( {2{dma_weh}}   ),
    .q0     (                ),

    .clk1   ( clk            ),
    .data1  ( 16'd0          ),
    .addr1  ( scan_addr      ),
    .we1    ( 2'b0           ),
    .q1     ( scan_odd       )
);

endmodule
