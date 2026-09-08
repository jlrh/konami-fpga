/*  This file is part of JTCORES (fork COWBOYS / Moo Mesa). GPLv3.

    jtasterix_video — integra el tilemap K056832 (jtasterix_k056832, validado 0.00% vs golden) con
    los sprites (jtsimson_obj, reuso xmen/simson) y el colmix (K053251 + K054338 alpha).

    Arquitectura del tilemap = estilo rungun (Camino A): el modulo K056832 lleva su PROPIO vtimer
    (fuente de timing del core) + VRAM interna paginada + 1 bus ROM SERIAL (scr) que multiplexa las 4
    capas. Sustituye a jtaliens_scroll (que era el K052109 de X-Men, chip distinto).

    PENDIENTE (validacion por escenas / Fase siguiente):
      - Empaquetado EXACTO de pixel hacia el K053251 en colmix (ci = f(colnib,pen)) — juez: sim==golden.
      - Alpha K054338 (geiser) — delta extra en colmix.
      - Carga por escena: la VRAM/regs del modulo son internos; para restore-ioctl habra que exponerlos
        como BRAM jtframe (como rungun) o cargar por el bus CPU en el testbench de escena.
      - Timing HW: el vtimer usa HTOTAL=456 (limite 9 bits); para MiSTer real revisar HJUMP/CRTC K053252.
      - Lectura CPU 16-bit (tilesys_dout) y separacion vram_cs(0x1a0000)/reg_cs(0x0c0000) en main (Fase 1).
*/
module jtasterix_video(
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

    input      [16:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    input             pcu_cs,
    input             alpha_cs,
    input             pal_cs,
    output     [15:0] pal_dout,
    output     [15:0] tilesys_dout,

    output            dma_bsy,
    output     [15:0] objsys_dout,
    input             objsys_cs,
    input             objreg_cs,
    input             objreg_byte,
    input             objcha_n,

    output reg        vdtac,
    input             tilesys_cs,
    input             tilereg_cs,
    output            rst8,

    input             rmrd,
    input             tilebank,
    input      [15:0] spritebank,
    input      [ 8:0] objdx,
    input      [ 9:0] objdy,
    output            flip,

    output     [20:2] scr_addr,
    output            scr_cs,
    input      [31:0] scr_data,
    input             scr_ok,

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
wire [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl, dump_obj, obj_mmr;
wire [ 4:0] lyro_pri;
wire [ 1:0] shadow;
wire [ 3:0] obj_amsb = 4'd0;
wire [15:0] tile_din;
wire [18:0] rom_addr;
wire [ 1:0] rom_lyr;
wire        rom_cs, cpu_weg;
wire [ 3:0] ommra;
wire [13:1] orama;
wire [ 1:0] orama_we;

assign cpu_weg     = cpu_we && cpu_dsn!=2'b11;
assign flip        = 1'b0;
assign tile_nmin   = 1'b1;
assign rst8        = 1'b0;
assign st_dout     = 8'd0;
assign tilesys_dout= tile_din;

assign scr_addr    = rom_addr;
assign scr_cs      = rom_cs;

always @(posedge clk) vdtac <= 1'b1;

/* verilator tracing_on */

jtasterix_k056832 u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .vs         ( vs        ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),

    .vram_cs    ( tilesys_cs),
    .cpu_dsn    ( cpu_dsn   ),
    .reg_cs     ( tilereg_cs),
    .cpu_we     ( cpu_weg   ),
    .cpu_addr   (cpu_addr[12:1]),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( tile_din  ),

    .rom_addr   ( rom_addr  ),
    .rom_lyr    ( rom_lyr   ),
    .rom_cs     ( rom_cs    ),
    .rom_data   ( scr_data  ),
    .rom_ok     ( scr_ok    ),

    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyrc_pxl   ( lyrc_pxl  ),

    .tilebank   ( tilebank  ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

assign tile_irqn = 1'b1;

/* verilator tracing_on */

assign ommra    = objreg_byte ? cpu_addr[4:1] : {cpu_addr[3:1], cpu_dsn[1]};

assign orama    = cpu_addr[13:1];
assign orama_we = oram_we;

`ifdef SIMULATION

integer vs_frame = 0;
reg     vs_lvbl_l = 0;
always @(posedge clk) begin
    vs_lvbl_l <= lvbl;
    if( lvbl && !vs_lvbl_l ) vs_frame <= vs_frame + 1;
end
always @(posedge clk) if( objsys_cs && cpu_we && |orama_we )
    $display("OBJRAM-W: frame=%0d idx=%0d(0x%03x) data=%04x we=%02x", vs_frame, orama, orama, cpu_dout, orama_we);
`endif

wire       obj_shd;

jtasterix_obj #(.RAMW(13),.SHADOW(1)) u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),

    .hs         ( hs        ),
    .lvbl       ( lvbl      ),
    .hdump      ( hdump + objdx ),
    .vdump      ( vrender + objdy[8:0] ),
    .spritebank ( spritebank ),

    .ram_cs     ( objsys_cs ),
    .ram_addr   ( orama     ),
    .ram_din    ( cpu_dout  ),
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
    .ioctl_addr ( {obj_amsb[1:0],ioctl_addr[11:0]} ),
    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

assign lyro_addr[22]= 1'b0;
assign shadow       = {1'b0, obj_shd};

/* verilator tracing_on */
jtasterix_colmix u_colmix(
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
    .lyrc_pxl   ( lyrc_pxl  ),
    .lyro_pxl   ( lyro_pxl  ),
    .lyro_pri   ( lyro_pri  ),

    .dimmod     ( dimmod    ),
    .dimpol     ( dimpol    ),
    .dim        ( dim       ),
    .shadow     ( shadow    ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      ),

    .ioctl_addr ( ioctl_addr[11:0]),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( ioctl_din ),
    .dump_mmr   (           ),

    .debug_bus  ( debug_bus )
);

endmodule
