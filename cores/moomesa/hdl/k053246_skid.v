/* =============================================================================================
    k053246_skid.v — buffer de 1 tile entre el SCAN de sprites y el DIBUJANTE (jtframe_objdraw).
    COWBOYS (Moo Mesa). Nuevo en la sesion 25. No existe equivalente en el arbol compartido.

    -- QUE PROBLEMA RESUELVE -------------------------------------------------------------------
    Sprites CORTADOS en placa (fase 2, vagon del tren): el scan no llega al final de la tabla de
    objetos dentro de la linea, y lo que no alcanza NO SE DIBUJA. Es presupuesto de tiempo.

    MEDIDO en la escena 14198 (87 sprites) a CLKDIV=6 (ratio real de placa, 1536 pasos cen2/linea),
    con la instrumentacion de k053246_scan.sv:

        reparto pasos/linea: skip(obj inactivo)=99  setup=339  draw+espera=701
        de esos 701 del estado draw, ciclos_parado_por_dr_busy = 632  => el 90 % es ESPERA PURA
        (solo ~69 pasos son trabajo real: 1 por cada tile enviado)
        dibujante: 69 tiles/linea x 10 cen2 = 720 cen2 ocupado (20 clk por tile de 16 px, 1 px/clk)

    El scan y el dibujante estan SERIALIZADOS: el scan se para a esperar a que el dibujante acabe
    el tile N antes de siquiera empezar a calcular el N+1. Solapandolos, el coste de la linea pasa
    de `suma` a `max(scan ~507, dibujante 720) = 720` de 1536 disponibles => cabe con holgura.

    -- POR QUE UN SKID Y NO TOCAR EL FSM DEL SCAN ----------------------------------------------
    El FSM del scan es fragil y ya lo demostro: quitarle el gate `cen2` para acelerarlo (FAST_SCAN)
    daba CERO sprites, porque ese gate le da slack al pipeline de zoom y a la latencia de la scan
    RAM (ver el analisis en k053246_scan.sv). Aqui NO se toca ni una linea de ese FSM.

    El truco es que `jtframe_objdraw` se instancia con **LATCH(1)**: captura code/xpos/ysub/hflip/
    vflip/pal/hzoom/hz_keep en el ciclo en que `draw` sube y `busy` esta bajo. Es decir, las
    senales del tile solo tienen que ser validas EN ESE CICLO. Este modulo hace exactamente lo
    mismo un ciclo antes: captura el tile cuando el scan lo emite y se lo entrega al dibujante en
    cuanto queda libre. Para el scan, `busy` deja de significar "el dibujante esta pintando" y pasa
    a significar "no tengo sitio para otro tile" => puede adelantar un tile de trabajo.

    ORDEN: es un FIFO de 1 elemento, preserva el orden de emision. Critico, porque el orden de
    dibujo es el que resuelve la PRIORIDAD entre sprites solapados (ver la sesion 17, orden-Z).

    FLUSH EN HS: al empezar la linea el scan se reinicia; si el skid guardase un tile de la linea
    anterior lo pintaria fuera de sitio. `hs` lo vacia.
   ============================================================================================= */

/*  -- POR QUE UNA COLA Y NO UN SOLO HUECO (medido, ses.25) -----------------------------------
    La primera version tenia UN hueco (skid de 1 tile). Medido en 14198/CLKDIV=6: 7.57 % -> 6.69 %,
    stall 632 -> 587. Casi nada. Razon: el scan genera los hsteps de un objeto MAS RAPIDO de lo que
    el dibujante los consume (1 paso vs 9), asi que llena el hueco y se bloquea igual; y cuando por
    fin pasa al objeto siguiente, sus ~5 pasos de SETUP ocurren con el dibujante ya OCIOSO.
    Es decir: los 376 pasos/linea de setup NUNCA se solapaban con el dibujo.
    Con una COLA de varios tiles el scan vuelca de golpe los hsteps del objeto N y se va a hacer el
    setup del N+1 MIENTRAS el dibujante drena la cola => setup y dibujo por fin se solapan.
    DEPTH=8 cubre el objeto mas ancho (hsz=3 => 8 hsteps).                                        */

module k053246_skid #( parameter DEPTH_LN = 1 )( // profundidad = 2**DEPTH_LN tiles
    input             rst,
    input             clk,
    input             hs,

    // lado SCAN (productor)
    input             dr_start,
    output            dr_busy,     // "no hay sitio", NO "el dibujante esta ocupado"
    input      [15:0] code,
    input      [ 9:0] hpos,
    input      [ 3:0] ysub,
    input      [11:0] hzoom,
    input             hz_keep,
    input             hflip,
    input             vflip,
    input      [ 9:0] attr,
    input      [ 1:0] shd,

    // lado DIBUJANTE (consumidor)
    output reg        q_start,
    input             q_busy,      // busy real de jtframe_objdraw
    output reg [15:0] q_code,
    output reg [ 9:0] q_hpos,
    output reg [ 3:0] q_ysub,
    output reg [11:0] q_hzoom,
    output reg        q_hz_keep,
    output reg        q_hflip,
    output reg        q_vflip,
    output reg [ 9:0] q_attr,
    output reg [ 1:0] q_shd
);

localparam DEPTH = 1<<DEPTH_LN,
           TW    = 16+10+4+12+1+1+1+10+2;   // ancho de un tile en la cola = 57 bits

reg [TW-1:0]       fifo[0:DEPTH-1];
reg [DEPTH_LN:0]   wptr, rptr;              // 1 bit extra para distinguir lleno de vacio

wire [DEPTH_LN:0]  ocup  = wptr - rptr;
wire               llena = ocup >= DEPTH[DEPTH_LN:0];
wire               vacia = wptr == rptr;

// El scan solo espera si la cola esta LLENA (antes esperaba a que el dibujante acabase el tile).
assign dr_busy = llena;

// se entrega cuando hay algo y el dibujante ni pinta ni acaba de arrancar (su busy sube 1 clk
// despues de `draw`, por `pre_bsy|dr_draw` en jtframe_objdraw con LATCH=1)
wire deliver = ~vacia & ~q_busy & ~q_start;

wire [TW-1:0] tile_in  = { code, hpos, ysub, hzoom, hz_keep, hflip, vflip, attr, shd };
wire [TW-1:0] tile_out = fifo[ rptr[DEPTH_LN-1:0] ];

// ⛔ EL FLUSH VA POR FLANCO, NO POR NIVEL. Primera version (ses.25) uso el NIVEL de `hs` y ROMPIO
// escenas pixel-exactas (1800: 0.0000 % -> 4.54 %). Razon: el scan se reinicia en el FLANCO
// (`hs && !hs_l` en k053246_scan.sv) y sigue emitiendo tiles durante el RESTO del pulso de hs, que
// dura varios ciclos => con el flush por nivel esos tiles se tiraban a la basura.
reg hs_l;
always @(posedge clk) hs_l <= hs;
wire hs_edge = hs & ~hs_l;

always @(posedge clk) begin
    if( rst ) begin
        wptr    <= 0;
        rptr    <= 0;
        q_start <= 0;
    end else begin
        q_start <= 0;
        if( hs_edge ) begin         // linea nueva: el scan se reinicia, no arrastres tiles
            wptr    <= 0;
            rptr    <= 0;
            q_start <= 0;
        end else begin
            if( deliver ) begin
                q_start <= 1;
                { q_code, q_hpos, q_ysub, q_hzoom,
                  q_hz_keep, q_hflip, q_vflip, q_attr, q_shd } <= tile_out;
                rptr    <= rptr + 1'd1;
            end
            if( dr_start & ~llena ) begin
                fifo[ wptr[DEPTH_LN-1:0] ] <= tile_in;
                wptr <= wptr + 1'd1;
            end
        end
    end
end

endmodule
