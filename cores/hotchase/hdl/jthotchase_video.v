module jthotchase_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    output            LHBL,
    output            LVBL,
    output            HS,
    output            VS,
    output     [ 8:0] vdump,
    output     [ 8:0] hdump,

    input             video_on,

    input      [13:1] mbus_addr,
    input      [15:0] mbus_dout,
    input      [ 1:0] pal_we, spr_we,
    input             psac1_we, psac2_we, psac1_rwe, psac2_rwe,
    output     [15:0] pal_dout, spr_dout,
    output     [ 7:0] psac1_dout, psac2_dout,

    input      [11:1] sbus_addr,
    input      [15:0] sbus_dout,
    input      [ 1:0] road_we,
    output     [15:0] road_dout,

    output     [16:0] psac1_addr,
    input      [ 7:0] psac1_data,
    output     [14:0] psac2_addr,
    input      [ 7:0] psac2_data,
    output     [16:1] road_addr,
    output            road_cs,
    input      [15:0] road_data,
    input             road_ok,
    output     [21:2] spr_addr,
    output            spr_cs,
    input      [31:0] spr_data,
    input             spr_ok,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,
    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

parameter [8:0] HVIS0 = 9'd0;

wire [8:0] H, vrender, vrender1;
wire       lhbl_t, lvbl_t, hs_t, vs_t;
assign hdump = H;

jtframe_vtimer #(
    .V_START  ( 9'd0   ),
    .VB_START ( 9'd223 ),
    .VB_END   ( 9'd255 ),
    .VS_START ( 9'd240 ),
    .VS_END   ( 9'd243 ),
    .VCNT_END ( 9'd255 ),
    .HB_END   ( 9'd399 ),
    .HB_START ( 9'd319 ),
    .HS_START ( 9'd336 ),
    .HS_END   ( 9'd368 ),
    .HCNT_END ( 9'd399 )
) u_vtimer(
    .clk      ( clk      ),
    .pxl_cen  ( pxl_cen  ),
    .vdump    ( vdump    ),
    .vrender  ( vrender  ),
    .vrender1 ( vrender1 ),
    .H        ( H        ),
    .Hinit    (          ),
    .Vinit    (          ),
    .LHBL     ( lhbl_t   ),
    .LVBL     ( lvbl_t   ),
    .HS       ( hs_t     ),
    .VS       ( vs_t     )
);

reg  lhbl_d, lvbl_d, hs_d, vs_d;
always @(posedge clk) if( pxl_cen ) begin
    lhbl_d <= lhbl_t; lvbl_d <= lvbl_t; hs_d <= hs_t; vs_d <= vs_t;
end
assign LHBL = lhbl_d, LVBL = lvbl_d, HS = hs_d, VS = vs_d;

`ifdef HC_SCENE
localparam SF_PAL="pal.bin", SF_SPR="spr.bin", SF_ROAD="road.bin", SF_HIL="hil.hex",
           SF_C1="ps1_code.bin", SF_A1="ps1_attr.bin", SF_R1="ps1_regs.hex",
           SF_C2="ps2_code.bin", SF_A2="ps2_attr.bin", SF_R2="ps2_regs.hex";
`else
localparam SF_PAL="", SF_SPR="", SF_ROAD="", SF_HIL="", SF_C1="", SF_A1="", SF_R1="", SF_C2="", SF_A2="", SF_R2="";
`endif
wire [11:0] pal_ra;  wire [15:0] pal_q;
wire [10:0] spr_ra, road_ra;
wire [15:0] spr_q, road_q;

jtframe_dual_ram16 #(.AW(12),.SIMFILE(SF_PAL)) u_pal(
    .clk0(clk), .data0(mbus_dout), .addr0(mbus_addr[12:1]), .we0(pal_we),  .q0(pal_dout),
    .clk1(clk), .data1(16'd0),     .addr1(pal_ra),          .we1(2'd0),    .q1(pal_q) );
jtframe_dual_ram16 #(.AW(11),.SIMFILE(SF_SPR)) u_spr(
    .clk0(clk), .data0(mbus_dout), .addr0(mbus_addr[11:1]), .we0(spr_we),  .q0(spr_dout),
    .clk1(clk), .data1(16'd0),     .addr1(spr_ra),          .we1(2'd0),    .q1(spr_q) );
jtframe_dual_ram16 #(.AW(11),.SIMFILE(SF_ROAD)) u_road(
    .clk0(clk), .data0(sbus_dout), .addr0(sbus_addr[11:1]), .we0(road_we), .q0(road_dout),
    .clk1(clk), .data1(16'd0),     .addr1(road_ra),         .we1(2'd0),    .q1(road_q) );

wire [10:0] hil_ra;  wire hil_q;
jtframe_dual_ram #(.DW(1),.AW(11),.SIMHEXFILE(SF_HIL)) u_hilast(
    .clk0(clk), .data0(mbus_addr[12]), .addr0(mbus_addr[11:1]), .we0(|pal_we), .q0(),
    .clk1(clk), .data1(1'b0),          .addr1(hil_ra),          .we1(1'b0),    .q1(hil_q) );

wire [10:0] bg_pxl, fg_pxl;
wire        bg_ok, fg_ok, ovr1, ovr2;

jthotchase_psac #(.CB(1),.AW(17),.WRAP(1),.HVIS0(HVIS0),.SF_CODE(SF_C1),.SF_ATTR(SF_A1),.SF_REGS(SF_R1)) u_psac1(
    .rst      ( rst            ), .clk     ( clk          ), .flip   ( 1'b0      ),
    .hdump    ( H              ), .vrender ( vrender      ), .vdump  ( vdump     ), .hs( hs_t ),
    .cpu_addr ( mbus_addr[11:1]), .cpu_dout( mbus_dout[7:0]), .cpu_we( 1'b1     ),
    .vr_cs    ( psac1_we       ), .io_cs   ( psac1_rwe    ), .cpu_din( psac1_dout),
    .rom_addr ( psac1_addr     ), .rom_cs  (              ), .rom_ok ( 1'b1      ), .rom_data( psac1_data ),
    .pxl      ( bg_pxl         ), .pxl_ok  ( bg_ok        ), .busy_ovr( ovr1     )
);
jthotchase_psac #(.CB(2),.AW(15),.WRAP(0),.HVIS0(HVIS0),.SF_CODE(SF_C2),.SF_ATTR(SF_A2),.SF_REGS(SF_R2)) u_psac2(
    .rst      ( rst            ), .clk     ( clk          ), .flip   ( 1'b0      ),
    .hdump    ( H              ), .vrender ( vrender      ), .vdump  ( vdump     ), .hs( hs_t ),
    .cpu_addr ( mbus_addr[11:1]), .cpu_dout( mbus_dout[7:0]), .cpu_we( 1'b1     ),
    .vr_cs    ( psac2_we       ), .io_cs   ( psac2_rwe    ), .cpu_din( psac2_dout),
    .rom_addr ( psac2_addr     ), .rom_cs  (              ), .rom_ok ( 1'b1      ), .rom_data( psac2_data ),
    .pxl      ( fg_pxl         ), .pxl_ok  ( fg_ok        ), .busy_ovr( ovr2     )
);

wire [10:0] rd_pxl;  wire rd_ok, ovr3;
jthotchase_road #(.HVIS0(HVIS0)) u_roadeng(
    .rst      ( rst       ), .clk     ( clk       ),
    .hdump    ( H         ), .vrender ( vrender   ), .vdump( vdump ), .hs( hs_t ),
    .ram_addr ( road_ra   ), .ram_q   ( road_q    ),
    .rom_addr ( road_addr ), .rom_cs  ( road_cs   ), .rom_ok( road_ok ), .rom_data( road_data ),
    .pxl      ( rd_pxl    ), .pxl_ok  ( rd_ok     ), .busy_ovr( ovr3 )
);

reg  [8:0] vr_l, v;
reg        obj_start;
always @(posedge clk) begin
    vr_l      <= vrender;
    obj_start <= 0;
    if( vrender != vr_l ) begin v <= vrender; obj_start <= 1; end
end
wire [ 8:0] so_addr;
wire [13:0] so_din;
wire [12:0] pa_q, pb_q;
wire        sa_q, sb_q;
wire        so_we, so_shwe, obj_busy;
reg  [ 8:0] clr_addr;
reg         clr_we;
wire        eng_a = ~v[0];
wire [ 8:0] sx8   = H + 9'd8;
always @(posedge clk) begin
    clr_we <= pxl_cen;
    if( pxl_cen ) clr_addr <= sx8;
end

jthotchase_obj u_obj(
    .rst      ( rst       ), .clk( clk ), .vdump( vdump ), .start( obj_start ), .v( v + 9'd8 ), .busy( obj_busy ),
    .ram_addr ( spr_ra    ), .ram_q( spr_q ),
    .rom_addr ( spr_addr  ), .rom_cs( spr_cs ), .rom_data( spr_data ), .rom_ok( spr_ok ),
    .lb_addr  ( so_addr   ), .lb_din( so_din ), .lb_we( so_we ), .lb_shwe( so_shwe ),
    .en       ( 1'b1      )
);

jtframe_dual_ram #(.DW(13),.AW(9)) u_lbpa(
    .clk0(clk), .data0( eng_a ? so_din[13:1] : 13'd0 ), .addr0( eng_a ? so_addr : clr_addr ),
                .we0  ( eng_a ? so_we : clr_we ), .q0(),
    .clk1(clk), .data1(13'd0), .addr1( sx8 ), .we1(1'b0), .q1(pa_q) );
jtframe_dual_ram #(.DW(13),.AW(9)) u_lbpb(
    .clk0(clk), .data0( !eng_a ? so_din[13:1] : 13'd0 ), .addr0( !eng_a ? so_addr : clr_addr ),
                .we0  ( !eng_a ? so_we : clr_we ), .q0(),
    .clk1(clk), .data1(13'd0), .addr1( sx8 ), .we1(1'b0), .q1(pb_q) );
jtframe_dual_ram #(.DW(1),.AW(9)) u_lbsa(
    .clk0(clk), .data0( eng_a ? so_din[0] : 1'b0 ), .addr0( eng_a ? so_addr : clr_addr ),
                .we0  ( eng_a ? so_shwe : clr_we ), .q0(),
    .clk1(clk), .data1(1'b0), .addr1( sx8 ), .we1(1'b0), .q1(sa_q) );
jtframe_dual_ram #(.DW(1),.AW(9)) u_lbsb(
    .clk0(clk), .data0( !eng_a ? so_din[0] : 1'b0 ), .addr0( !eng_a ? so_addr : clr_addr ),
                .we0  ( !eng_a ? so_shwe : clr_we ), .q0(),
    .clk1(clk), .data1(1'b0), .addr1( sx8 ), .we1(1'b0), .q1(sb_q) );
wire [12:0] spr_pq  = eng_a ? pb_q : pa_q;
wire        spr_sq  = eng_a ? sb_q : sa_q;
wire        spr_op  = spr_pq[12];
wire [11:0] spr_pxl = spr_pq[11:0] | { spr_sq, 11'd0 };
wire        spr_sh  = spr_sq;

`ifdef SIMULATION

reg ovr1_l=0, ovr2_l=0, ovr3_l=0;
always @(posedge clk) begin
    if( obj_start && obj_busy ) $display("OVERRUN sprites linea %0d", v);
    ovr1_l <= ovr1; ovr2_l <= ovr2; ovr3_l <= ovr3;
    if( ovr1 && !ovr1_l ) $display("OVERRUN PSAC#1 (linea %0d)", vrender);
    if( ovr2 && !ovr2_l ) $display("OVERRUN PSAC#2 (linea %0d)", vrender);
    if( ovr3 && !ovr3_l ) $display("OVERRUN carretera (linea %0d)", vrender);
end

integer sw_first=-1, sw_last=-1, sw_n=0;
reg lvbl_sl=0;
always @(posedge clk) begin
    if( |spr_we ) begin
        if( sw_first<0 ) sw_first = vdump;
        sw_last = vdump; sw_n = sw_n+1;
    end
    lvbl_sl <= lvbl_t;
    if( !lvbl_t && lvbl_sl ) begin
        if( sw_n>0 ) $display("SPRW %0d escrituras, lineas %0d..%0d (PRE_LINE del motor de sprites)", sw_n, sw_first, sw_last);
        sw_first = -1; sw_last = -1; sw_n = 0;
    end
end
`endif

jthotchase_colmix u_colmix(
    .clk      ( clk       ), .pxl_cen ( pxl_cen  ), .video_on( video_on ), .gfx_en( gfx_en ),
    .bg_pxl   ( bg_pxl    ), .bg_ok   ( bg_ok    ),
    .rd_pxl   ( rd_pxl    ), .rd_ok   ( rd_ok    ),
    .spr_pxl  ( spr_pxl   ), .spr_op  ( spr_op   ), .spr_sh( spr_sh ),
    .fg_pxl   ( fg_pxl    ), .fg_ok   ( fg_ok    ),
    .pal_addr ( pal_ra    ), .pal_q   ( pal_q    ),
    .hil_addr ( hil_ra    ), .hil_q   ( hil_q    ),
    .red      ( red       ), .green   ( green    ), .blue( blue )
);

endmodule
