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

module jtcowboys_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,

    // Base Video
    input             lhbl,
    input             lvbl,

    // CPU interface
    input             pcu_cs,
    input             alpha_cs,   // K054338 regs 0x0ca000 (alpha + backdrop fill)
    input             pal_cs,
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
    input      [ 2:0] dim,
    input             dimmod,
    input             dimpol,

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

wire [ 7:0] pal_r, pal_g, pal_b;   // lectura vídeo: canales xRGB_888 (moomesa)
wire [ 7:0] cr, cg, cb, cx;        // readback CPU (cx = byte 'x' de xRGB_888, ver u_pal_x)
reg  [23:0] bgr;
reg  [ 7:0] r8, b8, g8;
wire [10:0] pal_addr;
wire        shad, pcu_we, nc, k251_coln;
// 053251 inputs
wire [ 5:0] pri1;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4;
wire [ 1:0] shd_out, shd_in;
// K054338 alpha: 2ª instancia del K053251 ("back") + 2º puerto de paleta
wire [10:0] cout_b;                 // color ganador SIN la capa frontal de scroll (=fondo del blend)
wire        coln_b;                 // back transparente -> usar backdrop
wire [ 7:0] pal_r2, pal_g2, pal_b2; // lectura de paleta del color "back"
wire        front_a, front_b, front_c;   // one-hot: qué capa de scroll es la frontal (layer[2])
reg  [ 5:0] pri_a, pri_b, pri_c;    // prioridades snoopeadas de CI2/CI3/CI4 (mmr 2/3/4)
wire        do_blend;
wire [23:0] blended_bgr;

// Paleta xRGB_888 (moomesa: PALETTE set_format xRGB_888,2048 -> 2 words/color @0x1c0000).
// word par (cpu_addr[1]=0) low byte = R; word impar (cpu_addr[1]=1): high byte = G, low byte = B.
// Idéntico a build_palette del golden (r=hi&0xff, g=lo>>8, b=lo&0xff) y al backdrop K054338 de abajo.
wire [10:0] cpu_cidx = cpu_addr[12:2];   // índice de color (0..2047)
wire        we_r = pal_cs & cpu_we & ~cpu_addr[1] & ~cpu_dsn[0];
wire        we_g = pal_cs & cpu_we &  cpu_addr[1] & ~cpu_dsn[1];
wire        we_b = pal_cs & cpu_we &  cpu_addr[1] & ~cpu_dsn[0];
// ⚠ El byte 'x' de xRGB_888 (byte ALTO del word PAR) NO lo usa el vídeo... pero en la PLACA 0x1c0000 es
// **RAM NORMAL de 16 bits**: lo que escribes, lo relees. Sin este banco se PERDIA (no habia `we` para el)
// y `cpu_din` devolvia {8'h00, cr} -> una relectura de un word par NO casaba con lo escrito.
// Consecuencia REAL (no teorica): el POST hace un test de RAM (escribe 5555/aaaa y relee) sobre la paleta
// -> leia 0055/00aa -> **"RAM ... BAD"** en la pantalla de check. Ver HANDOFF sesion 7 §D (ya estaba
// anotado como "diferencia real contra MAME -> vigilar") y sesion 10.
// No afecta al video: `cx` solo sale por `cpu_din`, nunca por el camino RGB.
wire        we_x = pal_cs & cpu_we & ~cpu_addr[1] & ~cpu_dsn[1];
assign pcu_we    = pcu_cs & ~cpu_dsn[0] & cpu_we;
assign cpu_din   = cpu_addr[1] ? {cg, cb} : {cx, cr};
assign ioctl_din = 8'd0;   // TODO(full-core): volcado de paleta para restore de escena
// Orden de precedencia en el pixel final: FIX (opaco) > blend alpha K054338 > backdrop > tile ganador.
// do_blend degenera correctamente a "mostrar el fondo" cuando alpha_lv=0 (escena 1200 suprime la capa
// frontal). Cuando alpha_en=0 -> do_blend=0 -> salida IDÉNTICA a la ruta validada (notspr 180/300/900).
assign {blue,green,red} = (lvbl & lhbl ) ? (do_blend ? blended_bgr : (use_bg ? bg_bgr : bgr)) : 24'd0;

// 053251 wiring — mapeo REAL de moomesa (moo.cpp screen_update + k051_palette_index del golden):
//   SPRITES = CI0 (colorbase get_palette_index(CI0)=idx0; prioridad DINAMICA por sprite via pri0,
//     porque EXTEN[0]=0 -> el K053251 usa el input pri0). Antes estaban en CI1, donde EXTEN[1]=1 fuerza
//     pri1=mmr[1]=0x3f (mas baja) -> el sprite SIEMPRE perdia y no componia. Cazado con run_vfull.
//   CI1 = referencia de fondo (transparente aqui; su prioridad mmr[1] la fija el juego).
//   capa a=CI2, capa b=CI3, capa c=CI4 (colorbase idx2/3/4, prioridad mmr[2/3/4]).
// El FIX (colorbase fija 0x70) NO entra por el K053251 -> se SUPERPONE encima (mux pal_amux).
// Nota: mover sprites CI1->CI0 NO afecta a notspr (sprites transparentes en ambos casos; tiles intactos).
wire [ 5:0] pri0s = {lyro_pri,1'b0};    // prioridad dinamica del sprite (=(w6&0x3e0)>>4 del golden)
assign pri1      = 6'h3f;               // ci1 sin usar (EXTEN[1]=1 -> el K053251 toma mmr[1] igualmente)
assign ci0       =  lyro_pxl;           // SPRITES (CI0)
assign ci1       =  9'd0;               // CI1 = fondo/referencia (transparente)
assign ci2       = {1'b0, lyra_pxl};    // capa a (CI2)
assign ci3       =  lyrb_pxl;           // capa b (CI3)
assign ci4       =  lyrc_pxl;           // capa c (CI4)
assign shad      = |shd_out;
assign shd_in    =  shadow;

// FIX superpuesto encima del K053251 (colorbase 0x70): pal = fix_opaco ? {3'b111,fix} : cout_k251.
// lyrf_d = fix retrasado para alinear con la latencia del K053251 (~1 pxl_cen) — VALIDAR en full-core sim.
// fix retrasado L=2 para IGUALAR la latencia del scroll a través del K053251 (validado sesión 3:
// fix-only alineaba a +2 y scroll a +3 -> 1px de desfase relativo fix/scroll; con L=2 ambos a +3).
wire [ 7:0] lyrf_d;
wire        fix_op = |lyrf_d[3:0];
wire [10:0] pal_amux = fix_op ? {3'b111, lyrf_d} : pal_addr;
jtframe_sh #(.W(8),.L(2)) u_fixdly(.clk(clk),.clk_en(pxl_cen),.din(lyrf_pxl),.drop(lyrf_d));

// ---------------- K054338: registros (0x0ca000) + backdrop fill (+ alpha, parcial) ----------------
reg  [15:0] k38[0:15];
// contador de bucle LOCAL en named block (`integer ai` dentro de `begin:k38_rst`): Verilog-2001 legal
// (Quartus rechaza `for(int ai...)` en un .v -> error 10170; ver k056832, sesion 18). Sigue LOCAL ->
// evita el latch del `integer` de modulo en el reset (sesion 16).
always @(posedge clk, posedge rst) begin : k38_rst
    integer ai;
    if(rst) for(ai=0;ai<16;ai=ai+1) k38[ai]<=16'd0;
    else if(alpha_cs & cpu_we) k38[cpu_addr[4:1]] <= cpu_dout;
end
// backdrop fill: bytes CRUDOS (sin paleta) R=k38[0][7:0], G=k38[1][15:8], B=k38[1][7:0].
// la salida es {blue,green,red} -> ordenar {B,G,R}. Validado contra el golden (bgrgb).
wire [23:0] bg_bgr   = { k38[1][7:0], k38[1][15:8], k38[0][7:0] };
// alpha (K338): MIXPRI=k38[15][1] (enable), mixlv=k38[13][4:0], alpha_lv={mixlv,mixlv[4:2]}.
// TODO(no validado; ninguna escena tiene blending 0<lv<255): con alpha_lv==0 la capa alpha
// (=top scroll, layer[2] ordenada) NO se dibuja; con 0<lv<255 se mezcla con la de detras (K054338).
// Requiere identificar la capa alpha en el K053251 y, para blending, el 2o color -> diseño pendiente.
wire        alpha_en = k38[15][1];
wire [ 4:0] mixlv    = k38[13][4:0];
wire [ 7:0] alpha_lv = {mixlv, mixlv[4:2]};   // 5b->8b (=set_alpha_level de MAME)

// --- capa frontal (layer[2]) = la de scroll con MENOR prioridad (=frontmost en Konami) ---
// Snoop de las prioridades CI2/CI3/CI4 escritas al K053251 (addr 2/3/4, din=cpu_dout[5:0]).
always @(posedge clk, posedge rst) begin
    if(rst) begin pri_a<=0; pri_b<=0; pri_c<=0; end
    else if(pcu_we) case(cpu_addr[4:1])
        4'd2: pri_a <= cpu_dout[5:0];
        4'd3: pri_b <= cpu_dout[5:0];
        4'd4: pri_c <= cpu_dout[5:0];
        default:;
    endcase
end
// Réplica EXACTA de konami_sortlayers3(layer=[a,b,c], pri): el índice 2 final = min prioridad.
// (0=a/CI2, 1=b/CI3, 2=c/CI4). Sólo swap en '<' estricto, igual que el golden -> mismos empates.
reg [1:0] sl0, sl1, sl2; reg [5:0] sp0, sp1, sp2;
always @* begin
    sl0=2'd0; sl1=2'd1; sl2=2'd2; sp0=pri_a; sp1=pri_b; sp2=pri_c;
    if(sp0<sp1) begin {sp0,sp1}={sp1,sp0}; {sl0,sl1}={sl1,sl0}; end
    if(sp0<sp2) begin {sp0,sp2}={sp2,sp0}; {sl0,sl2}={sl2,sl0}; end
    if(sp1<sp2) begin {sp1,sp2}={sp2,sp1}; {sl1,sl2}={sl2,sl1}; end
end
assign front_a = sl2==2'd0;
assign front_b = sl2==2'd1;
assign front_c = sl2==2'd2;

// blend exacto (src*a + dst*(255-a))/255, con floor división por 255 vía mult-shift (0x8081>>23).
function [7:0] blend8( input [7:0] fr, input [7:0] bk, input [7:0] a );
    reg [16:0] num; reg [31:0] mul;
    begin
        num = fr*a + bk*(8'd255 - a);
        mul = num * 32'd32897;      // 0x8081
        blend8 = mul[30:23];
    end
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bgr   <= 0;
    end else begin
        { b8, g8, r8 } <= { pal_b, pal_g, pal_r };   // xRGB_888 directo (sin conv58 5->8)
        if( pxl_cen ) bgr <= ~shad ? { b8, g8, r8 } : { b8>>1, g8>>1, r8>>1 };
    end
end

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
    .pri0       ( pri0s     ),   // sprites: prioridad dinamica por sprite
    .pri1       ( pri1      ),
    .pri2       ( 6'h3f     ),
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

// backdrop: si el ganador del K053251 es transparente Y el fix es transparente -> color de fondo.
// Alineación con la latencia hacia bgr (VALIDADA en sim RGB, sesión 3): bgr(W)=palette[fix(W-2)] y
// fix_op ya lleva +1 de lyrf_d -> fixop_a necesita L=1 (no L=2, que erosionaba 1px el borde inicial
// de cada glifo del fix). El col_n del K053251 sí necesita L=2 (cout->paleta->bgr). Delays SEPARADOS.
wire coln_a, fixop_a;
jtframe_sh #(.W(1),.L(2)) u_colndly(.clk(clk),.clk_en(pxl_cen),.din(k251_coln),.drop(coln_a ));
jtframe_sh #(.W(1),.L(1)) u_fopdly (.clk(clk),.clk_en(pxl_cen),.din(fix_op),   .drop(fixop_a));
wire use_bg = coln_a & ~fixop_a;

// Paleta moomesa = xRGB_888, 2048 colores, 2 words por color (@0x1c0000). Se guarda en 3 bancos
// de 2048x8 (R,G,B) direccionados por índice de color: lectura por pal_amux (11b), escritura por
// cpu_cidx=cpu_addr[12:2] con we por byte (we_r/we_g/we_b). Port1 = lectura vídeo; Port0 = CPU rw.
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_r.bin")) u_pal_r(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_r ), .q0( cr    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1( pal_r )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_g.bin")) u_pal_g(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_g ), .q0( cg    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1( pal_g )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_b.bin")) u_pal_b(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_b ), .q0( cb    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1( pal_b )
);
// 4º banco: el byte 'x' de xRGB_888. El VIDEO NO LO USA (no hay puerto 1) — existe solo para que una
// relectura del word PAR devuelva lo que se escribio, como en la placa (RAM de 16 bits). Sin el, el test
// de RAM del POST sobre la paleta da "BAD". No hay SIMFILE: los dumps del golden no llevan este byte.
jtframe_dual_ram #(.DW(8),.AW(11)) u_pal_x(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_x ), .q0( cx    ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( pal_amux ), .we1( 1'b0 ), .q1(       )
);

// ================= K054338 alpha blending =================
// 2ª instancia del K053251 con la capa FRONTAL de scroll puesta a 0 (sprites CI0 intactos):
//   cout_b = color que quedaría si la capa frontal (=alpha) no se dibujara = "fondo" del blend.
// Si el ganador de la instancia A es un sprite o una capa trasera, quitar la frontal no cambia el
// ganador -> cout_b==pal_addr -> NO se hace blend (sprites nunca se alpha-mezclan). Si el ganador es
// la capa frontal, cout_b da lo de detrás y se mezcla. Con alpha_lv=0 el blend = "fondo" (suprime la
// capa frontal, escena 1200). Réplica del compositing painter's de moo.cpp screen_update.
wire [8:0] ci2b = front_a ? 9'd0 : ci2;
wire [7:0] ci3b = front_b ? 8'd0 : ci3;
wire [7:0] ci4b = front_c ? 8'd0 : ci4;
wire [1:0] shd_out_b;

jtcolmix_053251 u_k251_back(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),
    .sel        ( 1'b0      ),
    .pri0       ( pri0s     ),
    .pri1       ( pri1      ),
    .pri2       ( 6'h3f     ),
    .ci0        ( ci0       ),   // sprites INTACTOS en la instancia back
    .ci1        ( ci1       ),
    .ci2        ( ci2b      ),   // capa frontal a 0 si es a/b/c
    .ci3        ( ci3b      ),
    .ci4        ( ci4b      ),
    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out_b ),
    .ioctl_addr ( 4'd0      ),
    .ioctl_din  (           ),
    .cout       ( cout_b    ),
    .brit       (           ),
    .col_n      ( coln_b    )
);

// 2º puerto de paleta: lee el color "back" en paralelo (mismos writes que el banco principal).
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_r.bin")) u_pal_r2(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_r ), .q0(         ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( cout_b   ), .we1( 1'b0 ), .q1( pal_r2 )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_g.bin")) u_pal_g2(
    .clk0( clk ), .data0( cpu_dout[15:8] ), .addr0( cpu_cidx ), .we0( we_g ), .q0(         ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( cout_b   ), .we1( 1'b0 ), .q1( pal_g2 )
);
jtframe_dual_ram #(.DW(8),.AW(11),.SIMFILE("pal_b.bin")) u_pal_b2(
    .clk0( clk ), .data0( cpu_dout[7:0]  ), .addr0( cpu_cidx ), .we0( we_b ), .q0(         ),
    .clk1( clk ), .data1( 8'd0           ), .addr1( cout_b   ), .we1( 1'b0 ), .q1( pal_b2 )
);

// Cadena de latch del color back, IDÉNTICA en profundidad a la de bgr (pal->r8->bgr) para alinear.
reg  [ 7:0] br8, bg8, bb8;
reg  [23:0] back_bgr;
always @(posedge clk, posedge rst) begin
    if( rst ) begin { br8,bg8,bb8 } <= 0; back_bgr <= 0; end
    else begin
        { bb8, bg8, br8 } <= { pal_b2, pal_g2, pal_r2 };
        if( pxl_cen ) back_bgr <= { bb8, bg8, br8 };   // sin shadow (back = capas traseras opacas)
    end
end

// blend_en: alpha activo, ganador A opaco, y el ganador cambia al quitar la capa frontal
// (=> el ganador ES la capa frontal alpha). do_blend además exige que el FIX no sea opaco (el fix
// va siempre encima). Delay L=1: bgr/back_bgr van 1 periodo de pxl_cen por detrás de cout/pal_addr
// (cadena pal->r8->bgr), así que la decisión (calculada en el stage de cout) se alinea con +1.
// Validado en 1200: L=1 -> 0.0000% (L=2 dejaba residuo de 1px en el borde diagonal de la capa a).
wire       blend_en_now = alpha_en & ~k251_coln & (pal_addr != cout_b);
wire       blend_en_a, colnb_a;
jtframe_sh #(.W(1),.L(1)) u_blenddly(.clk(clk),.clk_en(pxl_cen),.din(blend_en_now),.drop(blend_en_a));
jtframe_sh #(.W(1),.L(1)) u_colnbdly(.clk(clk),.clk_en(pxl_cen),.din(coln_b     ),.drop(colnb_a  ));
assign do_blend = blend_en_a & ~fixop_a;

// back = paleta[cout_b] o backdrop si el back es transparente. blended = front(bgr) sobre back.
wire [23:0] back_sel   = colnb_a ? bg_bgr : back_bgr;
assign blended_bgr = { blend8(bgr[23:16], back_sel[23:16], alpha_lv),   // B
                       blend8(bgr[15: 8], back_sel[15: 8], alpha_lv),   // G
                       blend8(bgr[ 7: 0], back_sel[ 7: 0], alpha_lv) }; // R

endmodule