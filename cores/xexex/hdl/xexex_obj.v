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
    Date: 24-7-2023 */

module xexex_obj #(parameter
    RAMW      = 12,
    PACKED    = 1,
    SHADOW    = 0,
    K55673    = 0,

    K55673_DESC_SORT = 0,

    EDGE_TRIGGER = 0,
    parameter [9:0] HOFFSET   = 10'd62
)(
    input             rst,
    input             clk,
    output            ln_done,

    input             pxl_cen,
    input             pxl2_cen,
    input             simson,
    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input      [ 9:0] voffset,
    input             hs,
    input             lvbl,

    input             ram_cs,
    input             reg_cs,
    input             mmr_we,
    input      [ 3:0] mmr_addr,
    input      [15:0] mmr_din,
    input      [ 1:0] mmr_dsn,

    input      [15:0] ram_din,
    input      [ 1:0] ram_we,
    input    [RAMW:1] ram_addr,
    output     [15:0] cpu_din,
    output            dma_bsy,

    output     [22:2] rom_addr,
    input      [31:0] rom_data,
    output            rom_cs,
    input             rom_ok,
    input             objcha_n,

    output     [ 1:0] shd,
    output     [ 4:0] prio,
    output     [ 8:0] pxl,

    input      [ 3:0] gfx_en,
    input             ioctl_ram,
    input      [13:0] ioctl_addr,
    output     [ 7:0] dump_ram,
    output     [ 7:0] dump_reg,
    input      [ 7:0] debug_bus
);

localparam SHADOW_PEN = SHADOW[0]==1 ? 4'd15 : 4'd0;

wire [ 1:0] pre_shd;
wire [ 3:0] pen_eff;
wire [15:0] ram_data, dma_data;
wire [22:2] pre_addr;
wire [22:1] rmrd_addr;
wire [13:1] dma_addr;
wire [15:0] pre_pxl;

wire        dr_start, dr_busy;
wire [15:0] code;
wire [ 9:0] attr;
wire        hflip, vflip, hz_keep, pre_cs;
wire [ 9:0] hpos;
wire [ 3:0] ysub;
wire [11:0] hzoom;
wire [31:0] sorted, sort_packed, sort_unpacked;
wire        pen15;

wire scr_hflip, scr_vflip;

assign rom_cs    = ~objcha_n | pre_cs;
assign rom_addr  = !objcha_n ? rmrd_addr[22:2] :
    { pre_addr[22:7], pre_addr[5:2], pre_addr[6] };

assign cpu_din   = !objcha_n ? rmrd_addr[1] ? rom_data[31:16] : rom_data[15:0] :
                    ram_data;

assign pen15   = &pre_pxl[3:0];
assign pen_eff = (pre_pxl[15:14]==0 || !pen15) ? pre_pxl[3:0] : 4'd0;
assign shd     =  pre_pxl[15:14];
assign prio    =  pre_pxl[13:9];
assign pxl     =  gfx_en[3] ? {pre_pxl[8:4], pen_eff} : 9'd0;

jtframe_8x8x4_packed_msb u_packed(rom_data, sort_packed);

assign sorted = PACKED==1 ? sort_packed : rom_data;

k053246 #(
    .K55673          ( K55673           ),
    .K55673_DESC_SORT( K55673_DESC_SORT ),
    .EDGE_TRIGGER    ( EDGE_TRIGGER     ),
    .HOFFSET         ( HOFFSET          )
) u_scan (
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),
    .pxl_cen    ( pxl_cen   ),
    .simson     ( simson    ),

    .ln_done    ( ln_done   ),
    .voffset    ( voffset   ),

    .cs         ( reg_cs    ),
    .cpu_we     ( mmr_we    ),
    .cpu_addr   ( mmr_addr  ),
    .cpu_dout   ( mmr_din   ),
    .cpu_dsn    ( mmr_dsn   ),
    .rmrd_addr  ( rmrd_addr ),

    .dma_addr   ( dma_addr  ),
    .dma_data   ( dma_data  ),
    .dma_bsy    ( dma_bsy   ),

    .code       ( code      ),
    .attr       ( attr      ),
    .hflip      ( hflip     ),
    .vflip      ( vflip     ),
    .hpos       ( hpos      ),
    .ysub       ( ysub      ),
    .hzoom      ( hzoom     ),
    .hz_keep    ( hz_keep   ),

    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),

    .pxl        ( pxl       ),
    .shd        ( pre_shd   ),

    .dr_start   ( dr_start  ),
    .dr_busy    ( dr_busy   ),

    .debug_bus  ( debug_bus ),
    .st_addr    ( ioctl_ram ? ioctl_addr[7:0] : debug_bus ),
    .st_dout    ( dump_reg  )
);

k053247 #(
    .SHADOW(SHADOW),.SHADOW_PEN(SHADOW_PEN),
    .AW(10),.CW(16),.PW(4+10+2),.LATCH(1),.SWAPH(1),
    .ZW(12),.ZI(6), .ZENLARGE(1),.SW(2),.FLIP_OFFSET(9'h12)
) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( {1'b0,hdump}  ),

    .draw       ( dr_start      ),
    .busy       ( dr_busy       ),
    .code       ( code          ),
    .xpos       ( hpos          ),
    .ysub       ( ysub          ),
    .hz_keep    ( hz_keep       ),
    .hzoom      ( hzoom         ),

    .hflip      ( ~hflip        ),
    .vflip      ( vflip         ),
    .pal        ({pre_shd, attr}),

    .rom_addr   ( pre_addr      ),
    .rom_cs     ( pre_cs        ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( sorted        ),

    .pxl        ( pre_pxl       )
);

jtframe_dual_nvram16 #(
    .AW     ( RAMW    ),
    .SIMFILE("obj.bin")
) u_ram(

    .clk0   ( clk       ),
    .data0  ( ram_din   ),
    .addr0  ( ram_addr  ),
    .we0    ( ram_we & {2{ram_cs}} ),
    .q0     ( ram_data  ),

    .clk1   ( clk       ),
    .addr1a ( dma_addr[RAMW:1] ),
    .q1a    ( dma_data  ),

    .data1  ( 8'd0      ),
    .addr1b ( ioctl_addr[RAMW:0] ),
    .we1b   ( 1'd0      ),
    .q1b    ( dump_ram  ),
    .sel_b  ( ioctl_ram )
);

endmodule