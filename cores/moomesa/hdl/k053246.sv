/* =============================================================================================
    k053246.sv — FORK PROPIO del motor de sprites (K053246/K053247) de COWBOYS (Moo Mesa).
    Origen: cores/simson/hdl/jt053246.sv  (arbol jtcores, COMPARTIDO con simson/xmen/rungun...).
    Clonado 2026-07-20 (sesion 24). NO es una copia muerta: desde aqui EVOLUCIONA POR SU CUENTA.

    -- POR QUE SE CLONO ------------------------------------------------------------------------
    El modulo compartido PIERDE SPRITES al ratio de reloj real de la placa. Sintoma reportado y
    fotografiado en HW (fase 2, vagon del tren): al personaje le faltan torso y cabeza y los
    enemigos salen cortados, en las lineas donde se amontonan sprites.
    Capturas: debug/cowboys/raw/hw_snaps/20260720_085314/15/16-screen.png

    CAUSA RAIZ (medida): el FSM que recorre la tabla de objetos avanza a **clk/2**
    (original jt053246_scan.sv:95-96 `always @(negedge clk) cen2 <= ~cen2;` + `else if(cen2)`),
    luego los objetos procesables por linea escalan con el ratio de reloj:
       CLKDIV=8 (simulacion) -> 4096 clk/linea -> 2048 pasos -> alcanza el objeto ~0xd3..0xff
       CLKDIV=6 (PLACA REAL) -> 3072 clk/linea -> 1536 pasos -> se queda en el 0x4b (75 de 256)
    Los objetos no alcanzados NO SE DIBUJAN.

    MEDIDO en la escena 14198 (87 sprites, volcada del juego real por el usuario):
       CLKDIV=6  -> 128 de 224 lineas sin terminar -> sim==golden 7.57 %
       CLKDIV=8  ->  28 lineas sin terminar        -> 2.30 %
       CLKDIV=12 ->   0 lineas sin terminar        -> 2.30 %  (suelo = residuo ajeno)
    => es PURO presupuesto de tiempo, no un fallo funcional. La metrica ya existia en el RTL
       ($display "Obj scan did not finish" / "%d uncompleted lines"); nadie la miraba porque al
       ratio 8 de simulacion casi no salta.

    -- POR QUE NO SE ARREGLO EN EL COMPARTIDO --------------------------------------------------
    cores/simson/hdl lo usan otros cores y otros agentes: la regla del proyecto es NO TOCARLO.
    Y el fix puede no ser universal: cada placa Konami monta CUSTOMS DISTINTOS que pueden
    comportarse de otra manera. Se aprende de lo que hay y se vuela libre. Si el hallazgo sirve a
    otros, va por el _inbox del comun -- nunca editando su codigo.

    -- AVISOS ----------------------------------------------------------------------------------
    (1) TRAMPA DE NOMBRES (bug de harness de la ses.19): verilator y quartus resuelven modulos por
        NOMBRE, y el orden `-y` pone simson/hdl ANTES que cowboys/hdl. Un clon con el MISMO nombre
        quedaria SOMBREADO por el original y estarias probando codigo ajeno sin enterarte.
        POR ESO SE RENOMBRO TODO EL ARBOL: jtsimson_obj->cowboys_obj, jt053246*->k053246*.
        NO le devuelvas a ninguno su nombre original.
    (2) El HW ORIGINAL **NO** pierde esos sprites (verificado por el usuario en placa real) => es
        un defecto NUESTRO, no fidelidad. No lo "restaures" creyendo que el juego era asi.
    (3) Estos ficheros .sv/.v deben COPIARSE AL ARBOL jtcores por scripts/_cowboys_sync.sh. Si el
        sync solo copia *.v, los *.sv NO llegan y simularias/sintetizarias la version vieja.
   ============================================================================================= */
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
    Date: 30-7-2023 */

// See JTSIMSON's README.md

module k053246(    // sprite logic
    input             rst,
    input             clk,
    input             pxl2_cen,
    input             pxl_cen,
    input             simson,

    output            ln_done,

    // CPU interface
    input             cs,
    input             cpu_we,
    input      [ 3:0] cpu_addr, // bit 3 only in k44 mode
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,  // only used for MMR in 16-bit mode

    // ROM check by CPU
    output     [22:1] rmrd_addr,

    // External RAM
    output     [13:1] dma_addr, // up to 16 kB
    input      [15:0] dma_data,
    output            dma_bsy,

    // ROM addressing 22 bits in total
    output reg [15:0] code,
    // There are 22 bits communicating both chips on the PCB
    output reg [ 9:0] attr,     // OC pins
    output            hflip,
    output reg        vflip,
    output reg [ 9:0] hpos,
    output     [ 3:0] ysub,
    output reg [11:0] hzoom,
    output reg        hz_keep,

    // base video
    input      [ 8:0] hdump,    // Not inputs in the original, but
    input      [ 8:0] vdump,    // generated internally.
                                // Hdump goes from 20 to 19F, 384 pixels
                                // Vdump goes from F8 to 1FF, 264 lines
    input      [ 9:0] voffset,
    input             lvbl,
    input             hs,

    // shadow
    input      [ 8:0] pxl,
    output reg [ 1:0] shd,

    // indr module / 051937
    output reg        dr_start,
    input             dr_busy,

    // Debug
    input      [ 7:0] debug_bus,
    input      [ 7:0] st_addr,
    output     [ 7:0] st_dout
);
parameter       K55673=0, K55673_DESC_SORT=0, EDGE_TRIGGER=0;
parameter [9:0] HOFFSET   = 10'd62;

localparam [2:0] REG_XOFF  = 0, // X offset
                 REG_YOFF  = 1, // Y offset
                 REG_CFG   = 2; // interrupt control, ROM read
// K55673 seems to have fewer objects. Or maybe the lower half
// is used for the second screen on Run'n Gun (?)
localparam [7:0] SCAN_START = K55673==1 ? 8'h40 : 8'h0;

wire [15:0] scan_even, scan_odd, dma_din;
wire [11:2] scan_addr;
wire [11:1] dma_wr_addr;
wire [ 9:0] xoffset, yoffset;
wire [ 7:0] cfg;
wire        dma_wel, dma_weh, cpu_bsy,
            ghf, gvf, mode8, dma_en, flicker;

assign ghf       = cfg[0]; // global flip
assign gvf       = cfg[1];
assign mode8     = cfg[2]; // guess, use it for 8-bit access on 46/47 pair
assign cpu_bsy   = cfg[3];
assign dma_en    = cfg[4];

k053246_scan #(.HOFFSET(HOFFSET),.SCAN_START(SCAN_START)) u_scan(
    .rst       ( rst        ),
    .clk       ( clk        ),
    .done      ( ln_done    ),
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
    .voffset   ( voffset    ),
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


k053246_dma #(
    .K55673          ( K55673           ),
    .K55673_DESC_SORT( K55673_DESC_SORT ),
    .EDGE_TRIGGER    ( EDGE_TRIGGER     )
)u_dma(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),

    .mode8      ( mode8     ),
    .dma_en     ( dma_en    ),
    .dma_trig   ( 1'b0      ),
    .k44_en     ( 1'b0      ),   // enable k053244/5 mode (default k053246/7)
    .simson     ( simson    ),

    .hs         ( hs        ),
    .lvbl       ( lvbl      ),

    // External RAM
    .dma_addr   ( dma_addr  ), // up to 16 kB
    .dma_data   ( dma_data  ),
    .dma_bsy    ( dma_bsy   ),

    .dma_weh    ( dma_weh   ),
    .dma_wel    ( dma_wel   ),
    .dma_wr_addr(dma_wr_addr),
    .dma_din    ( dma_din   ),

    .flicker    ( flicker   )  // debug
);

k053246_mmr u_mmr(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .k44_en     ( 1'b0      ),
    .cs         ( cs        ),
    .cpu_we     ( cpu_we    ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cfg        ( cfg       ),
    .xoffset    ( xoffset   ),
    .yoffset    ( yoffset   ),
    .rmrd_addr  ( rmrd_addr ),
    .st_addr    ( st_addr   ),
    .st_dout    ( st_dout   )
);

jtframe_dual_ram16 #(.AW(10)) u_even( // 10:0 -> 2kB
    // Port 0: DMA
    .clk0   ( clk            ),
    .data0  ( dma_din        ),
    .addr0  (dma_wr_addr[11:2]),
    .we0    ( {2{dma_wel}}   ),
    .q0     (                ),
    // Port 1: scan
    .clk1   ( clk            ),
    .data1  ( 16'd0          ),
    .addr1  ( scan_addr      ),
    .we1    ( 2'b0           ),
    .q1     ( scan_even      )
);

jtframe_dual_ram16 #(.AW(10)) u_odd( // 10:0 -> 2kB
    // Port 0: DMA
    .clk0   ( clk            ),
    .data0  ( dma_din        ),
    .addr0  (dma_wr_addr[11:2]),
    .we0    ( {2{dma_weh}}   ),
    .q0     (                ),
    // Port 1: scan
    .clk1   ( clk            ),
    .data1  ( 16'd0          ),
    .addr1  ( scan_addr      ),
    .we1    ( 2'b0           ),
    .q1     ( scan_odd       )
);

endmodule
