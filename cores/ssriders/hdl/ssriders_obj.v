/*  ssriders — sprites K053244/K053245.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module ssriders_obj #(parameter
    RAMW   = 13,
    HFLIP_OFFSET = 0,
    SHADOW = 1
)(
    input             rst,
    input             clk,

    input             pxl_cen,
    input             pxl2_cen,
    input      [ 9:0] hdump,

    input      [ 8:0] vdump,
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
    input      [15:0] ioctl_addr,

    output     [ 7:0] dump_ram,
    output     [ 7:0] dump_reg,
    input      [ 7:0] debug_bus,

    output     [ 7:0] dbg_cnt,
    output     [ 7:0] dbg_flags,

    output     [ 7:0] dbg_cfg,
    output     [ 7:0] dbg_dmatrig_cnt
);

localparam SHADOW_PEN = SHADOW[0]==1 ? 4'd15 : 4'd0;

wire        pre_shd;
wire [ 3:0] pen_eff;
wire [15:0] ram_data, dma_data;
wire [22:2] pre_addr;
wire [ 7:0] cfg_raw;
wire        dmatrig_raw;
wire [21:1] rmrd_addr;
wire [13:1] dma_addr;
wire [15:0] pre_pxl;

wire        dr_start, dr_busy;
wire [15:0] code;
wire [ 6:0] attr;
wire        hflip, vflip, hz_keep, pre_cs;
wire [ 9:0] hpos;
wire [ 3:0] ysub;
wire [11:0] hzoom;
wire        pen15;

function [5:0] tile_swizzle( input [5:0] b );
    tile_swizzle = { b[5], b[3], b[1], b[4], b[2], b[0] };
endfunction

assign rom_cs    = ~objcha_n | pre_cs;
assign rom_addr  = objcha_n
    ? { pre_addr[21], pre_addr[20:13], tile_swizzle(pre_addr[12:7]),
        pre_addr[5], pre_addr[6], pre_addr[4:2] }
    : rmrd_addr[21:2];

assign cpu_din   = objcha_n ? ram_data
                            : (rmrd_addr[1] ? rom_data[31:16] : rom_data[15:0]);

assign pen15   = &pre_pxl[3:0];
assign pen_eff = (|pre_pxl[15:14] && pen15) ? 4'd0 : pre_pxl[3:0];

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
                          && s30_frame>=16'd1150 && s30_frame<=16'd1250)
    $display("SHD-SOLID frame=%0d hdump=%0d vdump=%0d pen=%0d pre_pxl=%04x",
              s30_frame, hdump, vdump, pre_pxl[3:0], pre_pxl);
`endif

k053244 #(.HFLIP_OFFSET(HFLIP_OFFSET)
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

    .hdump      ( hdump[8:0] ),
    .vdump      ( vdump     ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),

    .pxl        ( pxl       ),
    .shd        ( pre_shd   ),

    .dr_start   ( dr_start  ),
    .dr_busy    ( dr_busy   ),

    .debug_bus  ( debug_bus ),
    .st_addr    ( ioctl_ram ? ioctl_addr[7:0] : debug_bus ),
    .st_dout    ( dump_reg  ),
    .dbg_cfg     ( cfg_raw     ),
    .dbg_dmatrig ( dmatrig_raw )
);

jtframe_objdraw #(
    .SHADOW(SHADOW),.SHADOW_PEN(SHADOW_PEN),.SW(2),.HFIX(0),
    .AW(10),.CW(16),.PW(4+10+2),.LATCH(1),.SWAPH(1),
    .ZW(12),.ZI(6),.ZENLARGE(1),
    .FLIP_OFFSET(9'h12),.KEEP_OLD(0)
) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( hdump         ),

    .draw       ( dr_start      ),
    .busy       ( dr_busy       ),
    .code       ( code          ),
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

wire ram_dump_sel = ioctl_ram & (ioctl_addr[15:14]==2'b00);
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
    .sel_b  ( ram_dump_sel )
);

localparam DBG_STUCK_TH = 21'd400_000;

reg [ 7:0] dbg_cnt_run=0;
reg [ 7:0] dbg_cnt_r=0;
reg        dbg_lvbl_l=1'b1;
reg [20:0] dbg_drbusy_timer=0, dbg_romwait_timer=0;
reg        dbg_drbusy_stuck=1'b0, dbg_romok_stuck=1'b0;

reg  [ 7:0] dbg_dmatrig_run=0, dbg_dmatrig_r=0;
always @(posedge clk) begin
    dbg_lvbl_l <= lvbl;
    if( dr_start && dbg_cnt_run!=8'hff ) dbg_cnt_run <= dbg_cnt_run + 8'd1;
    if( dmatrig_raw && dbg_dmatrig_run!=8'hff ) dbg_dmatrig_run <= dbg_dmatrig_run + 8'd1;
    if( dbg_lvbl_l && !lvbl ) begin
        dbg_cnt_r     <= dbg_cnt_run;
        dbg_cnt_run   <= 8'd0;
        dbg_dmatrig_r   <= dbg_dmatrig_run;
        dbg_dmatrig_run <= 8'd0;
    end
    dbg_drbusy_timer <= dr_busy ? dbg_drbusy_timer + 21'd1 : 21'd0;
    if( dbg_drbusy_timer > DBG_STUCK_TH ) dbg_drbusy_stuck <= 1'b1;
    dbg_romwait_timer <= (rom_cs && !rom_ok) ? dbg_romwait_timer + 21'd1 : 21'd0;
    if( dbg_romwait_timer > DBG_STUCK_TH ) dbg_romok_stuck <= 1'b1;
end
assign dbg_cnt   = dbg_cnt_r;
assign dbg_flags = { 2'd0, rom_ok, rom_cs, dr_busy, dbg_romok_stuck, dbg_drbusy_stuck };
assign dbg_cfg          = cfg_raw;
assign dbg_dmatrig_cnt  = dbg_dmatrig_r;

`ifdef SSR_PROBE_WIDTH4

integer w4_o0_min=1023, w4_o0_max=0, w4_o1_min=1023, w4_o1_max=0;
integer w4_o0_n=0, w4_o1_n=0;
reg w4_lvbl_l=0;
always @(posedge clk) begin
    w4_lvbl_l <= lvbl;
    if( u_draw.u_gate.buf_we ) begin
        if( u_draw.u_gate.dr_xpos<500 ) begin
            if(u_draw.u_gate.buf_addr<w4_o0_min) w4_o0_min=u_draw.u_gate.buf_addr;
            if(u_draw.u_gate.buf_addr>w4_o0_max) w4_o0_max=u_draw.u_gate.buf_addr;
            w4_o0_n=w4_o0_n+1;
        end else begin
            if(u_draw.u_gate.buf_addr<w4_o1_min) w4_o1_min=u_draw.u_gate.buf_addr;
            if(u_draw.u_gate.buf_addr>w4_o1_max) w4_o1_max=u_draw.u_gate.buf_addr;
            w4_o1_n=w4_o1_n+1;
        end
    end
    if( lvbl && !w4_lvbl_l ) begin
        $display("SSR-WIDTH4 obj0(xpos<500) addr[%0d..%0d] n=%0d | obj1(xpos>=500) addr[%0d..%0d] n=%0d",
            w4_o0_min,w4_o0_max,w4_o0_n, w4_o1_min,w4_o1_max,w4_o1_n);
        w4_o0_min=1023; w4_o0_max=0; w4_o0_n=0;
        w4_o1_min=1023; w4_o1_max=0; w4_o1_n=0;
    end
end
`endif

`ifdef OBJDIAG

integer n_drstart=0, n_rdnz=0;
reg [9:0] hpmin=10'h3ff, hpmax=0;
reg [9:0] rdmin=10'h3ff, rdmax=0, hsmin=10'h3ff, hsmax=0;
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
