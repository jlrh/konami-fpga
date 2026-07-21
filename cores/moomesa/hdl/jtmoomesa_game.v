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

module jtmoomesa_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

// localparam [2:0] XMEN     = 3'd2;

/* verilator tracing_off */
wire        snd_irq, rmrd, rst8, dma_bsy,
            pal_cs, cpu_we, tilesys_cs, tilereg_cs, objsys_cs, pcu_cs, alpha_cs, mute, objcha_n,
            cpu_rnw, vdtac, tile_irqn, tile_nmin, snd_wrn,
            objreg_cs, pair_we;
wire [15:0] pal_dout, oram_dout, tilesys_dout;
wire [15:0] video_dumpa;
wire [13:1] oram_addr;
reg  [ 7:0] debug_mux;
// reg  [ 2:0] game_id;
// reg         cowboys;
wire [ 7:0] snd2main,
            obj_dout, snd_latch, pair_dout,
            st_main, st_video, st_snd;
wire [ 1:0] oram_we;

assign debug_view = debug_mux;
assign ram_we     = cpu_we & ram_cs;
assign ram_addr   = main_addr[15:1];
assign video_dumpa= ioctl_addr[15:0]-16'h80; // subtract NVRAM offset

always @(posedge clk) begin
    debug_mux <= st_snd;
    // case( debug_bus[7:6] )
    //     0: debug_mux <= st_main;
    //     1: debug_mux <= st_video;
    //     2: debug_mux <= st_snd;
    //     3: debug_mux <= { mute, /*cowboys,*/ 7'b0 };
    //     default: debug_mux <= 0;
    // endcase
end

`ifdef SIMULATION
// ⭐ SESION 19: SONDA DE LATENCIA SDRAM DEL BUS `scr` (tile ROM) con el controlador SDRAM REAL de jtframe.
// Mide los clk desde scr_cs↑ (peticion) hasta scr_ok↑ (dato listo). Dice la latencia EFECTIVA real por
// lectura -> comparar con la rodilla del modelo por-lectura del vfull (L≈5). Si la real << 5, el fetch
// cabe; si >= 5, el tilemap baja-res es throughput real. Reqs/frame /264 lineas = lecturas/linea.
reg        scr_cs_d, scr_ok_d, lvbl_d;
reg [15:0] scr_lat_cyc;
integer    scr_nreq, scr_nok, scr_latmax, scr_lb0, scr_lb4, scr_lb8, scr_lb16, scr_lb32, scr_nframe;
real       scr_latsum;
initial begin scr_nreq=0; scr_nok=0; scr_latsum=0.0; scr_latmax=0; scr_nframe=0;
    scr_lb0=0; scr_lb4=0; scr_lb8=0; scr_lb16=0; scr_lb32=0; end
always @(posedge clk) begin
    scr_cs_d<=scr_cs; scr_ok_d<=scr_ok; lvbl_d<=LVBL;
    if(scr_cs & ~scr_cs_d) begin scr_lat_cyc<=16'd0; scr_nreq=scr_nreq+1; end
    else scr_lat_cyc<=scr_lat_cyc+16'd1;
    if(scr_ok & ~scr_ok_d) begin
        scr_nok=scr_nok+1; scr_latsum=scr_latsum+scr_lat_cyc;
        if(scr_lat_cyc>scr_latmax) scr_latmax=scr_lat_cyc;
        if(scr_lat_cyc<4)       scr_lb0 =scr_lb0 +1;
        else if(scr_lat_cyc<8)  scr_lb4 =scr_lb4 +1;
        else if(scr_lat_cyc<16) scr_lb8 =scr_lb8 +1;
        else if(scr_lat_cyc<32) scr_lb16=scr_lb16+1;
        else                    scr_lb32=scr_lb32+1;
    end
    if(~LVBL & lvbl_d) begin   // flanco de bajada de LVBL = fin de frame visible -> volcar stats
        scr_nframe=scr_nframe+1;
        $display("[SCRLAT] frame=%0d reqs=%0d oks=%0d avg=%0.2f max=%0d reqs/linea=%0.1f hist[<4 <8 <16 <32 >=32]= %0d %0d %0d %0d %0d",
            scr_nframe, scr_nreq, scr_nok, (scr_nok>0)?(scr_latsum/scr_nok):0.0, scr_latmax,
            (scr_nframe>0)?(scr_nreq*1.0/scr_nframe/264.0):0.0, scr_lb0,scr_lb4,scr_lb8,scr_lb16,scr_lb32);
    end
end
`endif

/*always @(posedge clk) begin
    if( prog_addr[3:0]==15 && prog_we && header ) game_id <= prog_data[2:0];
    cowboys     <= game_id == XMEN;
end
*/
/* verilator tracing_off */
cowboys_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .LVBL           ( LVBL          ),

    .cpu_we         ( cpu_we        ),
    .cpu_dout       ( ram_din       ),
    .vdtac          ( vdtac         ),
    .tile_irqn      ( tile_irqn     ),

    .main_addr      ( main_addr     ),
    .rom_data       ( main_data     ),
    .rom_cs         ( main_cs       ),
    .rom_ok         ( main_ok       ),
    // RAM
    .ram_dsn        ( ram_dsn       ),
    .ram_dout       ( ram_data      ),
    .ram_cs         ( ram_cs        ),
    .ram_ok         ( ram_ok        ),
    // cabinet I/O
    .cab_1p         ( cab_1p        ),
    .coin           ( coin          ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .joystick3      ( joystick3     ),
    .joystick4      ( joystick4     ),
    .service        ( {4{service}}  ),

    .vram_dout      ( tilesys_dout  ),
    .oram_dout      ( oram_dout     ),
    .pal_dout       ( pal_dout      ),
    // To video
    .rmrd           ( rmrd          ),
    .dma_bsy        ( dma_bsy       ),
    .objreg_cs      ( objreg_cs     ),
    .objcha_n       ( objcha_n      ),

    .obj_cs         ( objsys_cs     ),
    .vram_cs        ( tilesys_cs    ),
    .tilereg_cs     ( tilereg_cs    ),
    .alpha_cs       ( alpha_cs      ),
    .pal_cs         ( pal_cs        ),
    .pcu_cs         ( pcu_cs        ), // priority mixer
    // To sound
    .sndon          ( snd_irq       ),
    .snd2main       ( snd2main      ),
    .snd_wrn        ( snd_wrn       ),
    .mute           ( mute          ),
    .pair_we        ( pair_we       ),
    .pair_dout      ( pair_dout     ),
    // EEPROM
    .nv_addr        ( nvram_addr    ),
    .nv_dout        ( nvram_dout    ),
    .nv_din         ( nvram_din     ),
    .nv_we          ( nvram_we      ),
    // DIP switches
    .dip_pause      ( dip_pause     ),
    .dip_test       ( dip_test      ),
    // Debug
    .st_dout        ( st_main       ),
    .debug_bus      ( debug_bus     )
);

assign oram_we   = ~ram_dsn & {2{cpu_we}};
assign oram_addr = {main_addr[6:5], main_addr[1], main_addr[13:7], main_addr[4:2]};

/* verilator tracing_off */
cowboys_video u_video (
    .rst            ( rst           ),
    .rst8           ( rst8          ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .pxl2_cen       ( pxl2_cen      ),

    .tile_irqn      ( tile_irqn     ),
    .tile_nmin      (               ),

    .lhbl           ( LHBL          ),
    .lvbl           ( LVBL          ),
    .hs             ( HS            ),
    .vs             ( VS            ),
    .hdump          (               ),   // observabilidad (harness vfull); abiertos en produccion
    .vdump          (               ),
    .lyro_pxl_o     (               ),
    .flip           ( dip_flip      ),
    // GFX - CPU interface
    .cpu_we         ( cpu_we        ),
    .cpu_addr       (main_addr[16:1]),
    .cpu_dsn        ( ram_dsn       ),
    .cpu_dout       ( ram_din       ),

    // Object DMA
    .oram_we        ( oram_we       ),
    .oram_addr      ( oram_addr     ),
    .dma_bsy        ( dma_bsy       ),

    .objsys_cs      ( objsys_cs     ),
    .objreg_cs      ( objreg_cs     ),
    .objcha_n       ( objcha_n      ),
    .tilesys_cs     ( tilesys_cs    ),
    .tilereg_cs     ( tilereg_cs    ),
    .alpha_cs       ( alpha_cs      ),
    .pal_cs         ( pal_cs        ),
    .pcu_cs         ( pcu_cs        ),
    .vdtac          ( vdtac         ),
    .tilesys_dout   ( tilesys_dout  ),
    .objsys_dout    ( oram_dout     ),
    .pal_dout       ( pal_dout      ),
    .rmrd           ( rmrd          ),
    // SDRAM: 1 bus de tile serial (scr) + sprites (lyro)
    .scr_addr       ( scr_addr      ),
    .scr_data       ( scr_data      ),
    .scr_cs         ( scr_cs        ),
    .scr_ok         ( scr_ok        ),
    .lyro_addr      ( lyro_addr     ),
    .lyro_data      ( lyro_data     ),
    .lyro_cs        ( lyro_cs       ),
    .lyro_ok        ( lyro_ok       ),
    // brightness
    .dim            (  3'b0         ),
    .dimmod         (  1'b0         ),
    .dimpol         (  1'b0         ),
    // pixels
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),
    // Debug
    .debug_bus      ( debug_bus     ),
    .ioctl_addr     ( video_dumpa   ),
    .ioctl_din      ( ioctl_din     ),
    .ioctl_ram      ( ioctl_ram     ),
    .gfx_en         ( gfx_en        ),
    .st_dout        ( st_video      )
);

/* verilator tracing_on */
cowboys_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_8      ( cen_8         ),
    .cen_4      ( cen_4         ),
    .cen_2      ( cen_2         ),
    .cen_pcm    ( cen_pcm       ),

    .pair_we    ( pair_we       ),
    .pair_dout  ( pair_dout     ),
    // communication with main CPU
    .main_dout  ( ram_din[7:0]  ),
    .main_din   ( snd2main      ),
    .main_addr  ( main_addr[4:1]),
    .main_rnw   ( snd_wrn       ),
    .snd_irq    ( snd_irq       ),
    // ROM
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    // ADPCM ROM
    .pcm_addr   ( pcm_addr      ),
    .pcm_dout   ( pcm_data      ),
    .pcm_cs     ( pcm_cs        ),
    .pcm_ok     ( pcm_ok        ),
    // Sound output — canales separados FM / PCM (puertos generados desde mem.yaml)
    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm_l      ( pcm_l         ),
    .pcm_r      ( pcm_r         ),
    // Debug
    .debug_bus  ( debug_bus     ),
    .st_dout    ( st_snd        )
);

endmodule
