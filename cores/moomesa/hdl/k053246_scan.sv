/* =============================================================================================
    k053246_scan.sv — FORK PROPIO del motor de sprites (K053246/K053247) de COWBOYS (Moo Mesa).
    Origen: cores/simson/hdl/jt053246_scan.sv  (arbol jtcores, COMPARTIDO con simson/xmen/rungun...).
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

    Author: Rafael Eduardo Paiva Feener. Copyright: Miki Saito
    Version: 1.0
    Date: 23-9-2024 */

// See JTSIMSON's README.md

module k053246_scan (    // sprite logic
    input             rst,
    input             clk,
    input      [ 9:0] voffset,

    output reg        done,
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
    input             hs,

    input      [15:0] scan_even, 
    input      [15:0] scan_odd,
    input      [ 9:0] xoffset,
    input      [ 9:0] yoffset,
    input             ghf, gvf,
    output     [11:2] scan_addr,

    // shadow
    output reg [ 1:0] shd,

    // indr module / 051937
    output reg        dr_start,
    input             dr_busy,

    // Debug
    input      [ 7:0] debug_bus
);
parameter [7:0] SCAN_START = 8'd0;
parameter [8:0] BOTTOM     = 9'h1F7;
parameter [9:0] HOFFSET    = 10'd62;

localparam [11:0] MAX_ZOOMIN= 6; // a value below 3 will break the "pass" scene in run&gun
localparam [ 9:0] HDUMP_MIN = 10'h020,
                  HADJ      = 10'h008;

// ── ✅ CULL-X EN EL SCAN v2 (ses.36): GEOMETRÍA CORRECTA (width + wrap). Reemplaza el cull v1 de ses.35
//    que ROMPIÓ LA PLACA. La causa del fallo v1 NO fue la ventana ([4..387] estaba bien) sino la CONDICIÓN:
//    v1 cullaba el sprite entero por x2 (tile IZQUIERDO) en una banda fija [480..1000] IGNORANDO la anchura
//    y el WRAP del buffer de 1024. Un sprite ancho (jefe, hasta 128px) con x2 en esa banda EXTIENDE sus
//    tiles derechos hacia lo visible (o envuelve mod-1024 a la izquierda) => v1 borraba sprites VISIBLES.
//
//    v2: se culla el sprite SOLO si su FOOTPRINT COMPLETO [x2 .. x2+Wpx-1] mod 1024 NO toca la ventana
//    visible [VIS_LO..VIS_HI] (medida por el tb: rd_addr real = [4..387]). Wpx = 16<<hsz (anchura no-zoom).
//    Solo no-zoom (hzoom==64), donde el footprint es exacto. Chain-safe por construcción: o se dibuja el
//    sprite ENTERO o se culla ENTERO (nunca parcial => no rompe la cadena hz_keep del dibujante).
//    Banda cullable resultante = [VIS_HI+1+M .. VIS_LO+1024-Wpx-M] (depende de la anchura). Margen M por
//    seguridad de overscan placa-vs-sim. VALIDAR: rgbdiff no sube en NINGUNA escena (vagon 11971-12018 +
//    jefe 24xxx-25xxx + controles), no solo 1800/11971 (el error de ses.35 fue validar 2 escenas).
// ⭐⭐ RAÍZ DEFINITIVA (ses.36): la ventana visible en coords de BUFFER es [150..532]. MEDIDA del RTL
//    (no de una replica): sonda RDMAP en k053247_gate -> hdf = columna_visible + 149, cols 0..383 -> buffer
//    [150..532]. Las "mediciones" previas [4..387] (mod-512) y [516..899] (mod-1024) eran ALIAS de esta por
//    el masking del tb. TODOS los cull-X de ses.26/33/35 usaron ventanas aliaseadas y por eso borraban
//    sprites visibles (x2 in [396..480] CAE dentro de [150..532] = visible; por eso rompian el jinete/jefe).
//    Se trabaja en coord DESPLAZADA x2s=(x2-150) mod 1024 -> ventana visible = [0..382]. Cullable = footprint
//    [x2s..x2s+Wpx-1] mod 1024 sin tocar [0..382] <=> x2s in [383+M .. 1024-Wpx-M].
localparam        XCULL_S_EN = 1;
localparam [ 9:0] VIS_SHIFT  = 10'd874;  // -150 mod 1024, lleva la ventana [150..532] a [0..382]
localparam [10:0] XMARGIN    = 11'd8;    // px de guarda cada lado (overscan placa-vs-sim)

reg  [18:0] yz_add;
reg  [11:0] vzoom;
reg  [ 9:0] y, y2, x, ydiff, ydiff_b, xadj, yadj, x2;
reg  [10:0] Wpx, cull_lo, cull_hi;   // cull-X v2 (ses.36): anchura y banda cullable (11-bit por el +1024)
reg  [ 9:0] x2s;                     // x2 en coord desplazada (ventana visible -> [0..383])
reg  [ 8:0] vlatch, ymove, vscl, hscl;
reg  [ 7:0] scan_obj/*, zcode*/; // max 256 objects
reg  [ 3:0] size;
reg  [ 2:0] hstep, hcode, hsum, vsum;
reg  [ 1:0] scan_sub, reserved;
reg         inzone, hs_l, hdone,
            vmir, hmir, sq, pre_vf, pre_hf, indr,
            hmir_eff, vmir_eff, hhalf, left_wrap, offscr_x;

wire [ 1:0] nx_mir, hsz, vsz;
wire        last_obj;

// ── CULL-X POR-TILE (sufijo derecho, ses.36): deja de dibujar los tiles de un sprite PARCIALMENTE visible
//    en cuanto cruzan el borde derecho (532). Es un SUFIJO (los tiles van a la derecha, hpos monotono +16)
//    => tras el 1er tile off-right todos lo estan => CHAIN-SAFE: no hay ningun tile dibujado DESPUES del cull,
//    la cadena hz_keep del dibujante no se rompe. Solo la mitad "derecha" del off-screen desplazado
//    [383+M..511]; NO la zona [874..1023] (izquierda, que envuelve): un sprite que ENTRA por la izquierda
//    tiene sus tiles fuera al PRINCIPIO (prefijo) y cullarlos SI romperia la cadena. Complementa el cull de
//    sprite-entero (offscr_x): este rasca el sufijo de los que asoman por la izquierda-visible y se salen.
wire [ 9:0] hpos_nx  = (hstep==3'd0) ? (x2 + (left_wrap ? HADJ : 10'b0)) : (hpos + 10'h10);
wire [ 9:0] ts_tile  = hpos_nx + VIS_SHIFT;   // pos del tile en coord desplazada (visible=[0..382])
wire        tile_offr = XCULL_S_EN && (hzoom==12'd64)
                      && (ts_tile >= (10'd383 + XMARGIN[9:0])) && (ts_tile <= 10'd511);
// MEDICION (ses.36, MEASURE_OFFL): tiles off-screen-IZQUIERDA (footprint entero buffer<150 => ts en
// [874..1008]). Es el PREFIJO de sprites que salen por la izquierda (vagon). Culларlos requiere arreglar
// la cadena hz_keep (el 1er tile visible debe resetear buf_addr) => NO se hace aqui (rompe imagen). Con
// MEASURE_OFFL=1 solo se SALTA el dibujo (dr_start=0) sin jump, para MEDIR cuanto baja el throughput.
localparam MEASURE_OFFL = 0;
wire        tile_offl = MEASURE_OFFL && (hzoom==12'd64)
                      && (ts_tile >= 10'd874) && (ts_tile <= 10'd1008);
reg  [ 8:0] zoffset [0:255];
reg  [ 3:0] pzoffset[0:15 ];
integer     missing;
// ── INSTRUMENTACION DEL PRESUPUESTO POR LINEA (fork cowboys, ses.24) ─────────────────────────
// Objetivo: saber DONDE se va el tiempo de la linea. La metrica `uncompleted lines` dice QUE no
// termina, pero no POR QUE. Aqui separamos: cuantos objetos entran en zona (=hay que dibujarlos) y
// cuantos ciclos se queda el scan PARADO esperando al dibujante (dr_busy). Si domina lo segundo, el
// cuello de botella es jtframe_objdraw, no recorrer la tabla.
// Solo simulacion: todo dentro de `ifndef SYNTHESIS` para que no toque la sintesis.
`ifndef SYNTHESIS
integer     dbg_inzone, dbg_stall, dbg_lines, dbg_objs, dbg_busy, dbg_starts;
integer     tot_inzone, tot_stall, tot_lines, tot_objs, tot_busy, tot_starts;
// ses.25: REPARTO del coste por categoria. Sin esto no se puede dimensionar el fix: si lo que se come
// la linea es SALTAR objetos inactivos (1 paso cada uno, 256 en total), solapar scan y dibujante NO
// basta. Cada contador suma PASOS cen2 gastados en su categoria.
integer     dbg_skip, dbg_setup, dbg_draw, dbg_nozone, dbg_avail;
integer     tot_skip, tot_setup, tot_draw, tot_nozone, tot_avail;
`endif

assign hflip     = ghf ^ pre_hf ^ hmir_eff;
assign scan_addr = { scan_obj, scan_sub };
assign ysub      = ydiff[3:0];
assign last_obj  = &scan_obj[7:0];
assign nx_mir    = scan_even[15:14];
assign {vsz,hsz} = size;

// ── ACELERACION DEL RECORRIDO (fork cowboys, ses.25) ────────────────────────────────────────
// MEDIDO en 14198 a CLKDIV=6 (1536 pasos cen2 de presupuesto por linea):
//    ciclos_parado_por_dr_busy = 632   (41 % del presupuesto esperando al dibujante)
//    dibujante ocupado/linea   = 720 cen2  (69 tiles enviados x 10 cen2 = 20 clk por tile de 16 px)
//    => recorrido puro = 1536-632 = ~904 pasos, que a clk/2 cuestan ~1808 clk de los 3072 de la linea.
// ⛔ PROBADO Y DESCARTADO (ses.25): correr el FSM a clk pleno (FAST_SCAN=1) NO FUNCIONA.
//    Medido en 14198/CLKDIV=6: `spr_nz=0`, `romcs=0` -> CERO sprites dibujados, rgbdiff 41.82 %.
//    EL GATE `cen2` NO ES GRATIS: da un ciclo de slack a DOS cosas que el FSM consume al ciclo
//    siguiente de pedirlas, y ninguna esta registrada dentro del propio FSM:
//      (a) el pipeline de zoom del always @(posedge clk) de arriba: y (paso 1) -> y2/ydiff_b ->
//          yz_add -> `inzone`, que el paso 4 lee con 2 clk de retraso. A clk pleno `inzone` es
//          basura => TODO objeto sale fuera de zona => no se envia ni un dr_start.
//      (b) la latencia de la RAM de objetos: `scan_addr` es combinacional y `scan_even/odd` llegan
//          1 clk despues; a clk pleno el paso N lee el dato del objeto anterior.
//    => acelerar el recorrido exige PIPELINAR de verdad (registrar inzone/scan_even por etapa), no
//    quitar el gate. Dejado a 0: es el comportamiento correcto y validado.
// ⭐ Y OJO AL REPARTO REAL DEL PRESUPUESTO: lo que domina NO es recorrer la tabla, es que el scan se
//    SERIALIZA con el dibujante (632 cen2 parados + 720 ocupados). El fix de mas valor es solapar
//    ambos (preparar el tile N+1 mientras jtframe_draw pinta el N), no correr mas rapido la tabla.
parameter FAST_SCAN = 0;

(* direct_enable *) reg cen2_div=0;
wire cen2 = FAST_SCAN ? 1'b1 : cen2_div;
always @(negedge clk) cen2_div <= ~cen2_div;

always @(posedge clk) begin
    xadj <= xoffset - HOFFSET;
    yadj <= yoffset + voffset;
    vscl <= rd_pzoffset(vzoom[9:0]);
    hscl <= rd_pzoffset(hzoom[9:0]);
    ydiff_b <= y2 + { vlatch[8], vlatch };
    /* verilator lint_off WIDTH */
    yz_add  <= vzoom[9:0]*ydiff_b; // vzoom < 10'h40 enlarge, >10'h40 reduce
                                   // opposite to the one in Aliens, which always
                                   // shrunk for non-zero zoom values
    /* verilator lint_on WIDTH */
end

function [8:0] zmove( input [1:0] sz, input[8:0] scl );
    case( sz )
        0: zmove = scl>>2;
        1: zmove = scl>>1;
        2: zmove = scl;
        3: zmove = scl<<1;
    endcase
endfunction

function [8:0] rd_pzoffset( input [9:0] zoom );
    case( zoom[9:8] )
        0:       rd_pzoffset =        zoffset[zoom[7:0]];
        1:       rd_pzoffset = {5'b0,pzoffset[zoom[7:4]]};
        2:       rd_pzoffset =  9'd3;
        3:       rd_pzoffset =  9'd2;
    endcase
endfunction

always @* begin : B
    ymove     = zmove( vsz, vscl );
    y2        = y + {1'b0,ymove};
    ydiff     = yz_add[6+:10];
    x2        = x - zmove( hsz, hscl );
    left_wrap = x2 < HDUMP_MIN;
    // sprite 100% fuera de pantalla-X (solo no-zoom): footprint COMPLETO [x2..x2+Wpx-1] mod 1024 fuera de
    // [VIS_LO..VIS_HI]. Wpx=16<<hsz. Banda cullable = [VIS_HI+1+M .. VIS_LO+1024-Wpx-M] (width-aware, wrap
    // correcto). Se descarta el sprite entero por el camino ~inzone del paso 4 (chain-safe). Ver cabecera.
    Wpx       = 11'd16 << hsz;                                   // anchura del sprite en px (no-zoom)
    x2s       = x2 + VIS_SHIFT;                                  // coord desplazada: visible = [0..382]
    cull_lo   = 11'd383 + XMARGIN;                               // footprint entero pasado el borde derecho
    cull_hi   = 11'd1024 - Wpx - XMARGIN;                        // antes de que el wrap re-entre a visible
    offscr_x  = XCULL_S_EN && (hzoom==12'd64)
             && ({1'b0,x2s} >= cull_lo) && ({1'b0,x2s} <= cull_hi);
    // test ver/game/scene/1 -> shadow, scan_obj 9
    case( vsz )
        0: vmir_eff = nx_mir[1] && !ydiff[3];
        1: vmir_eff = nx_mir[1] && !ydiff[4];
        2: vmir_eff = nx_mir[1] && !ydiff[5];
        3: vmir_eff = nx_mir[1] && !ydiff[6];
    endcase
    hmir_eff = hmir & hhalf;
    case( vsz )
        0: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:4]==0; // 16
        1: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:5]==0; // 32
        2: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:6]==0; // 64
        3: inzone = ydiff_b[9]==ydiff[9] && ydiff[9:7]==0; // 128
    endcase
    if( |yz_add[17:16] ) inzone=0;
    case( hsz )
        0: hdone = 1;
        1: hdone = hstep==1;
        2: hdone = hstep==3;
        3: hdone = hstep==7;
    endcase
    case( hsz )
        0: hsum = 0;
        1: hsum = hmir ? 3'd0                           : {2'd0,hstep[0]^hflip};
        2: hsum = hmir ? {2'd0,hstep[0]^hflip}          : {1'd0,hstep[1:0]^{2{hflip}}};
        3: hsum = hmir ? ({1'b0,hstep[1:0]^{2{hflip}}}) : hstep[2:0]^{3{hflip}};
    endcase
    case( vsz )
        0: vsum = 0;
        1: vsum = { 2'd0, ydiff[4]^vflip   };
        2: vsum = { 1'd0, ydiff[5:4]^{2{vflip}} };
        3: vsum = ydiff[6:4]^{3{vflip}};
    endcase
end

// Table scan
always @(posedge clk) begin : A
    if( rst ) begin
        hs_l     <= 0;
        scan_obj <= 0;
        scan_sub <= 0;
        hstep    <= 0;
        code     <= 0;
        attr     <= 0;
        pre_vf   <= 0;
        pre_hf   <= 0;
        vflip    <= 0;
        vzoom    <= 0;
        hzoom    <= 0;
        hz_keep  <= 0;
        indr     <= 0;
        hhalf    <= 0;
        shd      <= 0;
        done     <= 0;
    end else if( cen2 ) begin
        hs_l <= hs;
`ifndef SYNTHESIS
        if( dr_busy  ) dbg_busy   <= dbg_busy + 1;      // ciclos (cen2) con el dibujante OCUPADO
        if( dr_start ) dbg_starts <= dbg_starts + 1;    // objetos ENVIADOS a dibujar
        dbg_avail <= dbg_avail + 1;   // PRESUPUESTO real de la linea, en pasos cen2 (depende de CLKDIV)
`endif
        dr_start <= 0;
        if( hs && !hs_l && vdump>9'h10D && vdump<=BOTTOM) begin
`ifndef SYNTHESIS
            // ⚠️ ses.25: acumular SOLO las lineas que NO terminaron (scan_obj!=0). Antes se
            // promediaba sobre TODAS y la media mezclaba las lineas faciles (terminan y les sobran
            // pasos) con las que fallan -> salia el absurdo "gasta 1119 de 1732 disponibles y aun
            // asi no termina", y se optimizaba a ciegas. Las lineas que importan son las que fallan.
            if( scan_obj!=0 ) begin
                tot_inzone <= tot_inzone + dbg_inzone; tot_stall <= tot_stall + dbg_stall;
                tot_objs   <= tot_objs   + dbg_objs;   tot_lines <= tot_lines + 1;
                tot_busy   <= tot_busy   + dbg_busy;   tot_starts<= tot_starts + dbg_starts;
                tot_skip   <= tot_skip   + dbg_skip;   tot_setup <= tot_setup + dbg_setup;
                tot_draw   <= tot_draw   + dbg_draw;   tot_nozone<= tot_nozone+ dbg_nozone;
                tot_avail  <= tot_avail  + dbg_avail;
            end
            dbg_inzone <= 0; dbg_stall <= 0; dbg_objs <= 0; dbg_lines <= dbg_lines + 1;
            dbg_busy <= 0; dbg_starts <= 0;
            dbg_skip <= 0; dbg_setup <= 0; dbg_draw <= 0; dbg_nozone <= 0; dbg_avail <= 0;
`endif
            done     <= 0;
            scan_obj <= SCAN_START;
            scan_sub <= 0;
            indr     <= 0;
            vlatch   <= vdump;
            if( scan_obj!=0 ) begin
                $display("[FORK-COWBOYS] Obj scan did not finish. Last obj %X",scan_obj);
                missing <= missing + 1;
            end
            if(vdump==BOTTOM && missing!=0 ) begin
                missing <= 0;
                $display("%d uncompleted lines",missing);
`ifndef SYNTHESIS
                if( tot_lines>0 )
                    $display("[FORK-COWBOYS] presupuesto/linea: objetos=%0d en_zona=%0d ciclos_parado_por_dr_busy=%0d (media de %0d lineas)",
                        tot_objs/tot_lines, tot_inzone/tot_lines, tot_stall/tot_lines, tot_lines);
                if( tot_starts>0 )
                    $display("[FORK-COWBOYS] dibujante: enviados/linea=%0d  ocupado/linea=%0d cen2  => %0d cen2 POR OBJETO",
                        tot_starts/tot_lines, tot_busy/tot_lines, tot_busy/tot_starts);
                if( tot_lines>0 )
                    $display("[FORK-COWBOYS] reparto pasos/linea: skip(obj inactivo)=%0d setup=%0d draw+espera=%0d (fuera_de_zona=%0d) TOTAL=%0d de %0d disponibles",
                        tot_skip/tot_lines, tot_setup/tot_lines, tot_draw/tot_lines, tot_nozone/tot_lines,
                        (tot_skip+tot_setup+tot_draw)/tot_lines, tot_avail/tot_lines);
                tot_objs<=0; tot_inzone<=0; tot_stall<=0; tot_lines<=0; tot_busy<=0; tot_starts<=0;
                tot_skip<=0; tot_setup<=0; tot_draw<=0; tot_nozone<=0; tot_avail<=0;
`endif
            end
        end else if( !done ) begin
`ifndef SYNTHESIS
            // reparto del coste: cada paso cen2 cae en UNA categoria
            if( {indr,scan_sub}>=3'd5 )          dbg_draw  <= dbg_draw  + 1; // dibujar/esperar dr_busy
            else if( {indr,scan_sub}==0 )
                if( !scan_even[15] )             dbg_skip  <= dbg_skip  + 1; // objeto INACTIVO: 1 paso
                else                             dbg_setup <= dbg_setup + 1;
            else begin                           dbg_setup <= dbg_setup + 1;
                if( {indr,scan_sub}==3'd4 && ~inzone ) dbg_nozone <= dbg_nozone + 1; // activo pero fuera
            end
`endif
            {indr, scan_sub} <= {indr, scan_sub} + 1'd1;
            case( {indr, scan_sub} )
                0: begin
                    hhalf <= 0;
                    { sq, pre_vf, pre_hf, size } <= scan_even[14:8];
                    code    <= scan_odd;
                    hstep   <= 0;
                    hz_keep <= 0;
                    if( !scan_even[15] /*`ifndef JTFRAME_RELEASE || (scan_obj[6:0]==debug_bus[6:0] && flicker) `endif*/ ) begin
                        scan_sub <= 0;
                        scan_obj <= scan_obj + 1'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                1: begin
                    y <= gvf ? -scan_even[9:0] : scan_even[9:0];
                    x <= ghf ? -scan_odd[ 9:0] : scan_odd[ 9:0];
                    hcode <= {code[4],code[2],code[0]};
                    hstep <= 0;
                end
                2: begin
                    x <= x-xadj;
                    y <= y+yadj;
                    vzoom <= {2'b0, scan_even[9:0]};
                    hzoom <= sq ? {2'b0, scan_even[9:0]} : {2'b0, scan_odd[9:0]};
                end
                3: begin
                    { vmir, hmir } <= nx_mir;
                    { reserved, shd, attr } <= scan_even[13:0];
                    vflip <= pre_vf ^ gvf ^ vmir_eff;
                    if( hzoom < MAX_ZOOMIN ) begin
                        { indr, scan_sub } <= 0;
                        scan_obj <= scan_obj + 1'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                4: begin
                    // Add the vertical offset to the code, must wait for zoom
                    // calculations, so it cannot be done at step 3
                    {code[5],code[3],code[1]} <= {code[5],code[3],code[1]} + vsum;
`ifndef SYNTHESIS
                    if( inzone && offscr_x )   // sprites Y-visibles que el X-cull descarta: los sospechosos
                        $display("XCULL2 x2=%0d x2s=%0d Wpx=%0d hzoom=%0d obj=%0X band_s=[%0d..%0d]",
                                 x2, x2s, Wpx, hzoom, scan_obj, cull_lo, cull_hi);
`endif
                    if( ~inzone || offscr_x ) begin   // Y-cull  ||  X-cull (sprite 100% fuera en X, ses.35)
                        { indr, scan_sub } <= 0;
                        scan_obj <= scan_obj + 1'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                default: begin // in draw state
                    case( hsz )
                        1: if(hstep>=1) hhalf <= 1;
                        2: if(hstep>=2) hhalf <= 1;
                        3: if(hstep>=4) hhalf <= 1;
                    endcase
                    {indr, scan_sub} <= 5; // stay here
`ifndef SYNTHESIS
                    if( !((!dr_start && !dr_busy) || !inzone) ) dbg_stall <= dbg_stall + 1;
`endif
                    if( (!dr_start && !dr_busy) || !inzone ) begin
                        {code[4],code[2],code[0]} <= hcode + hsum;
                        if( hstep==0 ) begin
                            hpos    <= x2 + (left_wrap ? HADJ : 10'b0 );
                        end else begin
                            hpos    <= hpos + 10'h10;
                            hz_keep <= 1;
                        end
                        hstep <= hstep + 1'd1;
                        dr_start <= inzone && !tile_offr && !tile_offl;  // no dibujar off-right ni off-left(medicion)
                        if( hdone || !inzone || tile_offr ) begin  // fin sprite: hdone, fuera-Y, o cruzo borde derecho
`ifndef SYNTHESIS
                            dbg_objs <= dbg_objs + 1;
                            if( inzone ) dbg_inzone <= dbg_inzone + 1;
`endif
                            { indr, scan_sub } <= 0;
                            scan_obj <= scan_obj + 1'd1;
                            indr     <= 0;
                            if( last_obj ) done <= 1;
                        end
                    end
                end
            endcase
        end
    end
end

initial pzoffset ='{
    8, 7, 7, 6, 6, 6, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4
};

initial zoffset ='{                             //  octal count
    511, 511, 511, 511, 511, 410, 341, 293,     //   0-  7
    256, 228, 205, 186, 171, 158, 146, 137,     //  10- 17
    128, 120, 114, 108, 102,  98,  93,  89,     //  20- 27
     85,  82,  79,  76,  73,  71,  68,  66,     //  30- 37
     64,  62,  60,  59,  57,  55,  54,  53,     //  40- 47
     51,  50,  49,  48,  47,  46,  45,  44,     //  50- 57
     43,  42,  41,  40,  39,  39,  38,  37,     //  60- 67
     37,  36,  35,  35,  34,  34,  33,  33,     //  70- 77
     32,  32,  31,  31,  30,  30,  29,  29,     // 100-107
     28,  28,  28,  27,  27,  27,  26,  26,     // 110-117
     26,  25,  25,  25,  24,  24,  24,  24,     // 120-127
     23,  23,  23,  23,  22,  22,  22,  22,     // 130-137
     21,  21,  21,  21,  20,  20,  20,  20,     // 140-147
     20,  20,  19,  19,  19,  19,  19,  18,     // 150-157
     18,  18,  18,  18,  18,  18,  17,  17,     // 160-167
     17,  17,  17,  17,  17,  16,  16,  16,     // 170-177
     16,  16,  16,  16,  16,  15,  15,  15,     // 200-207
     15,  15,  15,  15,  15,  15,  14,  14,     // 210-217
     14,  14,  14,  14,  14,  14,  14,  14,     // 220-122
     13,  13,  13,  13,  13,  13,  13,  13,     // 230-237
     13,  13,  13,  13,  12,  12,  12,  12,     // 240-247
     12,  12,  12,  12,  12,  12,  12,  12,     // 250-257
     12,  12,  12,  11,  11,  11,  11,  11,     // 260-267
     11,  11,  11,  11,  11,  11,  11,  11,     // 270-277
     11,  11,  11,  11,  10,  10,  10,  10,     // 300-307
     10,  10,  10,  10,  10,  10,  10,  10,     // 310-317
     10,  10,  10,  10,  10,  10,  10,  10,     // 320-327
      9,   9,   9,   9,   9,   9,   9,   9,     // 330-337
      9,   9,   9,   9,   9,   9,   9,   9,     // 340-347
      9,   9,   9,   9,   9,   9,   9,   9,     // 350-357
      9,   8,   8,   8,   8,   8,   8,   8,     // 360-367
      8,   8,   8,   8,   8,   8,   8,   8      // 370-377
};

endmodule