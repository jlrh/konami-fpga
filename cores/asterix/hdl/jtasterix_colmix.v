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

    Author: Rafael Eduardo Paiva Feener. Copyright: Miki Saito
    Version: 1.0
    Date: 30-9-2024 */

// ============================================================================
// jtasterix_colmix — mezcla de prioridades K053251 + paleta xBGR_555 (ASTERIX).
//
// REESCRITO desde el clon de moomesa (B3 de research/FASE2-PLAN.md). Diferencias
// clave vs moomesa (fielmente a tools/asterix_golden_prio.py):
//   * Paleta **xBGR_555, 1 word/color, 1 banco** (moomesa era xRGB_888, 3 bancos,
//     2 words/color). Decode 5->8 por canal: (v<<3)|(v>>2). Fondo = pal[0].
//   * **SIN K054338**: no hay alpha, ni backdrop programable, ni 2ª instancia del
//     K053251, ni banco 'x' de paleta. asterix no lleva ese chip.
//   * **CI de asterix**: sprites = CI1; capas de tile en CI0/CI2/CI4; la capa FIX
//     (plano físico 2 = lyrb) se dibuja ENCIMA de todo (mux tras el K053251, como
//     el golden que la pinta al final). CI3 del chip queda transparente.
//   * Índice de color final = {COLHI(mmr9/10), ci} de 11 bits directo al índice de
//     paleta (color*16+pen); ver k051_palette_index() del golden.
//
// Mapa lyrX -> plano físico del K056832 (jtasterix_k056832: lb0..lb3 = capa 0..3):
//   lyrf = plano 0   -> CI0
//   lyra = plano 1   -> CI2
//   lyrb = plano 2   = FIX (encima de todo)   [colorbase CI3]
//   lyrc = plano 3   -> CI4
// (En moomesa lyrf era el FIX; en asterix el FIX es el plano 2 = lyrb.)
// ============================================================================
module jtasterix_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,

    // Base Video
    input             lhbl,
    input             lvbl,

    // CPU interface
    input             pcu_cs,       // regs K053251 (asterix 0x380500)
    input             alpha_cs,     // (asterix NO tiene K054338; queda sin uso)
    input             pal_cs,       // paleta xBGR_555 (asterix 0x280000)
    input             cpu_we,
    input      [15:0] cpu_dout,
    input      [ 7:0] cpu_d8,
    input      [ 1:0] cpu_dsn,
    input      [12:1] cpu_addr,
    output     [15:0] cpu_din,

    // Final pixels (K056832: 4 capas de tile 8b {colnib[7:4],pen[3:0]} + sprites)
    input      [ 7:0] lyrf_pxl,
    input      [ 7:0] lyra_pxl,
    input      [ 7:0] lyrb_pxl,
    input      [ 7:0] lyrc_pxl,
    input      [ 8:0] lyro_pxl,
    input      [ 4:0] lyro_pri,

    input      [ 1:0] shadow,
    input      [ 2:0] dim,          // (K054338: sin uso en asterix)
    input             dimmod,       // (K054338: sin uso en asterix)
    input             dimpol,       // (K054338: sin uso en asterix)

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    // Debug
    input      [11:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,
    output     [ 7:0] dump_mmr,

    input      [ 7:0] debug_bus
);

// K054338 sin uso en asterix: cortar las entradas para evitar warnings de señal muerta.
wire _unused = &{1'b0, alpha_cs, cpu_d8, dim, dimmod, dimpol, ioctl_addr[11:4], 1'b0};

wire [15:0] pal_q, pal_rd;      // pal_q = readback CPU; pal_rd = word xBGR_555 leído para vídeo
reg  [23:0] bgr;
reg  [ 7:0] r8, g8, b8;
wire [ 7:0] pr8, pg8, pb8;      // canales decodificados 5->8 del color leído
wire [10:0] pal_addr;           // índice de color ganador del K053251 (=color*16+pen)
wire        shad, pcu_we, k251_coln;
// 053251
wire [ 5:0] pri1s;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4;
wire [ 1:0] shd_out, shd_in;

// ---------------- decode xBGR_555 (1 word por color) ----------------
// pal[n] = xBBBBBGGGGGRRRRR. canal 5b -> 8b: (v<<3)|(v>>2). (=_pal5 del golden)
function [7:0] pal5(input [4:0] v); pal5 = {v,v[4:2]}; endfunction
assign pr8 = pal5( pal_rd[ 4: 0] );
assign pg8 = pal5( pal_rd[ 9: 5] );
assign pb8 = pal5( pal_rd[14:10] );

// ---------------- escritura / lectura CPU de la paleta ----------------
// bus: color n en el word-address n (1 word/color). cpu_addr[11:1] = índice 0..2047.
// dsn de 16b: escribe el word completo (el tb inyecta con dsn=0). Byte-enable respetado por si
// el juego real hace accesos de byte a la paleta.
wire [10:0] cpu_cidx = cpu_addr[11:1];
wire        we_pal   = pal_cs & cpu_we;
assign pcu_we    = pcu_cs & ~cpu_dsn[0] & cpu_we;
assign cpu_din   = pal_q;
assign ioctl_din = 8'd0;   // TODO(full-core): volcado de paleta para restore de escena

// Salida: dentro del área activa, FIX(opaco) > ganador K053251 > fondo pal[0].
assign {blue,green,red} = (lvbl & lhbl) ? bgr : 24'd0;

// ---------------- K053251 wiring (asterix) ----------------
//   CI0 = lyrf (plano 0), prioridad por registro (mmr[0], EXTEN[0]=1 lo fija el juego).
//   CI1 = SPRITES, prioridad DINÁMICA por sprite (pri1 externo; EXTEN[1]=0).
//   CI2 = lyra (plano 1), prioridad mmr[2].
//   CI3 = transparente (el FIX no entra por el chip, se superpone abajo).
//   CI4 = lyrc (plano 3), prioridad mmr[4].
// pri dinámica del sprite = (color&0x3e0)>>4 del golden = {lyro_pri,1'b0} (6b).
assign pri1s = {lyro_pri,1'b0};
assign ci0   = {1'b0, lyrf_pxl};   // plano 0 (CI0)
assign ci1   =  lyro_pxl;          // SPRITES (CI1)
assign ci2   = {1'b0, lyra_pxl};   // plano 1 (CI2)
assign ci3   =  8'd0;              // FIX fuera del chip -> CI3 transparente
assign ci4   =  lyrc_pxl;          // plano 3 (CI4)
// (shad se asigna abajo, junto al FIX: la sombra de sprite NO debe afectar al FIX)
assign shd_in= shadow;

jtcolmix_053251 u_k251(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    // CPU interface
    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),
    // explicit priorities
    .sel        ( 1'b0      ),
    .pri0       ( 6'h3f     ),   // CI0 usa mmr[0] (EXTEN) -> pri0 externo irrelevante
    .pri1       ( pri1s     ),   // SPRITES: prioridad dinámica por sprite
    .pri2       ( 6'h3f     ),   // CI2 usa mmr[2] (EXTEN)
    // color inputs
    .ci0        ( ci0       ),
    .ci1        ( ci1       ),
    .ci2        ( ci2       ),
    .ci3        ( ci3       ),
    .ci4        ( ci4       ),
    // shadow
    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out   ),
    // dump to SD card
    .ioctl_addr ( ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0] ),
    .ioctl_din  ( dump_mmr  ),

    .cout       ( pal_addr  ),
    .brit       (           ),
    .col_n      ( k251_coln )
);

// ---------------- FIX (plano 2 = lyrb) superpuesto encima del K053251 ----------------
// colorbase del FIX = idx[CI3] = 16*((k51[10])&7) del golden -> los 3 bits altos del índice.
// Se snoopean de la escritura al registro 10 (0xa) del K053251 (din = cpu_dout[5:0]).
reg  [ 2:0] fix_cbase;
always @(posedge clk, posedge rst) begin
    if(rst) fix_cbase <= 3'd0;
    else if(pcu_we && cpu_addr[4:1]==4'ha) fix_cbase <= cpu_dout[2:0];
end
// El FIX se retrasa L=2 para igualar la latencia del scroll a través del K053251 (misma constante
// validada en cowboys/moomesa: el K056832 y el K053251 no cambian). Así lyrb_d representa el MISMO
// pixel de pantalla que pal_addr/k251_coln (salidas registradas del chip).
wire [ 7:0] lyrb_d;
wire        fix_op = |lyrb_d[3:0];
// ⭐ La sombra de sprite NO afecta al FIX. En el golden el orden es: capas de prioridad -> sprites
// (que oscurecen lo que haya debajo) -> **capa FIX (plano 2) ENCIMA DE TODO**, con su color ÍNTEGRO.
// Aquí el FIX se superpone por `pal_amux`, pero `shad` se aplicaba al pixel FINAL, así que oscurecía
// también el FIX: la sombra de los caballos se "metía" en las alas del casco de Asterix (escena 1800:
// 38 px, golden 255,255,255 vs sim 153,153,153 = x0.6). `fix_op` está co-temporizado con `pal_addr`
// (ambos entran en `rd_idx` en el mismo stage), así que se gatea directo.
assign      shad   = |shd_out & ~fix_op;
wire [10:0] fix_idx  = {fix_cbase, lyrb_d};              // 3 + 8 = 11b (colorbase alto + {colnib,pen})
wire [10:0] pal_amux = fix_op ? fix_idx : pal_addr;
jtframe_sh #(.W(8),.L(2)) u_fixdly(.clk(clk),.clk_en(pxl_cen),.din(lyrb_pxl),.drop(lyrb_d));

// backdrop: si el ganador del K053251 es transparente Y el FIX es transparente -> pal[0] (bitmap.fill(0)).
// La selección se hace EN EL ÍNDICE DE LECTURA (mismo stage que pal_amux): k251_coln y fix_op ya están
// co-temporizados con pal_amux (el fix va L=2, alineado con las salidas registradas del K053251), así que
// NO hacen falta líneas de retardo — el índice y su propia lectura viajan juntos hacia bgr.
wire        use_bg  = k251_coln & ~fix_op;
wire [10:0] rd_idx  = use_bg ? 11'd0 : pal_amux;         // fondo = índice 0

// ---------------- paleta xBGR_555 (1 banco, 2048 colores, 1 word/color) ----------------
// Port0 = CPU rw (readback para el test de RAM del POST). Port1 = lectura de vídeo (índice ganador).
jtframe_dual_ram #(.DW(16),.AW(11),.SIMFILE("pal.bin")) u_pal(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_cidx ), .we0( we_pal ), .q0( pal_q  ),
    .clk1( clk ), .data1( 16'd0    ), .addr1( rd_idx   ), .we1( 1'b0   ), .q1( pal_rd )
);

// ---------------- salida RGB (con sombra de sprite) ----------------
// shadow: el pixel ganador (cuando el K053251 marca sombra) se atenúa. El golden hace (c*3)//5 EXACTO
// (SHADOW_NUM/DEN = 3/5, division entera). El ×154/256 anterior NO era equivalente: difiere en 1 para
// varios valores (c=123 -> 73 golden vs 74), y eso salia como residuo en la MEZCLA (tiles y sprites por
// separado daban 0% pero el full no). 3/5 = 0.6 ; 0.6*65536 = 39321.6 -> se usa 39322 (redondeo ARRIBA,
// para que los multiplos exactos de 5 lleguen al entero). Es exacto para c en 0..255: la parte
// fraccionaria de c*3/5 solo vale {0,.2,.4,.6,.8} y el error del multiplicador es <0.008.
// ⚠ El intermedio DEBE ser ancho: en Verilog el producto se evalua con el ancho auto-determinado de
// los operandos, asi que `(c*17'd39322)>>16` se truncaba a 17 bits y devolvia ~0 (la sombra salia NEGRA,
// no atenuada). Igual de roto estaba el `(c*8'd154)>>8` original (ancho 8 -> siempre 0): la sombra
// NUNCA funciono. Con {16'd0,c}*24'd39322 el producto cabe (255*39322 = 10.027.110 < 2^24).
function [7:0] shd06(input [7:0] c);
    reg [23:0] m;
    begin
        m      = {16'd0, c} * 24'd39322;
        shd06  = m[23:16];
    end
endfunction
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        { r8, g8, b8 } <= 0;
        bgr <= 0;
    end else begin
        { r8, g8, b8 } <= { pr8, pg8, pb8 };             // xBGR_555 decodificado 5->8
        if( pxl_cen )
            bgr <= ~shad ? { b8, g8, r8 }
                         : { shd06(b8), shd06(g8), shd06(r8) };
    end
end

`ifdef SIMULATION
// SONDA SESION 29 — bug de color de sprites ("le falta algun bit al color, el logo deberia ser un
// degradado y sale con 4 colores"). El golden (vfull, 0.0000%) ya prueba que el decode pixel/color es
// exacto CUANDO se le da el registro/paleta correctos; lo que falta medir es si esos datos llegan bien
// en el full-core REAL. mame_prottap.lua mide (ses.27/28) que el blitter copia 32 words a 280800 y
// 32 a 280900 en la escena del titulo (equivalente a MAME f1102) — el banco de color de los sprites
// (colores 1024-1183) que fija COLHI0=r09=0x18 (fijo desde MAME f14, no cambia mas). PAL-SPR imprime
// CADA escritura a esa ventana (CPU o blitter, cpu_dout ya es el bus EFECTIVO post-mux) para ver: (a) en
// que frame local llegan esas 2 copias (compararlo contra el frame en que se capturo el snapshot que
// disparo la sospecha), y (b) el VALOR escrito, para diff directo contra ROM (origen del blitter).
// gfx_en[3] no se toca: sonda de solo lectura, no cambia comportamiento.
integer ps_frame = 0;
reg     ps_lvbl_l = 0;
always @(posedge clk) begin
    ps_lvbl_l <= lvbl;
    if( lvbl && !ps_lvbl_l ) ps_frame <= ps_frame + 1;   // flanco de subida = inicio de frame
end
// Rango AMPLIADO tras ver frame_01173.png: el logo ya sale bien (fix confirmado, ver arriba), pero los
// PERSONAJES salen con formas correctas y colores MUY apagados (blanco/celeste palido) en vez de vivos.
// Hipotesis: usan bancos de color en el HUECO 1056-1151 (66-71) que NINGUNA copia del blitter observada
// hasta ahora (ni aqui ni en el trace de MAME ses.27, dst=280800/280900) toca — se amplia la ventana
// vigilada a todo CI1 (1024-1535, los 32 bancos que el sprite puede direccionar con attr[4:0]) para
// verlo con la MISMA tecnica (traza de escritura), ya que el volcado directo de u_pal.mem por jerarquia
// NO compila en Verilator aqui ("Can't find definition of 'mem' in dotted variable") — descartado.
always @(posedge clk) if( we_pal && cpu_cidx>=11'd1024 && cpu_cidx<11'd1536 )
    $display("PAL-SPR: frame=%0d idx=%0d(0x%03x) data=%04x", ps_frame, cpu_cidx, cpu_cidx, cpu_dout);
`endif

endmodule
