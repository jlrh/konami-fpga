/*  This file is part of JTCORES (fork COWBOYS / Moo Mesa). GPLv3. */

module xexex_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,
    input      [ 1:0] vmode,

    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    output     [ 8:0] hdump,
    output     [ 8:0] vdump,
    output     [ 8:0] lyro_pxl_o,

    output            tile_irqn,
    output            tile_nmin,

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
    input             objcha_n,

    output reg        vdtac,
    input             tilesys_cs,
    input             tilereg_cs,

    input             lvcram_cs,
    input             lvcreg_cs,
    input             lvcrom_cs,
    output     [15:0] lvc_dout,
    output            lvc_cpu_ok,
    output     [17:2] lvc_addr,
    output            lvc_cs,
    input      [31:0] lvc_data,
    input             lvc_ok,
    output     [17:2] lvco_addr,
    output            lvco_cs,
    input      [31:0] lvco_data,
    input             lvco_ok,
    input             alpha_off,
    output            rst8,

    input             rmrd,
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

wire        hs_int, vs_int;
wire [ 8:0] vrender, vrender1, lyro_pxl;
assign lyro_pxl_o = lyro_pxl;
wire [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl, dump_obj, obj_mmr;
wire        lyra_mix, lyrb_mix, lyrc_mix;
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

reg hs_crt=0, vs_crt=0;
wire [1:0] vm;
assign hs = hs_crt;
assign vs = vs_crt;
always @(posedge clk) if(pxl_cen) begin
    if( hdump==9'h1A3 ) begin
        hs_crt <= 1;

        case( vm )
            2'd1:    vs_crt <= vdump>=9'h0DB && vdump<=9'h0DD;
            2'd2:    vs_crt <= vdump>=9'h0F5 && vdump<=9'h0F7;
            default: vs_crt <= vdump>=9'h0EB && vdump<=9'h0F0;
        endcase
    end
    if( hdump==9'h1CB ) hs_crt <= 0;
end

xexex_k056832 u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs_int    ),
    .vs         ( vs_int    ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),
    .vmode      ( vmode     ),
    .vm         ( vm        ),

    .vram_cs    ( tilesys_cs),
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
    .lyra_mix   ( lyra_mix  ),
    .lyrb_mix   ( lyrb_mix  ),
    .lyrc_mix   ( lyrc_mix  ),

    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

assign tile_irqn = 1'b1;

/* verilator tracing_on */
assign ommra = {cpu_addr[3:1],cpu_dsn[1]};

assign orama    = { 2'd0, cpu_addr[14:7], cpu_addr[4:2] };
assign orama_we = oram_we & {2{cpu_addr[6:5]==2'd0 && !cpu_addr[1]}};

wire [15:0] oram_cpu_q;
jtframe_ram16 #(.AW(14)) u_oram_cpu(
    .clk    ( clk       ),
    .data   ( cpu_dout  ),
    .addr   ( cpu_addr[14:1] ),
    .we     ( oram_we & {2{objsys_cs}} ),
    .q      ( oram_cpu_q )
);
assign objsys_dout = oram_cpu_q;

wire [8:0] lvc_pxl;
xexex_k053250 u_lvc(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .ram_cs     ( lvcram_cs ),
    .reg_cs     ( lvcreg_cs ),
    .rom_cs     ( lvcrom_cs ),
    .cpu_we     ( cpu_we    ),
    .cpu_addr   ( cpu_addr[12:1] ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( lvc_dout  ),
    .cpu_ok     ( lvc_cpu_ok),
    .rom0_addr  ( lvc_addr  ),
    .rom0_cs    ( lvc_cs    ),
    .rom0_data  ( lvc_data  ),
    .rom0_ok    ( lvc_ok    ),
    .rom1_addr  ( lvco_addr ),
    .rom1_cs    ( lvco_cs   ),
    .rom1_data  ( lvco_data ),
    .rom1_ok    ( lvco_ok   ),
    .lhbl       ( lhbl      ),
    .hdump      ( hdump     ),
    .vrender1   ( vrender1  ),
    .pc_line    ( vm==2'd2 ? 9'h0F2 : 9'h0F0 ),
    .pxl        ( lvc_pxl   )
);

wire [7:0] obj_dbg;
`ifdef SIMULATION
assign obj_dbg = 8'd5;
`else
assign obj_dbg = debug_bus;
`endif

`ifdef SIMULATION

always @(posedge clk) if( objreg_cs && cpu_we ) begin
    $display("OBJREG_WR ommra=%b (addr[2:1]=%0d) dsn=%b dout=%04x -> %s",
        ommra, ommra[2:1], cpu_dsn, cpu_dout,
        (ommra[2:1]==2'd2 && !cpu_dsn[0]) ? "LATCHEA cfg" : "no toca cfg");
end

reg hs_l, lvbl_l2, p2c_seen;
integer n_hs=0, n_lvbl=0, n_p2c=0;
always @(posedge clk) begin
    hs_l <= hs_int; lvbl_l2 <= lvbl;
    if( pxl2_cen ) n_p2c <= n_p2c+1;
    if( ~hs_l & hs_int ) n_hs <= n_hs+1;
    if( lvbl_l2 & ~lvbl ) begin
        n_lvbl <= n_lvbl+1;
        $display("VTIMER frame=%0d | hs_pos=%0d pxl2_cen=%0d (por frame) | MMRCFG cfg=%02x dma_en=%b",
            n_lvbl, n_hs, n_p2c, obj_mmr, obj_mmr[4]);
        n_hs <= 0; n_p2c <= 0;
    end
end
`endif

localparam [9:0] OVOFFSET=10'h120;

localparam [8:0] OBJ_HOFF=9'd150;

localparam EDGE_TRIGGER = `ifndef NOMAIN 2 `else 0 `endif;

xexex_obj #(.RAMW(13),.SHADOW(1),.EDGE_TRIGGER(EDGE_TRIGGER)) u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),
    .simson     ( 1'b0      ),
    .ln_done    (           ),

    .voffset    ( OVOFFSET  ),
    .hs         ( hs_int    ),
    .lvbl       ( lvbl      ),
    .hdump      ( hdump + OBJ_HOFF ),
    .vdump      ( vrender   ),

    .ram_cs     ( objsys_cs ),
    .ram_addr   ( orama     ),
    .ram_din    ( cpu_dout  ),
    .ram_we     ( orama_we  ),
    .cpu_din    (           ),

    .reg_cs     ( objreg_cs ),
    .mmr_addr   ( ommra     ),
    .mmr_din    ( cpu_dout  ),
    .mmr_we     ( cpu_we    ),
    .mmr_dsn    ( cpu_dsn   ),

    .dma_bsy    ( dma_bsy   ),

    .rom_addr   ( lyro_addr ),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     ( lyro_cs   ),
    .objcha_n   ( objcha_n  ),

    .pxl        ( lyro_pxl  ),
    .shd        ( shadow    ),
    .prio       ( lyro_pri  ),

    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( {obj_amsb[1:0],ioctl_addr[11:0]} ),
    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( obj_dbg   )
);

/* verilator tracing_on */
xexex_colmix u_colmix(
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
    .lyra_mix   ( lyra_mix  ),
    .lyrb_mix   ( lyrb_mix  ),
    .lyrc_mix   ( lyrc_mix  ),
    .lyro_pxl   ( lyro_pxl  ),
    .lyro_pri   ( lyro_pri  ),

    .dimmod     ( dimmod    ),
    .dimpol     ( dimpol    ),
    .dim        ( dim       ),
    .shadow     ( shadow    ),
    .alpha_off  ( alpha_off ),
    .lvc_pxl    ( lvc_pxl   ),

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
