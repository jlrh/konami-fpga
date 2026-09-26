/*  blswhstl — top del core, contrato jtframe.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module jtblswhstl_game(
    `include "jtframe_game_ports.inc"
);

/* verilator tracing_off */
wire        rom_cs, oram_cs, objreg_cs, pal_cs, tile_cs,
            pcu_cs, k054000_cs, watchdog_cs,
            sndirq, snd_wrn, cpu_we, vdtac, dma_bsy, tile_irqn, flip, rst8;
wire [15:0] cpu_dout, oram_dout, objreg_dout, pal_dout, tile_dout;
wire        rmrd, rombank;
wire [ 7:0] k054000_dout;
wire [ 7:0] snd_dout, snd2main, st_main, st_video;
wire [22:2] lyro_addr_v;
wire [ 7:0] red_v, green_v, blue_v;
wire [13:1] oram_addr;
wire [ 1:0] oram_we;
wire [15:0] oram_din;

assign ram_addr = main_addr[13:1];
assign ram_we   = cpu_we & ram_cs;
wire [15:0] ram_data_m;
`ifdef BL_CHEAT_VIDAS

wire        cheat_on = debug_bus[7];
wire        lv_sel   = ram_cs & (ram_addr==13'h04B) & ~ram_dsn[1];
wire        lv_wr    = lv_sel &  cpu_we;
wire        lv_rd    = lv_sel & ~cpu_we;
wire [ 7:0] rd_hi    = ram_data[15:8];
wire        rd_low   = (rd_hi==8'd1) | (rd_hi==8'd2);
wire        wr_low   = (cpu_dout[15:8]==8'd1) | (cpu_dout[15:8]==8'd2);
assign ram_data_m = (cheat_on & lv_rd & rd_low) ? { 8'd3, ram_data[7:0] } : ram_data;
assign ram_din    = (cheat_on & lv_wr & wr_low) ? { 8'd3, cpu_dout[7:0] } : cpu_dout;

reg [7:0] t_rd_raw=0, t_wr_first=0, t_wr_last=0, t_wr_cnt=0, t_wr_hit=0, t_rd_forced=0;
reg       t_seen_wr=0, t_seen_rd=0, lv_wr_l=0, fr_l=0, wr_low_l=0;
wire      forced_now = cheat_on & lv_rd & ram_ok & rd_low;
always @(posedge clk) begin
    lv_wr_l  <= lv_wr;
    fr_l     <= forced_now;
    wr_low_l <= wr_low;
    if( lv_rd & ram_ok ) begin t_rd_raw <= rd_hi; t_seen_rd <= 1'b1; end
    if( forced_now & ~fr_l & ~&t_rd_forced ) t_rd_forced <= t_rd_forced + 8'd1;
    if( lv_wr ) begin
        t_wr_last <= cpu_dout[15:8];
        t_seen_wr <= 1'b1;
        if( !lv_wr_l ) begin
            t_wr_first <= cpu_dout[15:8];
            if( ~&t_wr_cnt ) t_wr_cnt <= t_wr_cnt + 8'd1;
        end
    end
    if( lv_wr_l & ~lv_wr & wr_low_l & ~&t_wr_hit ) t_wr_hit <= t_wr_hit + 8'd1;
end
reg [7:0] st_cheat;
always @* case( debug_bus[3:0] )
    4'd0: st_cheat = { cheat_on, t_seen_wr, t_seen_rd, 5'd0 };
    4'd1: st_cheat = t_rd_raw;
    4'd2: st_cheat = t_wr_first;
    4'd3: st_cheat = t_wr_last;
    4'd4: st_cheat = t_wr_cnt;
    4'd5: st_cheat = t_wr_hit;
    4'd6: st_cheat = t_rd_forced;
    default: st_cheat = 8'hA5;
endcase
`else
assign ram_din    = cpu_dout;
assign ram_data_m = ram_data;
`endif

assign obj_addr = lyro_addr_v[19:2];

assign red   = red_v  [7:3];
assign green = green_v[7:3];
assign blue  = blue_v [7:3];

function [13:1] conv13( input [13:1] a );
    conv13 = { a[6:5], a[1], a[13:7], a[4:2] };
endfunction
assign oram_addr = conv13( main_addr[13:1] );
assign oram_we   = {2{oram_cs & cpu_we}} & ~ram_dsn;
assign oram_din  = cpu_dout;

k054000 u_k054000(
    .rst    ( rst               ),
    .clk    ( clk               ),
    .cs     ( k054000_cs        ),
    .addr   ( main_addr[5:1]    ),
    .we     ( cpu_we & ~ram_dsn[0] ),
    .din    ( cpu_dout[7:0]     ),
    .dout   ( k054000_dout      )
);

`ifdef BL_CHEAT_VIDAS
assign debug_view = debug_bus[6] ? st_video : st_cheat;
`else
assign debug_view = debug_bus[6] ? st_video : st_main;
`endif

wire [3:0] gfx_en_eff = gfx_en;

/* verilator tracing_off */
blswhstl_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .LVBL           ( LVBL          ),

    .main_addr      ( main_addr     ),
    .rom_data       ( main_data     ),
    .rom_cs         ( main_cs       ),
    .rom_ok         ( main_ok       ),
    .ram_dout       ( ram_data_m    ),
    .ram_cs         ( ram_cs        ),
    .ram_ok         ( ram_ok        ),
    .ram_dsn        ( ram_dsn       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),

    .oram_cs        ( oram_cs       ),
    .objreg_cs      ( objreg_cs     ),
    .pal_cs         ( pal_cs        ),
    .tile_cs        ( tile_cs       ),
    .pcu_cs         ( pcu_cs        ),
    .k054000_cs     ( k054000_cs    ),
    .watchdog_cs    ( watchdog_cs   ),

    .snd_wrn        ( snd_wrn       ),
    .snd_dout       ( snd_dout      ),
    .snd2main       ( snd2main      ),
    .sndirq         ( sndirq        ),

    .oram_dout      ( oram_dout     ),
    .objreg_dout    ( oram_dout     ),
    .tile_dout      ( tile_dout     ),
    .k054000_dout   ( k054000_dout  ),
    .pal_dout       ( pal_dout      ),
    .vdtac          ( vdtac         ),

    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),

    .rmrd           ( rmrd          ),
    .tile_rombank   ( rombank       ),

    .tile_irqn      ( tile_irqn     ),

    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .cab_1p         ( cab_1p        ),
    .coin           ( coin          ),
    .service        ( {4{service}}  ),
    .dip_pause      ( dip_pause     ),
    .dip_test       ( dip_test      ),
    .st_dout        ( st_main       ),
    .debug_bus      ( debug_bus     )
);

/* verilator tracing_on */
blswhstl_video u_video(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .pxl2_cen       ( pxl2_cen      ),

    .lhbl           ( LHBL          ),
    .lvbl           ( LVBL          ),
    .hs             ( HS            ),
    .vs             ( VS            ),
    .hdump          (               ),
    .vdump          (               ),
    .lyro_pxl_o     (               ),

    .tile_irqn      ( tile_irqn     ),
    .tile_nmin      (               ),

    .oram_addr      ( oram_addr     ),
    .oram_we        ( oram_we       ),
    .oram_din       ( oram_din      ),

    .cpu_addr       ( main_addr[16:1]),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),

    .pcu_cs         ( pcu_cs        ),
    .alpha_cs       ( 1'b0          ),
    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),
    .tile_dout      ( tile_dout     ),

    .dma_bsy        ( dma_bsy       ),
    .objsys_dout    ( oram_dout     ),
    .objsys_cs      ( oram_cs       ),
    .objreg_cs      ( objreg_cs     ),

    .objreg_byte    ( 1'b1          ),
    .objcha_n       ( 1'b1          ),

    .vdtac          ( vdtac         ),
    .tile_cs        ( tile_cs       ),
    .rst8           ( rst8          ),

    .rmrd           ( rmrd          ),
    .rombank        ( rombank       ),

    .objdx          ( 9'd2          ),
    .objdy          ( 10'd0         ),
    .flip           ( flip          ),

    .lyrf_addr      ( lyrf_addr     ),
    .lyra_addr      ( lyra_addr     ),
    .lyrb_addr      ( lyrb_addr     ),
    .lyrf_cs        ( lyrf_cs       ),
    .lyra_cs        ( lyra_cs       ),
    .lyrb_cs        ( lyrb_cs       ),
    .lyrf_data      ( lyrf_data     ),
    .lyra_data      ( lyra_data     ),
    .lyrb_data      ( lyrb_data     ),
    .lyrf_ok        ( lyrf_ok       ),
    .lyra_ok        ( lyra_ok       ),
    .lyrb_ok        ( lyrb_ok       ),

    .lyro_addr      ( lyro_addr_v   ),
    .lyro_cs        ( obj_cs        ),
    .lyro_ok        ( obj_ok        ),
    .lyro_data      ( obj_data      ),

    .red            ( red_v         ),
    .green          ( green_v       ),
    .blue           ( blue_v        ),

    .ioctl_addr     ( ioctl_addr[15:0] ),
    .ioctl_ram      ( ioctl_ram     ),
    .ioctl_din      ( ioctl_din     ),
    .gfx_en         ( gfx_en_eff    ),
    .debug_bus      ( debug_bus     ),
    .st_dout        ( st_video      )
);

/* verilator tracing_on */
blswhstl_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),

    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .cen_pcm    ( cen_pcm       ),

    .main_dout  ( snd_dout      ),
    .main_din   ( snd2main      ),
    .main_wrn   ( snd_wrn       ),
    .main_addr  ( main_addr[2:1]),
    .snd_irq    ( sndirq        ),

    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),

    .pcma_addr  ( pcma_addr     ), .pcma_cs( pcma_cs ), .pcma_data( pcma_data ), .pcma_ok( pcma_ok ),
    .pcmb_addr  ( pcmb_addr     ), .pcmb_cs( pcmb_cs ), .pcmb_data( pcmb_data ), .pcmb_ok( pcmb_ok ),
    .pcmc_addr  ( pcmc_addr     ), .pcmc_cs( pcmc_cs ), .pcmc_data( pcmc_data ), .pcmc_ok( pcmc_ok ),
    .pcmd_addr  ( pcmd_addr     ), .pcmd_cs( pcmd_cs ), .pcmd_data( pcmd_data ), .pcmd_ok( pcmd_ok ),

    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),

    .pcm_l      ( pcm_r         ),
    .pcm_r      ( pcm_l         ),

    .snd_en     ( snd_en        ),
    .debug_bus  ( debug_bus     ),
    .st_dout    (               )
);

endmodule
