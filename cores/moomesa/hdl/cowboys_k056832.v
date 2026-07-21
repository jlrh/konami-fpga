/*  This file is part of JTCORES (fork COWBOYS). GPLv3. Crédito Jose Tejada / JTFRAME.

    cowboys_k056832 — tilemap Konami K056832 (Moo Mesa). Reemplaza jt052109/jt051962 de X-Men.
    Traduce el algoritmo VALIDADO 0.00% del golden (tools/cowboys_golden_prio.py) a RTL.
    Arquitectura: line-buffer con doble-buffer (ping-pong). 4 capas (FIX + 3 scroll).
    Blueprint: research/K056832-RTL-DESIGN.md. Validar con tb_k056832 (sim==golden).

    Salida por capa: lyrX_pxl[7:0] = { colnib[3:0], pen[3:0] }.
      colnib = (attr>>4)&0xf (fbits=3). El colorbase (K053251, FIX=0x70) lo añade colmix.
      pen==0 => transparente.

    Fetch (por línea 'vrender', para mostrar en la siguiente): por cada capa y tile de la línea:
      Xtm=(40+px+scrollX)&511, Ytm=(vrender+scrollY)&255 ; scrollX=dx[L]-offx[L].
      attr=vram[page*0x1000 + (row*64+col)*2] ; code=vram[+1].
      rom_row = code*8 + (flipY?7:0 ^ ty) ; 32b = 4 bytes (b0..b3) ; pen(tx)=nibble por byte {1,1,0,0,3,3,2,2}.
    Presupuesto: 4 capas*49 tiles*~11 clk ≈ 2156 clk/línea < 3072 (384px*8). OK.

    NOTA sim: la ROM de tiles la sirve el testbench (lyrX_data combinacional). En HW será SDRAM
    con line-fetch (mismo modelo, el margen de línea lo permite).
*/
module cowboys_k056832(
    input             rst,
    input             clk,
    input             pxl_cen,

    output            lhbl, lvbl, hs, vs,
    output     [ 8:0] hdump, vdump, vrender, vrender1,

    // CPU (68000, bus 16b)
    input             vram_cs,     // ventana 0x1a0000
    input             reg_cs,      // regs 0x0c0000
    input             cpu_we,
    input      [12:1] cpu_addr,    // word dentro de la ventana / reg idx en [5:1]
    input      [15:0] cpu_dout,
    output reg [15:0] cpu_din,

    // ROM de tiles (una lectura DW32 = una fila de 8 px). Dir = code*8 + fila.
    output reg [18:0] rom_addr,
    output reg [ 1:0] rom_lyr,     // capa que pide (para el testbench/SDRAM router)
    output            rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    // pixel out
    output     [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl,
    // flag de MEZCLA por pixel (attr[2] del tile) de cada capa de scroll — ver seccion line buffers
    output            lyra_mix, lyrb_mix, lyrc_mix,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

localparam signed [9:0] VX0 = 10'sd40;   // visarea X0
// layer_offs X = {-1,3,5,7}  (scrollX = dx - offs)
function signed [9:0] offx(input [1:0] l);
    case(l) 2'd0: offx=-10'sd1; 2'd1: offx=10'sd3; 2'd2: offx=10'sd5; default: offx=10'sd7; endcase
endfunction

// ---------------- vtimer MOO MESA (384x224, ~60Hz) — NO heredado de xmen (304px) ----------------
// H (Moo): activo 0..0x17F (384 col). HTOTAL=512 (HCNT_END=0x1FF). ⭐ SESION 18: el 456 provisional daba
//    17.54kHz/66.5Hz en placa (real moo.cpp:82-83 = 15.20kHz/59.19Hz) -> refresh ~12% rapido -> JUDDER de
//    scroll (66.5 vs 60 de la tele) y quiza tiles corruptos (poco hblank para el fetch de los line buffers).
//    pxl_cen=8MHz (K053252=32MHz/4) es correcto; solo el HTOTAL estaba mal. El real 526 (8M/15203) NO cabe
//    en el contador de 9 bits (por eso 0x20F=528 colgaba), pero 0x1FF=511 SI (=512 counts) -> 8M/512/264 =
//    59.19Hz (clavado). Activo 3..386 SIN tocar -> sim sigue pixel-exacto; los 56px extra -> hblank (72->128).
// V (KONAMI): vdump 0xF8..0x1FF (264 lineas), visible 0x110..0x1EF. IDENTICO a jt051962 (K052109) porque
//    el vertical de Moo == Konami; el obj (jt053246_scan) HARDCODEA este rango (scan si vdump>0x10D) y la
//    matematica de Y del sprite (voffset) esta calibrada a el. Antes usaba V origen-0 (0..263) y el obj
//    nunca escaneaba. Al re-basar V, VY0 pasa de 16 a 0 (0x110 mod 256 = 16 aporta el offset del visarea).
jtframe_vtimer #(
    .HCNT_START(9'h000), .HCNT_END(9'h1FF),   // HTOTAL 456->512: 66.5Hz->59.19Hz (ses.18, ver arriba)
    // ⭐ SESION 16: ventana activa DESPLAZADA +3 px para compensar la LATENCIA DEL PIPELINE del colmix
    // (K053251: paleta registrada -> {r8,g8,b8} -> bgr = ~3 clk). El RGB compuesto (tiles Y sprites, que
    // pasan ambos por colmix -> retardo UNIFORME) sale 3 px tarde; sin compensar, jtframe muestrea desde
    // H=0 y los 3 primeros px activos son basura pre-activo (COLUMNA NEGRA a la izq + todo corrido 3 px a
    // la derecha vs MAME — visible al comparar sim_snaps/mame_snaps). Al mover LHBL/HS +3, el muestreo
    // empieza en H=3, donde el RGB ya es content[0] -> alinea las dos capas de golpe SIN tocar el fetch.
    // Era el dx=3 / shift L=3 que rgbdiff barria y el HANDOFF tenia anotado como calibracion de timing HW.
    //   HB_START 0x17F(383)->0x182(386): activo 3..386 = 384 px exactos (mantiene el ancho, sin size mismatch).
    //   HB_END   0x1C7(455)->0x002(2)   : LHBL sube en H=3 (antes en H=0). Blanking 387..455,0,1,2 (wrap ok).
    //   HS_START 0x190(400)->0x193(403) : HS acompaña +3 -> imagen centrada igual respecto al sync (HW).
    .HB_START(9'h182), .HB_END(9'h002), .HS_START(9'h193),
    .V_START(9'h0F8), .VB_START(9'h1EF), .VB_END(9'h10F),
    .VS_START(9'h1FF), .VS_END(9'h0FF), .VCNT_END(9'h1FF)
) u_vtimer(
    .clk(clk), .pxl_cen(pxl_cen),
    .vdump(vdump), .vrender(vrender), .vrender1(vrender1),
    .H(hdump), .Hinit(), .Vinit(),
    .LHBL(lhbl), .LVBL(lvbl), .HS(hs), .VS(vs)
);

// ---------------- banco de registros de control (0x0c0000) ----------------
reg [15:0] mmr[0:31];
wire [4:0] reg_idx = cpu_addr[5:1];
// contador de bucle LOCAL en named block (`integer ri` dentro de `begin:mmr_rst`): Verilog-2001 legal
// (Quartus 17 RECHAZA `for(int ri...)` en un fichero .v -> error 10170; la sim Verilator lo tragaba ->
// solo el eslabon `cabe==sintetiza` lo caza, sesion 18). Sigue siendo LOCAL -> evita el latch del
// `integer` de modulo usado solo en el reset (warning 10240, motivo del cambio en sesion 16).
always @(posedge clk, posedge rst) begin : mmr_rst
    integer ri;
    if(rst) for(ri=0;ri<32;ri=ri+1) mmr[ri]<=0;
    else if(reg_cs & cpu_we) mmr[reg_idx]<=cpu_dout;
end
wire [1:0] fbits = mmr[5'h03][7:6];   // =3 en moomesa
function signed [9:0] dxL(input [1:0] l);
    case(l) 2'd0: dxL={mmr[5'h14][9],mmr[5'h14][8:0]}; 2'd1: dxL={mmr[5'h15][9],mmr[5'h15][8:0]};
            2'd2: dxL={mmr[5'h16][9],mmr[5'h16][8:0]}; default: dxL={mmr[5'h17][9],mmr[5'h17][8:0]}; endcase
endfunction
function signed [9:0] dyL(input [1:0] l);
    case(l) 2'd0: dyL={mmr[5'h10][9],mmr[5'h10][8:0]}; 2'd1: dyL={mmr[5'h11][9],mmr[5'h11][8:0]};
            2'd2: dyL={mmr[5'h12][9],mmr[5'h12][8:0]}; default: dyL={mmr[5'h13][9],mmr[5'h13][8:0]}; endcase
endfunction
function [3:0] pageL(input [1:0] l);   // pageIndex = (m_y<<2)|m_x ; m=(reg>>3)&3
    case(l) 2'd0: pageL={mmr[5'h08][4:3],mmr[5'h0c][4:3]}; 2'd1: pageL={mmr[5'h09][4:3],mmr[5'h0d][4:3]};
            2'd2: pageL={mmr[5'h0a][4:3],mmr[5'h0e][4:3]}; default: pageL={mmr[5'h0b][4:3],mmr[5'h0f][4:3]}; endcase
endfunction
wire [3:0] cpu_bank = {mmr[5'h19][4:3], mmr[5'h19][1:0]};

// ---------------- VRAM 16 páginas (0x10000 words) = jtframe_dual_ram (true dual-port) ----------------
// P0 = CPU (RW; mismo addr para el read-back y la escritura). P1 = video (RO, we1=0). Antes era un array
// crudo `reg vram[]` con 2 lecturas + 1 escritura en un solo always: infiere BRAM, PERO Quartus lo DUPLICA
// (2 Mbit para 1 Mbit real, ~256 M10K) por los 2 puertos de lectura. El true-dual-port usa UNA copia
// (~130 M10K). Lectura REGISTRADA (qq<=mem[addr]) = MISMA latencia de 1 clk que el array -> la FSM de fetch
// (F_ATTR/F_ATTR2...) no cambia. Sesion 16.
reg  [15:0] vid_addr;
wire [15:0] vram_qcpu, vram_qvid;
wire [15:0] cpu_vaddr = {cpu_bank, cpu_addr[12:1]};
jtframe_dual_ram #(.DW(16),.AW(16)) u_vram(
    .clk0(clk), .data0(cpu_dout), .addr0(cpu_vaddr), .we0(vram_cs & cpu_we), .q0(vram_qcpu),
    .clk1(clk), .data1(16'd0),    .addr1(vid_addr),  .we1(1'b0),            .q1(vram_qvid)
);
always @(posedge clk) cpu_din <= vram_cs ? vram_qcpu : reg_cs ? mmr[reg_idx] : 16'hffff;

// ---------------- line buffers (ping-pong) : 4 capas * 2 bancos * 384 * 8b ----------------
// OJO: el índice {fbank,outpx}/{dispbank,dpx} vale bank*512+px (outpx es de 9 bits, la concat
// desplaza el bit de banco 9 posiciones). Antes el array era [0:767] (bank*384) y las escrituras
// del banco 1 con px>=256 caían fuera de rango -> se perdían (píxeles 0 en cols>=256, en líneas de
// paridad impar). Dimensionado a 1024 = 2 bancos * 512.
// ⭐ SESION 16 (quartus_check): los line buffers eran arrays leidos COMBINACIONALMENTE
// (`assign lyrX_pxl = lbufX[rdaddr]`) -> 4 muxes 1024:1 = ~25K registros en LOGICA (medido:
// Total registers 25.243 en A&S). Ahora son 4x jtframe_rpwp_ram (1W/1R, lectura REGISTRADA ->
// infiere BRAM/MLAB). El +1 clk se asienta DENTRO del periodo de pixel: rdaddr={dispbank,dpx} solo
// cambia en pxl_cen, asi que el dout registrado ya es valido cuando colmix lo consume -> NO desplaza
// el pixel (patron empirecity; SINTESIS-READINESS.md §9). Instancias abajo, en la seccion de salida.
reg       dispbank;   // banco que se muestra (fetch escribe en ~dispbank)

// ---------------- FSM de fetch por línea (PIPELINE productor/consumidor, sesion 20) ----------------
// El fetch SERIAL costaba ~17 clk/tile (F_WRITE=8 px 1/clk + pipeline direcciones ~9) => ~3300-4000 clk/
// linea. A ratio clk/pxl_cen=6 (HW real: pxl_cen 8MHz / clk 48MHz) la linea son 512*6=3072 clk < coste
// => el fetch NO cabia: completaba 1 de cada 2 lineas => media res vertical de tiles = tilemap BAJA-RES
// SOLO EN HW. (Medido ses.20 con knob CLKDIV + reads/linea: 196@ratio8 -> 98@ratio6 -> 65@ratio6+lat25;
// el rgbdiff del vfull era CIEGO al bug por usar escena estatica: los bancos ping-pong convergen y un
// flip saltado re-muestra dato bueno. El gate real es reads/linea==196 a CLKDIV=6.)
// FIX: el PRODUCTOR genera attr/code/rom_data del tile N+1 mientras el CONSUMIDOR escribe los 8 px del
// tile N. Throughput = max(~7 productor, 8 consumidor) ~= 8-9 clk/tile => 196*9=1764 clk << 3072, con
// margen para la latencia real (avg 2.5, ses.19). Handoff de 1 tile entre etapas (hs_valid).
localparam P_IDLE=0, P_SETUP=1, P_ATTR=2, P_ATTR2=3, P_CODE=4, P_CODE2=5,
           P_ROM=6, P_ROM2=7, P_ROM3=8, P_DEP=9;
reg [3:0]  pf_st;        // estado productor
reg [1:0]  flyr;         // capa en curso (productor)
reg [5:0]  ftile;        // índice de tile en la línea (0..48) (productor)
reg [15:0] attr_p, code_p;
reg [31:0] romdata_p;
reg        fbank;        // banco de escritura (=~dispbank)
reg [8:0]  fline;        // línea a preparar (latcheada al arrancar el fetch)
reg        prev_lhbl;

localparam [0:0] C_IDLE=1'd0, C_WRITE=1'd1;    // dimensionados: cs_st es de 1 bit (evita warning 10230)
reg        cs_st;        // estado consumidor
reg [2:0]  fpx;          // pixel dentro del tile (consumidor)
reg [1:0]  wlyr;         // capa del tile que se escribe
reg [5:0]  wtile;        // índice de tile que se escribe
reg [15:0] attr_c;       // attr del tile en escritura (flipx, colnib)
reg [31:0] romdata_c;    // datos ROM del tile en escritura
reg [2:0]  subc;         // first_sub de la capa del tile en escritura

// Handoff 1-deep productor->consumidor
reg        hs_valid;
reg [15:0] h_attr;
reg [31:0] h_rom;
reg [5:0]  h_tile;
reg [1:0]  h_lyr;
reg [2:0]  h_sub;

// Direcciones PRODUCTOR (combinacional desde flyr, ftile, fline estables)
wire signed [11:0] Xbase_s = 12'sd40 + $signed(dxL(flyr)) - $signed(offx(flyr));
wire [8:0] baseX     = Xbase_s[8:0];              // mod 512
wire [2:0] first_sub = baseX[2:0];
wire [5:0] first_col = baseX[8:3];
wire [5:0] curcol    = first_col + ftile[5:0];    // mod 64 implícito
// VY0: con el vtimer re-basado a Konami, fline = vdump del display = 0x110+py, y 0x110 mod 256 = 16 ya
// aporta el offset del visarea (golden sy=16+py). Por eso VY0=0 (antes 16, con V origen-0). Ver vtimer.
localparam signed [11:0] VY0 = 12'sd0;
wire signed [11:0] Y_s = $signed({3'b0,fline}) + $signed(dyL(flyr)) + VY0;
wire [7:0] Ytm  = Y_s[7:0];                        // mod 256
wire [4:0] frow = Ytm[7:3];
wire [2:0] fty  = Ytm[2:0];
wire [11:0] tidx = {frow, curcol, 1'b0};           // (row*64+col)*2
wire [15:0] attr_addr = {pageL(flyr), tidx};
wire [15:0] code_addr = attr_addr | 16'h1;
wire       flipy_p = attr_p[1];
wire [2:0] tyf     = flipy_p ? ~fty : fty;

// Pen CONSUMIDOR (desde el tile latcheado del handoff)
wire       flipx_c = attr_c[0];
wire [3:0] colnib_c= attr_c[7:4];
wire [2:0] pxf     = flipx_c ? ~fpx : fpx;
function [3:0] tilepen(input [2:0] tx, input [31:0] d);
    reg [1:0] bs; reg [7:0] b;
    begin
        case(tx) 3'd0,3'd1: bs=2'd1; 3'd2,3'd3: bs=2'd0; 3'd4,3'd5: bs=2'd3; default: bs=2'd2; endcase
        b = d[{bs,3'b000}+:8];
        tilepen = tx[0] ? b[3:0] : b[7:4];
    end
endfunction
wire [3:0] pen = tilepen(pxf, romdata_c);
wire signed [11:0] outpx_s = $signed({3'b0,wtile,3'b0}) - $signed({9'b0,subc}) + $signed({9'b0,fpx});
wire [8:0] outpx  = outpx_s[8:0];
wire       outpx_ok = (outpx_s>=0) && (outpx_s<384);

// ⭐ SIM FIEL (ses.33): rom_cs debe MANTENERSE hasta rom_ok, no pulsar 1 ciclo. El pulso de 1 ciclo
// (pf_st==P_ROM2) funcionaba con el stub de scr_ok=1 INSTANTANEO, pero con la latencia SDRAM real el
// slot no completa y P_ROM3 espera rom_ok para SIEMPRE -> el fetch de tile se DEADLOCKEA (banco2 READ=1).
// Sospecha: es la causa (o parte) del tilemap baja-res de placa (ses.20). Mantener cs durante P_ROM2+P_ROM3.
assign rom_cs = (pf_st==P_ROM2) || (pf_st==P_ROM3);
always @(posedge clk, posedge rst) begin
    if(rst) begin
        pf_st<=P_IDLE; cs_st<=C_IDLE; flyr<=0; ftile<=0; fpx<=0; dispbank<=0; fbank<=1;
        rom_addr<=0; rom_lyr<=0; vid_addr<=0; prev_lhbl<=1; fline<=0; hs_valid<=0;
        wlyr<=0; wtile<=0;
    end else begin
        prev_lhbl <= lhbl;
        // ---- arranque de linea: en el flanco de bajada de LHBL, SOLO si el fetch anterior ya COMPLETO
        //      (ambas etapas idle y handoff vacio). Mostrar lo preparado y arrancar la siguiente. ----
        if( prev_lhbl && !lhbl && pf_st==P_IDLE && cs_st==C_IDLE && !hs_valid ) begin
            dispbank<=fbank;            // mostrar la línea recién preparada (flip en límite de línea)
            fbank<=~fbank;
            flyr<=0; ftile<=0;
            // El buffer preparado aquí se muestra 2 líneas después -> fline = vrender1 (2 adelante).
            // vrender1 = vrender+1 CON el wrap del vtimer (en VCNT_END va a V_START). Ver HANDOFF §5.
            fline<=vrender1;
            pf_st<=P_SETUP;
        end
        // ---- PRODUCTOR: recorre (flyr,ftile), deja el tile en el handoff ----
        case(pf_st)
        P_IDLE:  ;                                               // espera arranque de linea (arriba)
        P_SETUP: begin vid_addr<=attr_addr; pf_st<=P_ATTR; end   // flyr/ftile estables -> addr válida
        P_ATTR:  pf_st<=P_ATTR2;                                 // latencia BRAM
        P_ATTR2: begin attr_p<=vram_qvid; vid_addr<=code_addr; pf_st<=P_CODE; end
        P_CODE:  pf_st<=P_CODE2;                                 // latencia BRAM
        P_CODE2: begin code_p<=vram_qvid; pf_st<=P_ROM; end
        P_ROM:   begin rom_addr<={code_p[15:0],3'b0}+{16'b0,tyf}; rom_lyr<=flyr; pf_st<=P_ROM2; end
        P_ROM2:  pf_st<=P_ROM3;                                  // latencia ROM (settle) + rom_cs
        P_ROM3:  if(rom_ok) begin romdata_p<=rom_data; pf_st<=P_DEP; end   // esperar ROM ok
        P_DEP:   if(!hs_valid) begin                             // depositar cuando el consumidor libere
                     h_attr<=attr_p; h_rom<=romdata_p; h_tile<=ftile; h_lyr<=flyr; h_sub<=first_sub;
                     hs_valid<=1'b1;
                     if(ftile==6'd48) begin
                         ftile<=0;
                         if(flyr==2'd3) pf_st<=P_IDLE;           // fetch completo (todas las capas)
                         else begin flyr<=flyr+2'd1; pf_st<=P_SETUP; end
                     end else begin ftile<=ftile+6'd1; pf_st<=P_SETUP; end
                 end
        default: pf_st<=P_IDLE;
        endcase
        // ---- CONSUMIDOR: latchea el handoff y escribe 8 px al line buffer (1 px/clk) ----
        case(cs_st)
        C_IDLE: if(hs_valid) begin
                    attr_c<=h_attr; romdata_c<=h_rom; wtile<=h_tile; wlyr<=h_lyr; subc<=h_sub;
                    fpx<=0; hs_valid<=1'b0; cs_st<=C_WRITE;      // libera el handoff para el productor
                end
        C_WRITE: begin
                    // la escritura la hacen las instancias jtframe_rpwp_ram (via lb_we, abajo):
                    // lb_we=(cs_st==C_WRITE)&&outpx_ok, wr_addr={fbank,outpx}, din={colnib_c,pen}, sel wlyr.
                    if(fpx==3'd7) cs_st<=C_IDLE;
                    else fpx<=fpx+3'd1;
                 end
        endcase
    end
end

// ---------------- line buffers en BRAM (4x jtframe_rpwp_ram, lectura registrada) ----------------
// Escritura: en C_WRITE, a la capa `wlyr`, dir {fbank,outpx}, dato {colnib_c,pen}.
wire [9:0] lb_wa = {fbank, outpx};
// ⭐ BIT DE MEZCLA POR TILE (sesion 24) — el hallazgo que resuelve el bug del CRATER.
// El campo de color del tile son 6 bits: colpre = attr[7:2]. MAME (moo.cpp:290 tile_callback) usa
// SOLO colpre[5:2] como color y **DESCARTA colpre[1:0]**. Medido: colpre[0] (= attr[2]) es el flag
// "este tile se mezcla" del K054338:
//    attr[2]=0 -> tile OPACO, el blender NO le aplica
//    attr[2]=1 -> tile MEZCLADO al nivel alpha_lv
// Con alpha_lv=0 eso da las dos conductas que parecian contradictorias, con UNA regla:
//    * crater del attract (1200/1350): 94% de sus px con attr[2]=0 -> OPACO -> SE VE (MAME lo perdia)
//    * cortina de transicion (1030/1100): 100% con attr[2]=1, un unico tile 0xF4 -> INVISIBLE (correcto)
// Por eso los registros del K054338/K053251 son BIT-IDENTICOS entre ambas escenas: la informacion
// nunca estuvo en los registros, esta POR TILE. MAME no podia hallarlo mirando registros.
// Coste: line buffers 8->9 bits. El M10K de Cyclone V tiene modo x9 nativo -> mismo nº de BRAMs.
wire [8:0] lb_wd = {attr_c[2], colnib_c, pen};
wire       lb_we = (cs_st==C_WRITE) && outpx_ok;
// Lectura: banco de display + columna. dpx=hdump cambia solo en pxl_cen -> dout registrado estable.
wire [8:0] dpx = hdump;            // HCNT_START=0 -> activo empieza en 0
wire [9:0] rdaddr = {dispbank, dpx};
wire [8:0] lb0_q, lb1_q, lb2_q, lb3_q;

jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf0(
    .clk(clk), .rd_addr(rdaddr), .dout(lb0_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd0) );
jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf1(
    .clk(clk), .rd_addr(rdaddr), .dout(lb1_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd1) );
jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf2(
    .clk(clk), .rd_addr(rdaddr), .dout(lb2_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd2) );
jtframe_rpwp_ram #(.DW(9),.AW(10)) u_lbuf3(
    .clk(clk), .rd_addr(rdaddr), .dout(lb3_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd3) );

assign lyrf_pxl = gfx_en[0] ? lb0_q[7:0] : 8'd0;
assign lyra_pxl = gfx_en[1] ? lb1_q[7:0] : 8'd0;
assign lyrb_pxl = gfx_en[2] ? lb2_q[7:0] : 8'd0;
assign lyrc_pxl = gfx_en[3] ? lb3_q[7:0] : 8'd0;
// flag de mezcla por pixel de cada capa de scroll (el FIX no se mezcla: va siempre opaco encima)
assign lyra_mix = gfx_en[1] & lb1_q[8];
assign lyrb_mix = gfx_en[2] & lb2_q[8];
assign lyrc_mix = gfx_en[3] & lb3_q[8];

endmodule
