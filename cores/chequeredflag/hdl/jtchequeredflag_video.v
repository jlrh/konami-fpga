/*  This file is part of the Chequered Flag core for MiSTer. GPLv3. */

module jtchequeredflag_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,
    input             cen24,
    input             flip,

    output            lhbl, lvbl, hs, vs,

    input      [15:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    input             obj_cs, vr1_cs, vr2_cs, pal_cs, psac1_io, psac2_io,
    input             readroms,
    input      [ 7:0] vreg,
    output     [ 7:0] obj_dout, psac1_dout, psac2_dout, pal_dout,
    output            vid_ok,
    output            irq_n, nmi_n,

    output     [19:2] lyro_addr,
    output            lyro_cs,
    input             lyro_ok,
    input      [31:0] lyro_data,

    output     [19:0] psac2a_addr, psac2b_addr,
    output            psac2a_cs,   psac2b_cs,
    input             psac2a_ok,   psac2b_ok,
    input      [ 7:0] psac2a_data, psac2b_data,

    output     [16:0] psac1_addr,
    input      [ 7:0] psac1_data,

    output     [ 7:0] red, green, blue,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output            ovr
);

parameter BLANK_DLY = 1;

wire [ 8:0] hdump, vdump, vrender, vrender1;
wire [ 8:0] p1_pxl, p2_pxl;
wire [ 7:0] o_col, p1_ram, p2_ram;
wire        p1_ok, p2_ok, o_src, o_pm, o_sh0, o_sh1, shadow_mode, lhbl_t, lvbl_t;
wire        ovr1, ovr2, ovr3;

assign ovr        = ovr1 | ovr2 | ovr3;

reg flip_l = 0, lvbl_fl = 0;
always @(posedge clk) begin
    lvbl_fl <= lvbl_t;
    if( lvbl_fl && !lvbl_t ) flip_l <= flip;
end

wire        psac1_cs;
reg  [16:0] p1a_q, p1a_qq;
reg         psac1_ok;
always @(posedge clk) begin
    p1a_q <= psac1_addr; p1a_qq <= p1a_q;
    psac1_ok <= psac1_cs && psac1_addr==p1a_q && p1a_q==p1a_qq;
end

`ifdef SIMULATION

reg ovr_dicho = 0; integer nfr = 0; reg lvbl_ll = 0;
always @(posedge clk) begin
    lvbl_ll <= lvbl_t;
    if( lvbl_t && !lvbl_ll ) nfr = nfr + 1;
    if( ovr && !ovr_dicho ) begin
        ovr_dicho <= 1;
        $display("VIDEO: overrun de linea en el frame %0d (psac1=%0d psac2=%0d obj=%0d)", nfr, ovr1, ovr2, ovr3);
    end
end
`endif

assign psac1_dout = p1_ram;
assign psac2_dout = p2_ram;
assign vid_ok     = 1'b1;

jtframe_vtimer #(
    .HCNT_START ( 9'h020    ),
    .HCNT_END   ( 9'h19F    ),
    .HB_START   ( 9'h199    ),
    .HB_END     ( 9'h069    ),
    .HS_START   ( 9'h034    ),
    .V_START    ( 9'h0F8    ),
    .VB_START   ( 9'h1EF    ),
    .VB_END     ( 9'h10F    ),
    .VS_START   ( 9'h1FF    ),
    .VS_END     ( 9'h0FF    ),
    .VCNT_END   ( 9'h1FF    )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),
    .H          ( hdump     ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( lhbl_t    ),
    .LVBL       ( lvbl_t    ),
    .HS         ( hs        ),
    .VS         ( vs        )
);

jtframe_sh #(.W(2),.L(BLANK_DLY)) u_bdly(
    .clk    ( clk       ),
    .clk_en ( pxl_cen   ),
    .din    ( {lhbl_t, lvbl_t} ),
    .drop   ( {lhbl, lvbl} )
);

jtchequeredflag_psac #(.BPP(4),.AW(17),.WRAP(0),.DUAL(0)) u_psac1(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .flip       ( flip_l    ),
    .hdump      ( hdump     ),
    .vrender    ( vrender   ),
    .vdump      ( vdump     ),
    .hs         ( hs        ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .vr_cs      ( vr1_cs    ),
    .io_cs      ( psac1_io  ),
    .cpu_din    ( p1_ram    ),
    .ckbank     (           ),
    .rom_addr   ( psac1_addr),
    .rom_cs     ( psac1_cs  ),
    .rom_ok     ( psac1_ok  ),
    .rom_data   ( psac1_data),
    .rom2_addr  (           ),
    .rom2_cs    (           ),
    .rom2_ok    ( 1'b0      ),
    .rom2_data  ( 8'd0      ),
    .pxl        ( p1_pxl    ),
    .pxl_ok     ( p1_ok     ),
    .busy_ovr   ( ovr1      )
);

jtchequeredflag_psac #(.BPP(8),.AW(20),.WRAP(1),.DUAL(1)) u_psac2(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .flip       ( flip_l    ),
    .hdump      ( hdump     ),
    .vrender    ( vrender   ),
    .vdump      ( vdump     ),
    .hs         ( hs        ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .vr_cs      ( vr2_cs    ),
    .io_cs      ( psac2_io  ),
    .cpu_din    ( p2_ram    ),
    .ckbank     (           ),
    .rom_addr   ( psac2a_addr),
    .rom_cs     ( psac2a_cs  ),
    .rom_ok     ( psac2a_ok  ),
    .rom_data   ( psac2a_data),
    .rom2_addr  ( psac2b_addr),
    .rom2_cs    ( psac2b_cs  ),
    .rom2_ok    ( psac2b_ok  ),
    .rom2_data  ( psac2b_data),
    .pxl        ( p2_pxl    ),
    .pxl_ok     ( p2_ok     ),
    .busy_ovr   ( ovr2      )
);

jtchequeredflag_obj u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .flip       ( flip_l    ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .hs         ( hs        ),
    .lvbl       ( lvbl_t    ),
    .cs         ( obj_cs    ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .cpu_din    ( obj_dout  ),
    .irq_n      ( irq_n     ),
    .nmi_n      ( nmi_n     ),
    .shadow_mode( shadow_mode ),
    .rom_addr   ( lyro_addr ),
    .rom_cs     ( lyro_cs   ),
    .rom_ok     ( lyro_ok   ),
    .rom_data   ( lyro_data ),
    .px_src     ( o_src     ),
    .px_pm      ( o_pm      ),
    .px_sh0     ( o_sh0     ),
    .px_sh1     ( o_sh1     ),
    .px_col     ( o_col     ),
    .busy_ovr   ( ovr3      )
);

jtchequeredflag_colmix u_colmix(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .pal_cs     ( pal_cs    ),
    .pal_dout   ( pal_dout  ),
    .vreg       ( vreg      ),
    .shadow_mode( shadow_mode ),
    .p2_pxl     ( p2_pxl    ),
    .p1_pxl     ( p1_pxl    ),
    .p1_ok      ( p1_ok     ),
    .o_src      ( o_src     ),
    .o_pm       ( o_pm      ),
    .o_sh0      ( o_sh0     ),
    .o_sh1      ( o_sh1     ),
    .o_col      ( o_col     ),
    .gfx_en     ( gfx_en    ),
    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      )
);

endmodule
