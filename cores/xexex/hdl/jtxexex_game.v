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
    Date: 23-8-2024 */

module jtxexex_game(
    `include "jtframe_game_ports.inc"
);

/* verilator tracing_off */
wire        snd_irq, rmrd, rst8, dma_bsy,
            pal_cs, cpu_we, tilesys_cs, tilereg_cs, objsys_cs, pcu_cs, alpha_cs, mute, objcha_n,
            vdtac, tile_irqn, snd_wrn, alpha_off,
            lvcram_cs, lvcreg_cs, lvcrom_cs, lvc_cpu_ok,
            objreg_cs, pair_we;
wire [15:0] pal_dout, oram_dout, tilesys_dout, lvc_dout;
wire [15:0] video_dumpa;
wire [ 8:0] vdump;
wire [22:2] lyro_addr_obj;
reg  [ 7:0] debug_mux;
wire [ 7:0] snd2main, pair_dout,
            st_main, st_video, st_snd;
wire [ 1:0] oram_we;

assign debug_view = debug_mux;
assign ram_we     = cpu_we & ram_cs;
assign ram_addr   = main_addr[15:1];
assign video_dumpa= ioctl_addr[15:0]-16'h80;

assign lyro_addr  = lyro_addr_obj[21:2];

localparam [25:0] LVC_ST  = 26'h4E0000,
                  LVCO_ST = 26'h180000;
wire [25:0] lvc_rel = ioctl_addr - LVC_ST;

always @* begin
    pre_addr = ioctl_addr;
    if( !ioctl_ram && ioctl_addr >= LVC_ST && ioctl_addr < LVC_ST + 26'h80000 )
        pre_addr = (lvc_rel[2] ? LVCO_ST : LVC_ST) + {8'd0, lvc_rel[18:3], lvc_rel[1:0]};
end

always @(posedge clk) begin
    case( debug_bus[7:6] )
        0: debug_mux <= st_main;
        1: debug_mux <= st_video;
        2: debug_mux <= st_snd;
        3: debug_mux <= { mute, 7'b0 };
        default: debug_mux <= 0;
    endcase
end

`ifdef SIMULATION

reg        snd_ok_d, lvbl_sd;
reg [16:0] snd_addr_d;
reg [15:0] snd_lat_cyc;
reg        snd_wait;
integer    snd_nreq=0, snd_latmax=0, snd_nfr=0;
real       snd_latsum=0.0;
always @(posedge clk) begin
    snd_ok_d <= snd_ok; lvbl_sd <= LVBL; snd_addr_d <= snd_addr;
    if( snd_cs && (snd_addr!=snd_addr_d || !snd_wait) && !snd_ok ) begin
        if( !snd_wait ) begin snd_wait <= 1; snd_lat_cyc <= 0; snd_nreq = snd_nreq+1; end
    end
    if( snd_wait ) snd_lat_cyc <= snd_lat_cyc + 16'd1;
    if( snd_wait && snd_ok ) begin
        snd_wait <= 0; snd_latsum = snd_latsum + snd_lat_cyc;
        if( snd_lat_cyc > snd_latmax ) snd_latmax = snd_lat_cyc;
    end
    if( ~LVBL & lvbl_sd ) begin
        snd_nfr = snd_nfr+1;
        if( snd_nfr[3:0]==0 )
            $display("[SNDLAT] frame=%0d reqs=%0d avg=%0.2f max=%0d (clk 48 MHz; limite de la puerta del POST ~45 de media)",
                snd_nfr, snd_nreq, (snd_nreq>0)?(snd_latsum/snd_nreq):0.0, snd_latmax);
    end
end
initial snd_wait = 0;
`endif

/* verilator tracing_off */
xexex_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .LVBL           ( LVBL          ),
    .vdump          ( vdump         ),

    .cpu_we         ( cpu_we        ),
    .cpu_dout       ( ram_din       ),
    .vdtac          ( vdtac         ),
    .tile_irqn      ( tile_irqn     ),

    .main_addr      ( main_addr     ),
    .rom_data       ( main_data     ),
    .rom_cs         ( main_cs       ),
    .rom_ok         ( main_ok       ),

    .ram_dsn        ( ram_dsn       ),
    .ram_dout       ( ram_data      ),
    .ram_cs         ( ram_cs        ),
    .ram_ok         ( ram_ok        ),

    .cab_1p         ( cab_1p        ),
    .coin           ( coin          ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .service        ( {4{service}}  ),

    .vram_dout      ( tilesys_dout  ),
    .oram_dout      ( oram_dout     ),
    .pal_dout       ( pal_dout      ),

    .lvcram_cs      ( lvcram_cs     ),
    .lvcreg_cs      ( lvcreg_cs     ),
    .lvcrom_cs      ( lvcrom_cs     ),
    .lvc_ok         ( lvc_cpu_ok    ),
    .lvc_dout       ( lvc_dout      ),

    .rmrd           ( rmrd          ),
    .dma_bsy        ( dma_bsy       ),
    .objreg_cs      ( objreg_cs     ),
    .objcha_n       ( objcha_n      ),
    .alpha_off      ( alpha_off     ),

    .obj_cs         ( objsys_cs     ),
    .vram_cs        ( tilesys_cs    ),
    .tilereg_cs     ( tilereg_cs    ),
    .alpha_cs       ( alpha_cs      ),
    .pal_cs         ( pal_cs        ),
    .pcu_cs         ( pcu_cs        ),

    .sndon          ( snd_irq       ),
    .snd2main       ( snd2main      ),
    .snd_wrn        ( snd_wrn       ),
    .mute           ( mute          ),
    .pair_we        ( pair_we       ),
    .pair_dout      ( pair_dout     ),

    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),

    .dip_pause      ( dip_pause     ),
    .dip_test       ( dip_test      ),

    .st_dout        ( st_main       ),
    .debug_bus      ( debug_bus     )
);

assign oram_we   = ~ram_dsn & {2{cpu_we}};

/* verilator tracing_off */
xexex_video u_video (
    .rst            ( rst           ),
    .rst8           ( rst8          ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .pxl2_cen       ( pxl2_cen      ),
    .vmode          ( status[14:13] ),

    .tile_irqn      ( tile_irqn     ),
    .tile_nmin      (               ),

    .lhbl           ( LHBL          ),
    .lvbl           ( LVBL          ),
    .hs             ( HS            ),
    .vs             ( VS            ),
    .hdump          (               ),
    .vdump          ( vdump         ),
    .lyro_pxl_o     (               ),
    .flip           ( dip_flip      ),

    .cpu_we         ( cpu_we        ),
    .cpu_addr       (main_addr[16:1]),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( ram_din       ),

    .oram_we        ( oram_we       ),
    .dma_bsy        ( dma_bsy       ),

    .objsys_cs      ( objsys_cs     ),
    .objreg_cs      ( objreg_cs     ),
    .objcha_n       ( objcha_n      ),
    .tilesys_cs     ( tilesys_cs    ),
    .tilereg_cs     ( tilereg_cs    ),
    .lvcram_cs      ( lvcram_cs     ),
    .lvcreg_cs      ( lvcreg_cs     ),
    .lvcrom_cs      ( lvcrom_cs     ),
    .lvc_dout       ( lvc_dout      ),
    .lvc_cpu_ok     ( lvc_cpu_ok    ),
    .lvc_addr       ( lvc_addr      ),
    .lvc_cs         ( lvc_cs        ),
    .lvc_data       ( lvc_data      ),
    .lvc_ok         ( lvc_ok        ),
    .lvco_addr      ( lvco_addr     ),
    .lvco_cs        ( lvco_cs       ),
    .lvco_data      ( lvco_data     ),
    .lvco_ok        ( lvco_ok       ),
    .alpha_off      ( alpha_off     ),
    .alpha_cs       ( alpha_cs      ),
    .pal_cs         ( pal_cs        ),
    .pcu_cs         ( pcu_cs        ),
    .vdtac          ( vdtac         ),
    .tilesys_dout   ( tilesys_dout  ),
    .objsys_dout    ( oram_dout     ),
    .pal_dout       ( pal_dout      ),
    .rmrd           ( rmrd          ),

    .scr_addr       ( scr_addr      ),
    .scr_data       ( scr_data      ),
    .scr_cs         ( scr_cs        ),
    .scr_ok         ( scr_ok        ),
    .lyro_addr      ( lyro_addr_obj ),
    .lyro_data      ( lyro_data     ),
    .lyro_cs        ( lyro_cs       ),
    .lyro_ok        ( lyro_ok       ),

    .dim            (  3'b0         ),
    .dimmod         (  1'b0         ),
    .dimpol         (  1'b0         ),

    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),

    .debug_bus      ( debug_bus     ),
    .ioctl_addr     ( video_dumpa   ),
    .ioctl_din      ( ioctl_din     ),
    .ioctl_ram      ( ioctl_ram     ),
    .gfx_en         ( gfx_en        ),
    .st_dout        ( st_video      )
);

/* verilator tracing_on */
xexex_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_8      ( cen_8         ),
    .cen_4      ( cen_4         ),
    .cen_2      ( cen_2         ),
    .cen_pcm    ( cen_pcm       ),

    .pair_we    ( pair_we       ),
    .pair_dout  ( pair_dout     ),

    .main_dout  ( ram_din[7:0]  ),
    .main_din   ( snd2main      ),
    .main_addr  ( main_addr[4:1]),
    .main_rnw   ( snd_wrn       ),
    .snd_irq    ( snd_irq       ),

    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),

    .pcm_addr   ( pcm_addr      ),
    .pcm_dout   ( pcm_data      ),
    .pcm_cs     ( pcm_cs        ),
    .pcm_ok     ( pcm_ok        ),

    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm_l      ( pcm_l         ),
    .pcm_r      ( pcm_r         ),

    .debug_bus  ( debug_bus     ),
    .st_dout    ( st_snd        )
);

endmodule
