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
    Adapted for ASTERIX (GX068) — B2 de research/FASE2-PLAN.md.
*/

module jtasterix_obj #(parameter
    RAMW   = 13,
    HFLIP_OFFSET = 0,
    SHADOW = 1
)(
    input             rst,
    input             clk,

    input             pxl_cen,
    input             pxl2_cen,
    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input             hs,
    input             lvbl,

    input      [15:0] spritebank,

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

    output     [21:2] rom_addr,
    input      [31:0] rom_data,
    output            rom_cs,
    input             rom_ok,
    input             objcha_n,

    output            shd,
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

wire        pre_shd;
wire [ 3:0] pen_eff;
wire [15:0] ram_data, dma_data;
wire [22:2] pre_addr;
wire [21:1] rmrd_addr;
wire [13:1] dma_addr;
wire [15:0] pre_pxl;

wire        dr_start, dr_busy;
wire [15:0] code, code_bank;
wire [ 6:0] attr;
wire        hflip, vflip, hz_keep, pre_cs;
wire [ 9:0] hpos;
wire [ 3:0] ysub;
wire [11:0] hzoom;
wire        pen15;

function [5:0] paroda_conv(input [5:0]x);
    paroda_conv = { x[5], x[3], x[1], x[4], x[2], x[0] };
endfunction

function [2:0] sprbank(input [1:0] sel, input [15:0] sb);
    case( sel )
        2'd0: sprbank = sb[ 2:0];
        2'd1: sprbank = sb[ 5:3];
        2'd2: sprbank = sb[ 8:6];
        2'd3: sprbank = sb[11:9];
    endcase
endfunction
assign code_bank = { 1'b0, sprbank(code[13:12], spritebank), code[11:0] };

assign rom_cs    = ~objcha_n | pre_cs;
assign rom_addr  = !objcha_n ? rmrd_addr[21:2] :
    { pre_addr[21], pre_addr[20:13], paroda_conv(pre_addr[12:7]), pre_addr[5], pre_addr[6], pre_addr[4:2] };

assign cpu_din   = !objcha_n ? rmrd_addr[1] ? rom_data[31:16] : rom_data[15:0] :
                    ram_data;

assign pen15   = &pre_pxl[3:0];
assign pen_eff = (pre_pxl[15:14]==0 || !pen15) ? pre_pxl[3:0] : 4'd0;

assign shd     =  pre_pxl[14];
assign prio    =  {1'd1,pre_pxl[10:9],2'd0} ;
assign pxl     = gfx_en[3] ? {pre_pxl[8:4], pen_eff} : 9'd0;

`ifdef SIMULATION

reg [15:0] s30_frame=0;
reg        s30_lvbl_l;
always @(posedge clk) begin
    s30_lvbl_l <= lvbl;
    if(!lvbl && s30_lvbl_l) s30_frame <= s30_frame + 1'b1;
end
always @(posedge clk) if(pxl_cen && lvbl && pre_pxl[14] && pre_pxl[3:0]!=4'h0 && pre_pxl[3:0]!=4'hf
                          && s30_frame>=16'd600 && s30_frame<=16'd1250)
    $display("SHD-SOLID frame=%0d hdump=%0d vdump=%0d pen=%0d pre_pxl=%04x",
              s30_frame, hdump, vdump, pre_pxl[3:0], pre_pxl);
`endif

jtasterix_053244 #(.HFLIP_OFFSET(HFLIP_OFFSET)
    )u_scan(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),
    .pxl_cen    ( pxl_cen   ),

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

jtframe_objdraw #(
    .SHADOW(SHADOW),.SHADOW_GATE(1),.SHADOW_PEN(SHADOW_PEN),.SW(2),.HFIX(0),
    .AW(10),.CW(16),.PW(4+10+2),.LATCH(1),.SWAPH(1),
    .ZW(12),.ZI(6),.ZENLARGE(1),
    .FLIP_OFFSET(9'h12),.KEEP_OLD(0)
) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( {1'b0,hdump}  ),

    .draw       ( dr_start      ),
    .busy       ( dr_busy       ),
    .code       ( code_bank     ),
    .xpos       ( hpos          ),
    .ysub       ( ysub          ),
    .hz_keep    ( hz_keep       ),
    .hzoom      ( hzoom         ),

    .hflip      ( ~hflip        ),
    .vflip      ( vflip         ),
    .pal        ({1'b0,pre_shd, 3'b0, attr}),

    .rom_addr   ( pre_addr      ),
    .rom_cs     ( pre_cs        ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( rom_data      ),

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

`ifdef OBJDIAG

integer n_drstart=0, n_rdnz=0;
reg [9:0] hpmin=10'h3ff, hpmax=0;
reg [8:0] rdmin=9'h1ff, rdmax=0, hsmin=9'h1ff, hsmax=0;
reg lvbl_l=0;
always @(posedge clk) if(!rst) begin
    lvbl_l <= lvbl;
    if( dr_start ) begin
        n_drstart <= n_drstart+1;
        if( hpos<hpmin ) hpmin <= hpos;
        if( hpos>hpmax ) hpmax <= hpos;
    end
    if( pxl_cen && hs ) begin
        if( hdump<hsmin ) hsmin <= hdump;
        if( hdump>hsmax ) hsmax <= hdump;
    end
    if( pxl_cen && lvbl && |pre_pxl[3:0] ) begin
        n_rdnz <= n_rdnz+1;
        if( hdump<rdmin ) rdmin <= hdump;
        if( hdump>rdmax ) rdmax <= hdump;
    end
    if( lvbl_l && !lvbl )
        $display("OBJ-DIAG: dr_start=%0d hpos[%0d..%0d] | rd_nz=%0d hdump[%0d..%0d] | hs[%0d..%0d]",
                 n_drstart, hpmin, hpmax, n_rdnz, rdmin, rdmax, hsmin, hsmax);
end
`endif

endmodule
