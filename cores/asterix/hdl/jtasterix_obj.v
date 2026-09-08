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
    Adapted for ASTERIX (GX068) — B2 de research/FASE2-PLAN.md.
*/

// ============================================================================
// jtasterix_obj — sprites K053244/K053245 de ASTERIX.
//
// DERIVADO de jtriders_obj (Konami K053244/5, chip EXACTO de asterix — validado
// en riders: ssriders/tmnt2/lgtnfght). Reusa jt053244/jt053244_scan (scan+DMA
// ordenado por pri_code) + jtframe_objdraw. DELTA de asterix vs riders:
//   * spritebank (0x380400 -> reset_spritebank): el sprite_callback de asterix.cpp
//     hace code = (code & 0xfff) | m_spritebanks[(code>>12)&3], con
//     m_spritebanks[i] = (spritebank<<{12,9,6,3})&0x7000. Aquí se aplica al code
//     que sale del scan ANTES del objdraw (el scan sólo toca code[5:0], así que
//     code[13:12] = word1[13:12] = selector de banco intacto). = golden draw_sprites.
//   * sin lgtnfght (dma_addr = scan_addr directo).
//   * rom_addr [21:2] = región obj de 4MB (068a08/a07, ROM_LOAD32_WORD). El remap
//     de bits del K053245 (paroda_conv) es idéntico al del golden (bits 1..4).
//   * shd de 1 bit (K053245) — el colmix lo mete en shd_in[0].
// ============================================================================
module jtasterix_obj #(parameter
    RAMW   = 13,
    HFLIP_OFFSET = 0,
    SHADOW = 1
)(
    input             rst,
    input             clk,

    input             pxl_cen,
    input             pxl2_cen,
    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input             hs,
    input             lvbl,

    // spritebank (0x380400) — reset_spritebank de asterix.cpp
    input      [15:0] spritebank,

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

    // ROM addressing (4MB obj)
    output     [21:2] rom_addr,
    input      [31:0] rom_data,
    output            rom_cs,
    input             rom_ok,
    input             objcha_n,

    // pixel output
    output            shd,      // shadow (1 bit)
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

wire        pre_shd;
wire [ 3:0] pen_eff;
wire [15:0] ram_data, dma_data;
wire [22:2] pre_addr;
wire [21:1] rmrd_addr;
wire [13:1] dma_addr;
wire [15:0] pre_pxl;

// Draw module
wire        dr_start, dr_busy;
wire [15:0] code, code_bank;
wire [ 6:0] attr;     // OC pins
wire        hflip, vflip, hz_keep, pre_cs;
wire [ 9:0] hpos;
wire [ 3:0] ysub;
wire [11:0] hzoom;
wire        pen15;

function [5:0] paroda_conv(input [5:0]x);
    paroda_conv = { x[5], x[3], x[1], x[4], x[2], x[0] };
endfunction

// spritebank de asterix.cpp: code = (code & 0xfff) | m_spritebanks[(code>>12)&3]
// m_spritebanks[i]>>12 = spritebank[{2:0,5:3,8:6,11:9}] según i=(code>>12)&3.
function [2:0] sprbank(input [1:0] sel, input [15:0] sb);
    case( sel )
        2'd0: sprbank = sb[ 2:0];
        2'd1: sprbank = sb[ 5:3];
        2'd2: sprbank = sb[ 8:6];
        2'd3: sprbank = sb[11:9];
    endcase
endfunction
assign code_bank = { 1'b0, sprbank(code[13:12], spritebank), code[11:0] };

assign rom_cs    = ~objcha_n | pre_cs;
assign rom_addr  = !objcha_n ? rmrd_addr[21:2] :
    { pre_addr[21], pre_addr[20:13], paroda_conv(pre_addr[12:7]), pre_addr[5], pre_addr[6], pre_addr[4:2] };

assign cpu_din   = !objcha_n ? rmrd_addr[1] ? rom_data[31:16] : rom_data[15:0] :
                    ram_data;

// Shadow: si shadow activo y pen=15, salida transparente (pen 0) + bit de sombra.
assign pen15   = &pre_pxl[3:0];
assign pen_eff = (pre_pxl[15:14]==0 || !pen15) ? pre_pxl[3:0] : 4'd0;
// NOTA (residuo 1800/personajes pastel ses.29) — RESUELTO ses.30 con `SHADOW_GATE(1)` abajo.
// `jtframe_obj_buffer` ponia el bit de sombra con `add_shade = shade & we && is_just_a_shadow`
// SIN comprobar si en esa posicion YA habia un pixel SOLIDO de OTRO sprite dibujado antes. El
// golden hace `if shadow and pen==0x0f: if solidmask[o] or shadowmask[o]: continue` (el solido
// gana). Confirmado por MEDIDA (sonda `SHD-SOLID`, full-core sim frames 750-1250, ses.30):
// 92.493 pixeles con `shd=1` y un pen SOLIDO real (ni 0 ni 15) — exactamente la firma del bug,
// empezando en la escena de personajes corriendo (~f759) y presente hasta el logo del titulo.
// PROBADO y DESCARTADO (ses.29): gatear aqui con `& ~|pre_pxl[3:0]` (sombra solo si el plano de
// sprites es transparente EN EL MOMENTO DE LA MEZCLA) es DEMASIADO BURDO -> 1800 38->388 px y
// 2400 65->410: ataca el lado de LECTURA (el pixel final), no el de ESCRITURA del buffer (el
// momento en que la sombra pisa al solido), asi que tambien mata sombras legitimas sobre tiles.
// FIX real (ses.30): parametro `SHADOW_GATE` nuevo en `jtframe_obj_buffer`/`jtframe_objdraw[_gate]`
// (opt-in, default 0 = comportamiento TMNT-style de fabrica, no toca otros cores), DOS cambios:
// 1) `&& was_blank` en `add_shade` — la sombra solo se aplica si el buffer estaba blank (pen==0),
//    replicando el `solidmask` del golden.
// 2) `erase_shade = new_we` (en vez de `!shade & new_we`) — el primer intento (solo 1) NO bastaba:
//    un sprite QUE SI proyecta sombra (`shade=1` en TODOS sus pixeles) puede tener pixeles de color
//    SOLIDO propios (is_just_a_shadow==0, p.ej. el cuerpo de un caballo) que escriben con new_we=1
//    pero NUNCA limpiaban el bit de sombra residual de esa posicion porque `erase_shade` exigia
//    `!shade`, que es falso para ESE sprite. MEDIDO: con solo el cambio 1, `SHD-SOLID` seguia dando
//    exactamente los MISMOS 92.493 hits (0% de cambio) — la causa real de los hits medidos era esta
//    segunda ruta, no la primera. Con las DOS, cualquier escritura solida limpia la sombra, igual
//    que el `solidmask` del golden (que no distingue de que sprite viene el pixel solido).
// Activado para asterix como `.SHADOW_GATE(1)` en `u_draw` mas abajo. Pendiente de re-validar el
// conteo de `SHD-SOLID` a 0 tras el fix (bloqueado por tiradas largas del full-core sim, ver HANDOFF).
assign shd     =  pre_pxl[14];
assign prio    =  {1'd1,pre_pxl[10:9],2'd0} ;
assign pxl     = gfx_en[3] ? {pre_pxl[8:4], pen_eff} : 9'd0;

`ifdef SIMULATION
// SONDA sesion 30 — confirmar por medida la hipotesis de la NOTA de arriba (residuo 1800/logo
// pastel de la ses.29). Leido `jtframe_obj_buffer.v`: `add_shade = shade & we && is_just_a_shadow`
// NO comprueba `was_blank` (si YA habia un pixel solido en el buffer de OTRO sprite dibujado
// antes). El propio comentario de cabecera de `jtframe_objdraw_gate.v` dice que es INTENCIONADO
// ("shadow bit is always written, even if the pixel is blank" — estilo TMNT), asi que el golden de
// asterix (que SI mira `solidmask`/`shadowmask`, `tools/asterix_golden_prio.py:387-394`) exige un
// comportamiento DISTINTO al de fabrica del modulo compartido. Firma esperada si la hipotesis es
// cierta: un pixel SOLIDO (pen!=0 Y pen!=15, no es un sprite de "solo sombra") que ADEMAS lleva el
// bit `shd` puesto -> se oscurecera x0.6 en jtasterix_colmix aunque MAME lo pinte integro.
// (ses.30: sospecha inicial de que ESTA sonda colgaba `capture 1250 s30` -> DESCARTADA por un
// control run identico sin la sonda que tardo ~2h30 reales en completar 750 frames sin problema.
// Repetidos "killed" DESPUES tambien en tiradas SIN relacion con ScheduleWakeup y con el propio
// target de 750 -> el patron encaja con la inestabilidad de ESTA maquina ya documentada en sesiones
// previas (hibernacion/competicion por CPU alarga o corta las tiradas largas de forma impredecible),
// no con el codigo. Ventana bajada de 1150-1250 a 600-800 para que una tirada MAS CORTA (que ya
// demostro llegar, al menos una vez, hasta 750-751) tenga alguna oportunidad de ejercitar la sonda:
// cubre la escena de la aldea/personajes corriendo (`00690.png`/`00780.png` de la ses.27), donde el
// mismo bug de sombra sprite-sobre-sprite es tan plausible como en el logo del titulo.
reg [15:0] s30_frame=0;
reg        s30_lvbl_l;
always @(posedge clk) begin
    s30_lvbl_l <= lvbl;
    if(!lvbl && s30_lvbl_l) s30_frame <= s30_frame + 1'b1;   // flanco de bajada de lvbl ~ 1/frame
end
always @(posedge clk) if(pxl_cen && lvbl && pre_pxl[14] && pre_pxl[3:0]!=4'h0 && pre_pxl[3:0]!=4'hf
                          && s30_frame>=16'd600 && s30_frame<=16'd1250)
    $display("SHD-SOLID frame=%0d hdump=%0d vdump=%0d pen=%0d pre_pxl=%04x",
              s30_frame, hdump, vdump, pre_pxl[3:0], pre_pxl);
`endif

// jtasterix_053244 = fork de jt053244 (riders) con el flicker de DEBUG del scan DESACTIVADO:
// `scan_obj[6:0]==debug_bus[6:0] && flicker` descartaba en lineas alternas el sprite cuyo indice
// coincide con debug_bus; con debug_bus=0 eso PERDIA el sprite de pri_code 0 (el jefe en la escena
// 900). En simson/jt053246_scan esa misma clausula ya esta comentada. MEDIDO: 900 3.15%->1.14%,
// 3000 0.61%->0.0000%.
jtasterix_053244 #(.HFLIP_OFFSET(HFLIP_OFFSET)
    )u_scan(    // sprite logic
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl2_cen   ( pxl2_cen  ),
    .pxl_cen    ( pxl_cen   ),

    // CPU interface
    .cs         ( reg_cs    ),
    .cpu_we     ( mmr_we    ),
    .cpu_addr   ( mmr_addr  ),
    .cpu_dout   ( mmr_din   ),
    .cpu_dsn    ( mmr_dsn   ),
    .rmrd_addr  ( rmrd_addr ),

    // External RAM
    .dma_addr   ( dma_addr  ),
    .dma_data   ( dma_data  ),
    .dma_bsy    ( dma_bsy   ),

    // ROM addressing
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

// ⭐ SESION 23 — `HFIX(0)`. Por defecto jtframe_objdraw_gate lleva HFIX=1: la direccion de lectura
// del line buffer NO es `hdump`, es un contador `hdfix` que solo se re-sincroniza con `hdump` cuando
// `hdump > hdfix` o cuando **HS esta alto**; si `hdump` DECRECE sin que llegue HS, `hdfix` sigue
// subiendo y se va +512 por encima (el buffer es AW=10, asi que 512 direcciones mas arriba = zona
// vacia) => los sprites DESAPARECEN ENTEROS.
// Aqui `hdump` del obj es `hdump_vtimer + objdx` (offset de calibracion, 124) en 9 bits, o sea que
// DECRECE dos veces por linea: al pasar de 511 a 0 y en el wrap de H. Con el vtimer viejo funcionaba
// **por casualidad**: HS caia justo entre ese decremento y la ventana activa. Al mover HS (obligado,
// porque con HTOTAL=384 el 403 ya no existe) se rompia: MEDIDO `dr_start=9536 hpos[143..375]` (el
// scan y el dibujo PERFECTOS) con `rd_nz=0` (el buffer no devolvia un solo pixel).
// Con HFIX=0, `hdfix = hdump` siempre: la lectura ya no depende de donde este HS. En la ventana
// activa es IDENTICO a lo que hacia antes (alli hdfix ya valia hdump), asi que no mueve un pixel.
jtframe_objdraw #(
    .SHADOW(SHADOW),.SHADOW_GATE(1),.SHADOW_PEN(SHADOW_PEN),.SW(2),.HFIX(0),
    .AW(10),.CW(16),.PW(4+10+2),.LATCH(1),.SWAPH(1),
    .ZW(12),.ZI(6),.ZENLARGE(1),
    .FLIP_OFFSET(9'h12),.KEEP_OLD(0)
) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),

    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( {1'b0,hdump}  ),

    .draw       ( dr_start      ),
    .busy       ( dr_busy       ),
    .code       ( code_bank     ),   // <-- code con spritebank aplicado (delta asterix)
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

jtframe_dual_nvram16 #(
    .AW     ( RAMW    ),
    .SIMFILE("obj.bin")
) u_ram(
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

`ifdef OBJDIAG
// SONDA del camino de sprites (la activa `run_vfull.sh` con +define+OBJDIAG). Mide las DOS mitades
// por separado, que es lo que desatasco la sesion 23: cuantas ordenes de dibujo emite el scan y en
// que rango escribe (`dr_start`/`hpos`) FRENTE A cuantos pixeles devuelve el line buffer y en que
// hdump (`rd_nz`). Ver los dos a la vez distingue "el scan no encuentra sprites" de "los dibuja
// bien pero se leen en otra direccion" — que era el caso, y a ojo son el mismo sintoma.
integer n_drstart=0, n_rdnz=0;
reg [9:0] hpmin=10'h3ff, hpmax=0;
reg [8:0] rdmin=9'h1ff, rdmax=0, hsmin=9'h1ff, hsmax=0;
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
