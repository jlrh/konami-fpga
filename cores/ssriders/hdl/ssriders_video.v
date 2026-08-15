/*  ssriders — integracion de tilemap, sprites y mezclador.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module ssriders_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    output     [ 8:0] hdump,
    output     [ 8:0] vdump,
    output     [ 8:0] lyro_pxl_o,

    output            tile_irqn,
    output            tile_nmin,

    input      [13:1] oram_addr,
    input      [ 1:0] oram_we,
    input      [15:0] oram_din,

    input      [16:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    input             pcu_cs,
    input             alpha_cs,
    input             pal_cs,
    output     [15:0] pal_dout,
    output     [15:0] tile_dout,

    output            dma_bsy,
    output     [15:0] objsys_dout,
    input             objsys_cs,
    input             objreg_cs,
    input             objreg_byte,
    input             objcha_n,

    output reg        vdtac,
    input             tile_cs,
    output            rst8,

    input             rmrd,
    input      [ 8:0] objdx,
    input      [ 9:0] objdy,
    output            flip,

    output     [19:2] lyrf_addr,
    output     [19:2] lyra_addr,
    output     [19:2] lyrb_addr,
    output            lyrf_cs,
    output            lyra_cs,
    output            lyrb_cs,
    input      [31:0] lyrf_data,
    input      [31:0] lyra_data,
    input      [31:0] lyrb_data,
    input             lyrf_ok,
    input             lyra_ok,
    input             lyrb_ok,

    output     [22:2] lyro_addr,
    output            lyro_cs,
    input             lyro_ok,
    input      [31:0] lyro_data,

    input      [ 2:0] dim,
    input             dimmod,
    input             dimpol,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    input      [15:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout
);

wire [ 8:0] vrender, vrender1, lyro_pxl;
assign lyro_pxl_o = lyro_pxl;
wire [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, dump_obj, obj_mmr;
wire [ 4:0] lyro_pri;
wire [ 1:0] shadow;
wire [ 3:0] ommra;
wire [13:1] orama;
wire [ 1:0] orama_we;

wire [ 7:0] tile_ioctl_din, colmix_ioctl_din;
wire [ 7:0] dbg_cnt, dbg_flags;

wire [ 7:0] dbg_cfg, dbg_dmatrig_cnt;

wire        dbgstat_dump_sel = ioctl_ram & (ioctl_addr[15:4]==12'h902);
wire [ 7:0] dbgstat_ioctl_din = !dbgstat_dump_sel ? 8'd0 :
                                 ioctl_addr[3:0]==4'd0 ? dbg_cnt :
                                 ioctl_addr[3:0]==4'd1 ? dbg_flags :
                                 ioctl_addr[3:0]==4'd2 ? {7'd0,dma_bsy} :
                                 ioctl_addr[3:0]==4'd3 ? dbg_cfg :
                                 ioctl_addr[3:0]==4'd4 ? dbg_dmatrig_cnt : 8'd0;

wire        obj_dump_sel = ioctl_ram & (ioctl_addr[15:14]==2'b00);
assign ioctl_din = tile_ioctl_din | colmix_ioctl_din | (obj_dump_sel ? dump_obj : 8'd0) | dbgstat_ioctl_din;

assign st_dout = debug_bus[1:0]==2'd0 ? dbg_cnt :
                  debug_bus[1:0]==2'd1 ? dbg_flags :
                  debug_bus[1:0]==2'd2 ? {7'd0,dma_bsy} :
                  debug_bus[1:0]==2'd3 ? dbg_cfg : 8'd0;

assign flip        = 1'b0;

assign tile_nmin   = 1'b1;

always @(posedge clk) vdtac <= 1'b1;

/* verilator tracing_on */

`ifndef SSR_HB_OFFSET
 `define SSR_HB_OFFSET 0
`endif
`ifndef SSR_HB_EXTRAL
 `define SSR_HB_EXTRAL 0
`endif
`ifndef SSR_HB_EXTRAR
 `define SSR_HB_EXTRAR 160
`endif
ssriders_k052109 #(
    .HB_OFFSET  ( 9'd`SSR_HB_OFFSET ),
    .HB_EXTRAL  ( 9'd`SSR_HB_EXTRAL ),
    .HB_EXTRAR  ( 9'd`SSR_HB_EXTRAR )
) u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .vs         ( vs        ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),

    .tile_cs    ( tile_cs   ),
    .cpu_addr   (cpu_addr[13:1]),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .cpu_din    ( tile_dout ),

    .irqn       ( tile_irqn ),
    .rst8       ( rst8      ),
    .rmrd       ( rmrd      ),

    .lyrf_addr  ( lyrf_addr ),
    .lyra_addr  ( lyra_addr ),
    .lyrb_addr  ( lyrb_addr ),
    .lyrf_cs    ( lyrf_cs   ),
    .lyra_cs    ( lyra_cs   ),
    .lyrb_cs    ( lyrb_cs   ),
    .lyrf_data  ( lyrf_data ),
    .lyra_data  ( lyra_data ),
    .lyrb_data  ( lyrb_data ),
    .lyrf_ok    ( lyrf_ok   ),
    .lyra_ok    ( lyra_ok   ),
    .lyrb_ok    ( lyrb_ok   ),

    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),

    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),

    .ioctl_ram  ( ioctl_ram      ),
    .ioctl_addr ( ioctl_addr     ),
    .ioctl_din  ( tile_ioctl_din )
);

/* verilator tracing_on */

assign ommra    = objreg_byte ? {cpu_addr[4:2], cpu_dsn[1]} : {cpu_addr[3:1], cpu_dsn[1]};

assign orama    = oram_addr;
assign orama_we = oram_we;

`ifdef SIMULATION

integer vs_frame = 0;
reg     vs_lvbl_l = 0;
always @(posedge clk) begin
    vs_lvbl_l <= lvbl;
    if( lvbl && !vs_lvbl_l ) vs_frame <= vs_frame + 1;
end

`ifdef _SSR_TRACE_OBJRAM
always @(posedge clk) if( objsys_cs && cpu_we && |orama_we )
    $display("OBJRAM-W: frame=%0d idx=%0d(0x%03x) data=%04x we=%02x", vs_frame, orama, orama, cpu_dout, orama_we);
`endif
`endif

wire       obj_shd;

ssriders_obj #(.RAMW(13),.SHADOW(1)) u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),

    .hs         ( hs        ),
    .lvbl       ( lvbl      ),

    .hdump      ( {1'b0,hdump} + {1'b0,objdx} ),
    .vdump      ( vrender + objdy[8:0] ),

    .ram_cs     ( objsys_cs ),
    .ram_addr   ( orama     ),
    .ram_din    ( oram_din  ),
    .ram_we     ( orama_we  ),
    .cpu_din    (objsys_dout),

    .reg_cs     ( objreg_cs ),
    .mmr_addr   ( ommra     ),
    .mmr_din    ( cpu_dout  ),
    .mmr_we     ( cpu_we    ),
    .mmr_dsn    ( cpu_dsn   ),

    .dma_bsy    ( dma_bsy   ),

    .rom_addr   ( lyro_addr[21:2] ),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     ( lyro_cs   ),
    .objcha_n   ( objcha_n  ),

    .pxl        ( lyro_pxl  ),
    .shd        ( obj_shd   ),
    .prio       ( lyro_pri  ),

    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( ioctl_addr ),

    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .dbg_cnt    ( dbg_cnt   ),
    .dbg_flags  ( dbg_flags ),
    .dbg_cfg         ( dbg_cfg         ),
    .dbg_dmatrig_cnt ( dbg_dmatrig_cnt )
);

assign lyro_addr[22]= 1'b0;
assign shadow       = {1'b0, obj_shd};

wire cpu_weg = cpu_we && cpu_dsn!=2'b11;

/* verilator tracing_on */
ssriders_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),

    .cpu_addr   (cpu_addr[12:1]),
    .cpu_we     ( cpu_weg   ),
    .cpu_din    ( pal_dout  ),
    .cpu_d8     ( cpu_dout[7:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .pal_cs     ( pal_cs    ),
    .pcu_cs     ( pcu_cs    ),
    .alpha_cs   ( alpha_cs  ),

    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyro_pxl   ( lyro_pxl  ),
    .lyro_pri   ( lyro_pri  ),

    .dimmod     ( dimmod    ),
    .dimpol     ( dimpol    ),
    .dim        ( dim       ),
    .shadow     ( shadow    ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      ),

    .ioctl_addr ( ioctl_addr ),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( colmix_ioctl_din ),
    .dump_mmr   (           ),

    .debug_bus  ( debug_bus )
);

endmodule
