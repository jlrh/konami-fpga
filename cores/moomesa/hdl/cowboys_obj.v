/* =============================================================================================
    cowboys_obj.v — FORK PROPIO del motor de sprites (K053246/K053247) de COWBOYS (Moo Mesa).
    Origen: cores/simson/hdl/jtsimson_obj.v  (arbol jtcores, COMPARTIDO con simson/xmen/rungun...).
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
    Date: 24-7-2023 */

module cowboys_obj #(parameter
    RAMW      = 12, // 12 -> 8kB
    PACKED    = 1,
    SHADOW    = 0,
    K55673    = 0,
    // K55673 (used with K53246 on Run'n Gun) uses ascending order
    // This is actually programmed on register 12, bit 4, but
    // it is never changed. Other register functions are unknown
    // so I am leaving it static for now
    K55673_DESC_SORT = 0,
    // Set high to trigger DMA on the edge dma_en signal
    EDGE_TRIGGER = 0,
    parameter [9:0] HOFFSET   = 10'd62
)(
    input             rst,
    input             clk,
    output            ln_done,

    input             pxl_cen,
    input             pxl2_cen,
    input             simson,
    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input      [ 9:0] voffset,
    input             hs,
    input             lvbl,

    // CPU interface
    input             ram_cs,
    input             reg_cs,
    input             mmr_we,
    input      [ 3:0] mmr_addr,
    input      [15:0] mmr_din,
    input      [ 1:0] mmr_dsn,

    input      [15:0] ram_din, // 16-bit interface
    input      [ 1:0] ram_we,
    input    [RAMW:1] ram_addr,
    output     [15:0] cpu_din,
    output            dma_bsy,

    // ROM addressing
    output     [22:2] rom_addr,
    input      [31:0] rom_data,
    output            rom_cs,
    input             rom_ok,
    input             objcha_n,

    // pixel output
    output     [ 1:0] shd,      // shadow
    output     [ 4:0] prio,
    output     [ 8:0] pxl,

    // debug
    input      [ 3:0] gfx_en,
    input             ioctl_ram,
    input      [13:0] ioctl_addr,
    output     [ 7:0] dump_ram,
    output     [ 7:0] dump_reg,
    input      [ 7:0] debug_bus
);

localparam SHADOW_PEN = SHADOW[0]==1 ? 4'd15 : 4'd0;

wire [ 1:0] pre_shd;
wire [ 3:0] pen_eff;
wire [15:0] ram_data, dma_data;
wire [22:2] pre_addr;
wire [22:1] rmrd_addr;
wire [13:1] dma_addr;
wire [15:0] pre_pxl;

// Draw module
wire        dr_start, dr_busy;
wire [15:0] code;
wire [ 9:0] attr;     // OC pins
wire        hflip, vflip, hz_keep, pre_cs;
wire [ 9:0] hpos;
wire [ 3:0] ysub;
wire [11:0] hzoom;
wire [31:0] sorted, sort_packed, sort_unpacked;
wire        pen15;

wire scr_hflip, scr_vflip;

// ── SOLAPAMIENTO SCAN <-> DIBUJANTE: PROBADO Y REVERTIDO (ses.25) ───────────────────────────
// `k053246_skid.v` (cola de tiles entre el scan y el dibujante) sigue en el repo pero DESCONECTADO:
// en sim mejoraba (7.57 % -> 3.60 % en 14198/CLKDIV=6) y en PLACA salieron SPRITES FANTASMA.
// El gate de sim era una escena ESTATICA de 1 frame => ciego al movimiento. Ver HANDOFF sesion 26.

assign rom_cs    = ~objcha_n | pre_cs;
assign rom_addr  = !objcha_n ? rmrd_addr[22:2] :
    { pre_addr[22:7], pre_addr[5:2], pre_addr[6] };

assign cpu_din   = !objcha_n ? rmrd_addr[1] ? rom_data[31:16] : rom_data[15:0] :
                    ram_data;

// Shadow understanding so far
// The 053251 color mixer lets shadow pass based on numerical priority only
// and independently of what layer is selected. As the object layer should not
// be drawn directly over a shadow, it looks like the logic must be like this
// - in the LUT the shadow bits are set for the whole sprite
// - when drawing the sprite, if the shadow is enabled and the sprite pen is
//   15 (bits 3:0 high), output the shadow bits but set the pen to 0 (transparent)
// - otherwise, output 0 for shadow bits and let the pen go through unaltered
// - Some bits in upper byte of register 2 are unknown in MAME and could be
//   related to selecting shadow pens
// 053244 (parodius) has 7 palette bits, top 2 used for priority
assign pen15   = &pre_pxl[3:0];
assign pen_eff = (pre_pxl[15:14]==0 || !pen15) ? pre_pxl[3:0] : 4'd0; // real color or 0 if shadow
assign shd     =  pre_pxl[15:14];
assign prio    =  pre_pxl[13:9];
assign pxl     =  gfx_en[3] ? {pre_pxl[8:4], pen_eff} : 9'd0;

// Simpsons, X-Men
jtframe_8x8x4_packed_msb u_packed(rom_data, sort_packed);

assign sorted = PACKED==1 ? sort_packed : rom_data;

k053246 #(
    .K55673          ( K55673           ),
    .K55673_DESC_SORT( K55673_DESC_SORT ),
    .EDGE_TRIGGER    ( EDGE_TRIGGER     ),
    .HOFFSET         ( HOFFSET          )
) u_scan (    // sprite logic
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),
    .pxl_cen    ( pxl_cen   ),
    .simson     ( simson    ),

    .ln_done    ( ln_done   ),
    .voffset    ( voffset   ),
    // CPU interface
    .cs         ( reg_cs    ),
    .cpu_we     ( mmr_we    ),
    .cpu_addr   ( mmr_addr  ),
    .cpu_dout   ( mmr_din   ),
    .cpu_dsn    ( mmr_dsn   ),
    .rmrd_addr  ( rmrd_addr ),

    // External RAM
    .dma_addr   ( dma_addr  ), // up to 16 kB
    .dma_data   ( dma_data  ),
    .dma_bsy    ( dma_bsy   ),

    // ROM addressing 22 bits in total
    .code       ( code      ),
    .attr       ( attr      ),     // OC pins
    .hflip      ( hflip     ),
    .vflip      ( vflip     ),
    .hpos       ( hpos      ),
    .ysub       ( ysub      ),
    .hzoom      ( hzoom     ),
    .hz_keep    ( hz_keep   ),

    // control
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),

    // shadow
    .pxl        ( pxl       ),
    .shd        ( pre_shd   ),

    // draw module / 053247
    .dr_start   ( dr_start  ),
    .dr_busy    ( dr_busy   ),

    // Debug
    .debug_bus  ( debug_bus ),
    .st_addr    ( ioctl_ram ? ioctl_addr[7:0] : debug_bus ),
    .st_dout    ( dump_reg  )
);


// ── DIBUJANTE: se usa el COMPARTIDO `jtframe_objdraw` ────────────────────────────────────────
// ⛔ ses.25: se forkeo a `k053246_objdraw` + `k053246_draw` (filtro de tiles invisibles) y se metio
// una cola `k053246_skid`. En SIM median muy bien (14198/CLKDIV=6: 7.57 % -> 3.60 %, y las 8 escenas
// de control en su valor exacto) pero EN PLACA EMPEORO: glitches del vagon mas visibles y SPRITES
// FANTASMA alrededor del personaje al moverse. REVERTIDO al compartido, que es lo que corre en la
// placa hoy. Los tres ficheros del fork siguen en el repo, DESCONECTADOS, con el analisis dentro.
// El gate de sim (escena ESTATICA, 1 frame) era incapaz de ver el fallo -> antes de re-cablear nada
// hay que montar el GATE DE MOVIMIENTO (dumps 4000-4015 ya volcados; ver HANDOFF sesion 26).
// ── ses.27: dibujante = FORK PROPIO `k053247` (rol del 053247 del silicio) ───────────────────
// PASO 1: k053247/_gate/_draw/_buffer son copia 1:1 renombrada de jtframe_objdraw/_gate/_draw/
// jtframe_obj_buffer (1 px/clk, comportamiento IDENTICO al compartido) => ambos gates deben quedar
// EXACTOS (movimiento 0.2604%, corte 14198@CLKDIV=6 7.5695%/128 lineas). Es el checkpoint verificable
// antes del PASO 2 (2 px/clk + line buffer doble banco + datapath 64-bit interno). jtframe NO se toca.
k053247 #(
    .SHADOW(SHADOW),.SHADOW_PEN(SHADOW_PEN),
    .AW(10),.CW(16),.PW(4+10+2),.LATCH(1),.SWAPH(1),
    .ZW(12),.ZI(6), .ZENLARGE(1),.SW(2),.FLIP_OFFSET(9'h12)
) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( {1'b0,hdump}  ),

    .draw       ( dr_start      ),
    .busy       ( dr_busy       ),
    .code       ( code          ),
    .xpos       ( hpos          ),
    .ysub       ( ysub          ),
    .hz_keep    ( hz_keep       ),
    .hzoom      ( hzoom         ),

    .hflip      ( ~hflip        ),
    .vflip      ( vflip         ),
    .pal        ({pre_shd, attr}),

    .rom_addr   ( pre_addr      ),
    .rom_cs     ( pre_cs        ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( sorted        ),

    .pxl        ( pre_pxl       )
);

jtframe_dual_nvram16 #(
    .AW     ( RAMW    ),
    .SIMFILE("obj.bin")
) u_ram( // 8 or 16kB? check PCB. Game seems to work on 8kB ok
    // Port 0 - CPU access
    .clk0   ( clk       ),
    .data0  ( ram_din   ),
    .addr0  ( ram_addr  ),
    .we0    ( ram_we & {2{ram_cs}} ),
    .q0     ( ram_data  ),
    // Port 1 - Video access
    .clk1   ( clk       ),
    .addr1a ( dma_addr[RAMW:1] ),
    .q1a    ( dma_data  ),
    // 8-bit IOCTL access
    .data1  ( 8'd0      ),
    .addr1b ( ioctl_addr[RAMW:0] ),
    .we1b   ( 1'd0      ),
    .q1b    ( dump_ram  ),
    .sel_b  ( ioctl_ram )
);

endmodule