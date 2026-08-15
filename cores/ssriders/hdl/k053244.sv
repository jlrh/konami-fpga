/*  ssriders — K053244/K053245 sprite generator, top level.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module k053244(
    input             rst,
    input             clk,
    input             pxl2_cen,
    input             pxl_cen,

    input             cs,
    input             cpu_we,
    input      [ 3:0] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,

    output     [21:1] rmrd_addr,

    output     [13:1] dma_addr,
    input      [15:0] dma_data,
    output            dma_bsy,

    output     [15:0] code,
    output     [ 6:0] attr,
    output            hflip,
    output            vflip,
    output     [ 9:0] hpos,
    output     [ 3:0] ysub,
    output     [11:0] hzoom,
    output            hz_keep,

    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input             lvbl,
    input             hs,

    input      [ 8:0] pxl,
    output            shd,

    output            dr_start,
    input             dr_busy,

    input      [ 7:0] debug_bus,
    input      [ 7:0] st_addr,
    output     [ 7:0] st_dout,

    output     [ 7:0] dbg_cfg,
    output            dbg_dmatrig
);

parameter HFLIP_OFFSET = 0;

wire [15:0] scan_even, scan_odd, dma_din;
wire [11:2] scan_addr;
wire [11:1] dma_wr_addr;
wire [ 9:0] xoffset, yoffset;
wire [ 7:0] cfg;
wire        dma_wel, dma_weh, dma_trig, flicker, nc;

wire ghf    = cfg[0];
wire gvf    = cfg[1];
wire dma_en = cfg[4];

assign dma_trig    = cs && cpu_addr[2:1]==2'b11;
assign dbg_cfg     = cfg;
assign dbg_dmatrig = dma_trig;

k053244_scan #(.HFLIP_OFFSET(HFLIP_OFFSET)) u_scan(
    .rst       ( rst        ),
    .clk       ( clk        ),
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

k053244_dma u_dma(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),

    .dma_en     ( dma_en    ),
    .dma_trig   ( dma_trig  ),

    .z_rej_en   ( 1'b1      ),
    .z_rej      ( 7'd0      ),
    .z_rej_skip0( 1'b1      ),

    .hs         ( hs        ),
    .lvbl       ( lvbl      ),

    .dma_addr   ( dma_addr  ),
    .dma_data   ( dma_data  ),
    .dma_bsy    ( dma_bsy   ),

    .dma_weh    ( dma_weh   ),
    .dma_wel    ( dma_wel   ),
    .dma_wr_addr( dma_wr_addr ),
    .dma_din    ( dma_din   ),

    .flicker    ( flicker   )
);

k053244_mmr u_mmr(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cs         ( cs        ),
    .cpu_we     ( cpu_we    ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cfg        ( cfg       ),
    .xoffset    ( xoffset   ),
    .yoffset    ( yoffset   ),
    .rmrd_addr  ( {nc,rmrd_addr} ),
    .st_addr    ( st_addr   ),
    .st_dout    ( st_dout   )
);

jtframe_dual_ram16 #(.AW(10)) u_even(
    .clk0   ( clk              ),
    .data0  ( dma_din          ),
    .addr0  ( dma_wr_addr[11:2]),
    .we0    ( {2{dma_wel}}     ),
    .q0     (                  ),
    .clk1   ( clk              ),
    .data1  ( 16'd0            ),
    .addr1  ( scan_addr        ),
    .we1    ( 2'b0             ),
    .q1     ( scan_even        )
);

jtframe_dual_ram16 #(.AW(10)) u_odd(
    .clk0   ( clk              ),
    .data0  ( dma_din          ),
    .addr0  ( dma_wr_addr[11:2]),
    .we0    ( {2{dma_weh}}     ),
    .q0     (                  ),
    .clk1   ( clk              ),
    .data1  ( 16'd0            ),
    .addr1  ( scan_addr        ),
    .we1    ( 2'b0             ),
    .q1     ( scan_odd         )
);

`ifdef SIMULATION
reg [7:0] cfg_l=0;
reg       lvbl_l=0;
integer   dmatrig_cnt=0, dmaok_cnt=0, inzone_cnt=0;
always @(posedge clk) begin
    cfg_l <= cfg;
    if( cfg !== cfg_l ) $display("S83-CFG cfg=%02x dma_en=%b t=%0t", cfg, cfg[4], $time);
    if( dma_trig ) dmatrig_cnt <= dmatrig_cnt + 1;

    if( u_dma.wr_en && u_dma.st==2'd2 ) dmaok_cnt <= dmaok_cnt + 1;
    if( u_scan.inzone ) inzone_cnt <= inzone_cnt + 1;
    lvbl_l <= lvbl;
    if( lvbl_l && !lvbl ) begin
        $display("S83-FRAME dmatrig=%0d dmaok=%0d inzone=%0d cfg=%02x xoff=%03x yoff=%03x",
            dmatrig_cnt, dmaok_cnt, inzone_cnt, cfg, xoffset, yoffset);
        dmatrig_cnt <= 0; dmaok_cnt <= 0; inzone_cnt <= 0;
    end
end
`endif

endmodule
