/*  This file is part of JTCORES (fork COWBOYS). GPLv3. Crédito Jose Tejada / JTFRAME.

    jtasterix_k056832 — tilemap Konami K056832 (Moo Mesa). Reemplaza jt052109/jt051962 de X-Men.
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
module jtasterix_k056832(
    input             rst,
    input             clk,
    input             pxl_cen,

    output            lhbl, lvbl, hs, vs,
    output     [ 8:0] hdump, vdump, vrender, vrender1,

    // CPU (68000, bus 16b)
    input             vram_cs,     // ventana 0x1a0000
    input      [ 1:0] cpu_dsn,     // UDSn/LDSn: la VRAM necesita byte-enables reales
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

    input             tilebank,     // control2 bit5 (m_cur_tile_bank): get_lookup |= tilebank<<4
    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

localparam signed [9:0] VX0 = 10'sd40;   // visarea X0
// layer_offs X ASTERIX = {-7,-5,-3,-1} (golden LAYER_OFFS_X_NORMAL; scrollX = dx - offx).
// (moomesa/cowboys era {-1,3,5,7}.) Con flip de pantalla (k56[0]&0x10) restar 177 extra -> B1d pendiente.
function signed [9:0] offx(input [1:0] l);
    case(l) 2'd0: offx=-10'sd7; 2'd1: offx=-10'sd5; 2'd2: offx=-10'sd3; default: offx=-10'sd1; endcase
endfunction

// ---------------- vtimer ASTERIX (288x224, 59.64Hz) ----------------
// ⭐ SESION 23: hasta aqui el vtimer era LITERALMENTE el de MOO MESA (HTOTAL=512, VTOTAL=264, activo
//    384 px). Moo lo tiene bien porque su pxl_cen son 8 MHz (K053252=32M/4): 8M/512/264 = 59.19 Hz.
//    ASTERIX tiene 6 MHz (24M/4) => con esos MISMOS numeros salia 6M/512/264 = 44.39 Hz y 11.72 kHz de
//    HSync: 25% LENTO y fuera de norma de TV. Verdad-terreno (asterix.cpp:402):
//      screen.set_raw(24_MHz_XTAL/4, 384, 0+16, 320-16, 262, 16, 240);  // "not 264"
//    => HTOTAL=384, VTOTAL=262, visible 288x224 -> 6M/384/262 = 59.64 Hz, 6M/384 = 15.625 kHz. ✔
//    ⚠ COMO SE MIDIO (el sim NO lo grita): `jtsim -d SIMULATION_VTIMER` imprime H total / vdump total
//    por frame, y jtframe deja el refresco medido en el fichero `framerate` de la carpeta ver/. OJO:
//    ese numero sale a MITAD del real en esta familia de vtimer (cowboys/empirecity marcan 29.59 con
//    59.19 reales), asi que hay que DOBLARLO antes de comparar; los que valen tal cual son H total y
//    vdump total.
// H: activo 3..290 = 288 px (visarea real), HTOTAL 384 (HCNT_END=0x17F). Blanking 291..383 = 96 px,
//    repartido a norma TV: front porch 9 (291..299), HS 300..327 (28 px = 4.7us @6MHz), back porch
//    328..383 + 0..2 = 59 px. El activo SIGUE empezando en H=3 (ver +3 abajo) => el pixel-exacto de
//    Fase 2 no se toca; lo que desaparece son las 96 columnas de mas que el core pintaba y la placa
//    real manda a blanking (por eso los frames del full-core salian 384 de ancho en vez de 288).
//    El fetch de los line buffers sigue cabiendo: 196 lecturas * ~9 clk = 1764 clk << 384*8 = 3072.
// V (KONAMI): vdump 0xFA..0x1FF (262 lineas), visible 0x110..0x1EF (224). Se recorta por ARRIBA
//    (V_START 0xF8->0xFA) para NO mover el origen 0x110: el obj (jt053246_scan) HARDCODEA ese rango
//    (scan si vdump>0x10D) y la matematica de Y del sprite (voffset) esta calibrada a el.
jtframe_vtimer #(
    .HCNT_START(9'h000), .HCNT_END(9'h17F),   // HTOTAL 512->384 (asterix.cpp:402)
    // ⭐ SESION 16: ventana activa DESPLAZADA +3 px para compensar la LATENCIA DEL PIPELINE del colmix
    // (K053251: paleta registrada -> {r8,g8,b8} -> bgr = ~3 clk). El RGB compuesto (tiles Y sprites, que
    // pasan ambos por colmix -> retardo UNIFORME) sale 3 px tarde; sin compensar, jtframe muestrea desde
    // H=0 y los 3 primeros px activos son basura pre-activo (COLUMNA NEGRA a la izq + todo corrido 3 px a
    // la derecha vs MAME — visible al comparar sim_snaps/mame_snaps). Al mover LHBL/HS +3, el muestreo
    // empieza en H=3, donde el RGB ya es content[0] -> alinea las dos capas de golpe SIN tocar el fetch.
    // Era el dx=3 / shift L=3 que rgbdiff barria y el HANDOFF tenia anotado como calibracion de timing HW.
    //   HB_START 0x182(386)->0x122(290): activo 3..290 = 288 px exactos = visarea real (antes 384).
    //   HB_END   0x002(2)               : LHBL sube en H=3. Blanking 291..383,0,1,2 (wrap ok).
    //   HS_START 0x193(403)->0x12C(300) : el 403 ya no existe con HTOTAL=384; 300 = front porch de 9 px.
    .HB_START(9'h122), .HB_END(9'h002), .HS_START(9'h12C),
    .V_START(9'h0FA), .VB_START(9'h1EF), .VB_END(9'h10F),
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
`ifdef SIMULATION
// SONDA: los rotulos de la pantalla de test del POST salen BASURA mientras que GOOD/BAD (codigos
// 0x4012/11/14, bits 11:10 = banco 0) salen PERFECTOS. Los rotulos usan codigos con bits 11:10 = 1 y 3,
// o sea OTRA entrada del lookup de banco de tiles -> mirar que se escribe en mmr[0x1c] (y en el resto).
integer n_reg=0;
always @(posedge clk) if(reg_cs & cpu_we && n_reg<150) begin
    n_reg <= n_reg+1;
    $display("K56832-REG[%02x] <= %04x", reg_idx, cpu_dout);
end
// SONDA B (sin tope): solo el reg 0x1c (tilebanks lookup), con vrender para ver el timing respecto
// al render (MAME lo recalcula 1 vez por frame en screen_update; aqui se lee en vivo).
always @(posedge clk) if(reg_cs & cpu_we && reg_idx==5'h1c)
    $display("K56832-REG1C <= %04x  vrender=%0d", cpu_dout, vrender);
// SONDA C: flancos de `tilebank` (control2 bit5 -> cur_tile_bank), mismo criterio de timing.
reg tilebank_l=0;
always @(posedge clk) begin
    tilebank_l <= tilebank;
    if(tilebank !== tilebank_l) $display("K56832-TILEBANK <= %b  vrender=%0d", tilebank, vrender);
end
// SONDA D (v2): la v1 filtraba code_p[11:10]!=0 asumiendo que los rotulos rotos usaban banco no-0
// (comentario original, nunca verificado) -> el fix de tilebank NO cambio NI UN PIXEL (diff exacto
// contra el frame previo), asi que esa asuncion es SOSPECHOSA. Aqui se vuelca TODO el FIX (flyr==2,
// code_p!=0) SIN filtrar por banco, en una ventana de pocos frames ya con la pantalla asentada
// (frame_cnt local, contado por flancos de `vs`), para ver los codigos/bancos REALES de esas tiles.
reg [15:0] frame_cnt=0;
reg vs_l=0;
always @(posedge clk) begin
    vs_l <= vs;
    if(vs && !vs_l) frame_cnt <= frame_cnt + 1'b1;
end
always @(posedge clk) if(pf_st==P_ROM3 && rom_ok && flyr==2'd2 && code_p!=16'd0
                          && frame_cnt>=16'd456 && frame_cnt<=16'd457)
    $display("K56832-FIXDUMP frame=%0d ftile=%0d fline=%0d code=%04x bank=%0d get_lookup=%0d ptcode=%04x rom_addr=%05x rom_data=%08x",
              frame_cnt, ftile, fline, code_p, code_p[11:10], get_lookup, ptcode, rom_addr, rom_data);
// SONDA E: lado CONSUMIDOR (escritura al line buffer) para el FIX (wlyr==2), misma ventana de frame.
// Productor confirmado sano (SONDA D: banco 0, rom_data con pinta de fuente real) -> mirar si la
// escritura outpx/lb_we aterriza donde toca o si se pierde (!outpx_ok) dejando pixel viejo (fantasma).
always @(posedge clk) if(cs_st==C_WRITE && wlyr==2'd2 && wtile>=6'd4 && wtile<=6'd20
                          && frame_cnt>=16'd456 && frame_cnt<=16'd457)
    $display("K56832-FIXWR frame=%0d fbank=%0d wtile=%0d fpx=%0d subc=%0d outpx_s=%0d outpx=%0d ok=%b pen=%0d colnib=%0d",
              frame_cnt, fbank, wtile, fpx, subc, outpx_s, outpx, outpx_ok, pen, colnib_c);
`endif
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
// VENTANA DE VRAM DEL 68k — asterix usa `ram_half_word_r/w`, NO `ram_word_r/w` (moomesa/cowboys):
//   asterix.cpp:313  map(0x400000,0x400fff) -> ram_half_word_{r,w}
//   k056832.cpp:1020 idx = m_selected_page_x4096 + (((offset<<1) & 0xffe) | 1)
// La ventana es de 4 KB (0x800 words) y se proyecta SOLO sobre las words IMPARES de la pagina de
// 4096 words: en asterix el tile entero va en la word CODE (impar) y la word ATTR (par) no se usa
// (ver tile_callback mas abajo). offset = A[11:1] -> idx = {A[11:1], 1}.
// ⚠ Con la formula de moomesa ({cpu_bank, cpu_addr[12:1]}) el 68k escribia en las words PARES y en
// la mitad baja de la pagina: la VRAM del full-core quedaba desplazada respecto a lo que lee el
// render (code_addr = tidx|1). El vfull NO cubria esto (inyecta la VRAM del oracle a pelo).
wire [15:0] cpu_vaddr = {cpu_bank, cpu_addr[11:1], 1'b1};
wire [ 1:0] vram_we   = {2{vram_cs & cpu_we}} & ~cpu_dsn;
// ⚠ BYTE ENABLES OBLIGATORIOS -> jtframe_dual_ram16 (we0[1:0]), no jtframe_dual_ram (we0 de 1 bit).
// Con un unico `we` una escritura de BYTE del 68k metia la palabra ENTERA y pisaba el otro lane.
// MEDIDO: la pantalla de resultados del POST marcaba BAD justo en "11G" (una de las SRAM de VRAM de
// tilemap, LH5168D) mientras "10G"/"7F"/"8F" salian OK = fallaba UN lane de UN par. El vfull no lo
// veia porque el tb inyecta la VRAM siempre con palabras completas (dsn=0).
jtframe_dual_ram16 #(.AW(16)) u_vram(
    .clk0(clk), .data0(cpu_dout), .addr0(cpu_vaddr), .we0(vram_we), .q0(vram_qcpu),
    .clk1(clk), .data1(16'd0),    .addr1(vid_addr),  .we1(2'b0),            .q1(vram_qvid)
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
           P_ROM=6, P_ROM2=7, P_ROM3=8, P_DEP=9,
           P_RS1=10, P_RS2=11, P_RS3=12;   // B1c: lectura de la tabla de rowscroll (1 vez por capa/linea)
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
// ⭐ SESION 34: residuo tx{6,7} (HANDOFF ses.33) — confirmado con PEINEPROBE real (tag=3000,
// col.70/71 dentro de "POWER"): el indice ya corregido (tx0_true=fpx-2) hace que fpx=0,1 lean
// tx=6,7 pero SIGUEN tirando de romdata_c/attr_c de la tesela ACTUAL (wtile), cuando esos 2
// primeros ciclos de cada tesela en realidad pertenecen (por el mismo retraso de 2 ciclos) a la
// COLA de la tesela ANTERIOR (wtile-1) -- confirmado: golden pide curcol=11 (code=174) en X=70
// pero el RTL ya ha saltado a curcol=12 (code=175). Se guarda la tesela SALIENTE justo antes de
// pisarla en el handoff, y fpx<2 usa esa copia (datos Y flipx/color, que tambien son por-tesela).
reg [31:0] prevdata_c;   // romdata_c de la tesela ANTERIOR (para fpx=0,1)
reg [15:0] prevattr_c;   // attr_c   de la tesela ANTERIOR (para fpx=0,1)

// Handoff 1-deep productor->consumidor
reg        hs_valid;
reg [15:0] h_attr;
reg [31:0] h_rom;
reg [5:0]  h_tile;
reg [1:0]  h_lyr;
reg [2:0]  h_sub;
`ifdef PEINEPROBE
// SONDA PEINE (ses.32 cont.11): diagnostico puro, sin efecto en produccion. Lleva por el handoff
// la direccion REAL (curcol/frow/fty/code_addr/rom_addr) del tile que produjo h_rom/romdata_c, para
// poder comparar el dato CRUDO contra tiles_region.bin/VRAM en el pixel "peine" conocido sin
// confundirla con el estado del productor (que ya ha avanzado a otro tile cuando el consumidor escribe).
reg [5:0]  h_dbg_curcol, dbg_curcol;
reg [4:0]  h_dbg_frow,   dbg_frow;
reg [2:0]  h_dbg_fty,    dbg_fty;
reg [15:0] h_dbg_codeaddr, dbg_codeaddr;
reg [18:0] h_dbg_romaddr,  dbg_romaddr;
`endif

// Direcciones PRODUCTOR (combinacional desde flyr, ftile, fline estables)
// ⭐ ASTERIX: origen X del visarea = VX0=16 (golden asterix, 288 ancho). El clon cowboys tenía 40
// (visarea 384). Con offx=golden(-7,-5,-3,-1) y VX0=16 el tilemap alinea con el golden a L≈0 (antes,
// con 40, la alineación real caía en L=24 fuera del rango de rgbdiff -> falso mínimo somero en L=8).
// ---------------- B1c: ROWSCROLL / LINESCROLL (scrollmode 0 y 2) ----------------
// golden rowscroll_dx(): scrollmode = (k56[5]>>(L*2))&3 ; 0=linescroll(1px) 2=rowscroll(8px);
// 1 y 3 = scroll CONSTANTE (dxL). La tabla vive en la VRAM, en la pagina
//   scrollbank = ((k56[0x18]>>1)&0xc) | (k56[0x18]&3)   [= {r18[4],r18[3],r18[1],r18[0]}]
// con offset de capa L<<10; cada entrada son 2 words (32b big-endian).
//   sm==2: sdat_start=(dy&~7)<<1, line_starty=-(dy&7), lh=8, adv=16
//   sm==0: sdat_start=dy<<1,      line_starty=0,       lh=1, adv=2
//   k = (sy-line_starty)/lh ; so = (sdat_start + k*adv) & 0x3ff ; dxv = {vram[pbase+so],vram[+so+1]}
// SIMPLIFICACIONES (equivalentes, no atajos):
//  * baseX es mod 512 (colspan=1) y 512 divide 65536 => la word ALTA no afecta: basta vram[pbase+so+1].
//  * `so` es PAR en ambos modos (sm2 acaba en 4'b0, sm0 en 1'b0) => so+1 = {so[9:1],1'b1}.
//  * sy debe ser el del golden (VY0+py = 16+py), NO el fline crudo (0x110+py): difieren en 256 y el
//    &0x3ff no lo absorbe (k*adv se desplazaria 512). Por eso sy = fline[7:0].
// El valor es CONSTANTE para toda la linea de una capa => 1 sola lectura extra por capa y linea
// (estados P_RS*), latcheada en rs_dx antes de recorrer los tiles.
reg  [1:0] smL;        // scrollmode de la capa en curso (productor)
reg [15:0] dyraw;      // dy crudo de la capa en curso (hacen falta dy[8:3] y dy[2:0])
always @* case(flyr)
    2'd0: begin smL = mmr[5'h05][1:0]; dyraw = mmr[5'h10]; end
    2'd1: begin smL = mmr[5'h05][3:2]; dyraw = mmr[5'h11]; end
    2'd2: begin smL = mmr[5'h05][5:4]; dyraw = mmr[5'h12]; end
    default: begin smL = mmr[5'h05][7:6]; dyraw = mmr[5'h13]; end
endcase
wire        rowscroll = (smL==2'd0) || (smL==2'd2);
wire [15:0] r18       = mmr[5'h18];
wire [ 3:0] scrollbank= {r18[4], r18[3], r18[1], r18[0]};
wire [ 8:0] sy8  = {1'b0, fline[7:0]};                       // = VY0+py del golden
wire [ 8:0] k2   = (sy8 + {6'd0, dyraw[2:0]}) >> 3;          // sm==2: (sy+(dy&7))>>3
wire [ 5:0] idx2 = dyraw[8:3] + k2[5:0];                     //        (dy>>3) + k
wire [ 8:0] idx0 = dyraw[8:0] + sy8;                         // sm==0: dy + sy
wire [ 8:0] so_h = (smL==2'd2) ? {idx2, 3'd0} : idx0;        // so[9:1] (so[0]=0 siempre)
wire [15:0] rs_addr = {scrollbank, flyr, so_h, 1'b1};        // pbase + so + 1 (word baja)
reg  [15:0] rs_dx;                                           // scroll de la fila (latcheado por capa)

wire signed [11:0] dx_eff = rowscroll ? $signed({3'd0, rs_dx[8:0]}) : $signed(dxL(flyr));
wire signed [11:0] Xbase_s = 12'sd16 + dx_eff - $signed(offx(flyr));
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
// ASTERIX tile index (rom): tcode = (code&0x3ff) | tilebanks[(code>>10)&3].
//   tilebanks[b] = get_lookup(b)<<10 ; get_lookup(b) = ((reg1c>>(b*4))&0xf) | (cur_tile_bank<<4).
//   reg1c = mmr[0x1c] (inyectado por el tb). cur_tile_bank = control2 bit5 (señal 'tilebank' de main):
//   HOY = 0 (sin cablear) -> B4. code_p estable en P_ROM cuando se usa ptcode.
// NOTA: `tilebank` (control2 bit5) parpadea 0/1 cada ~5 lineas durante todo el frame activo (MEDIDO;
// probablemente bit-bang de la EEPROM que reescribe control2 sin tocar este bit a proposito). Se probo
// cachearlo 1 vez por frame (en `vs`, como hace el golden en screen_update) pero el diff con el golden
// dio EXACTAMENTE CERO PIXELES distinto con y sin el cache -> esta señal no es la causante de la
// corrupcion de los rotulos (era `tilepen`, mas abajo). Revertido para no dejar un cambio sin efecto
// probado; si se retoma, revisar research/mame k056832.cpp get_lookup()/screen_update.
wire        cur_tile_bank = tilebank;
reg  [ 3:0] tbk_lut;
always @* case(code_p[11:10])
    2'd0: tbk_lut = mmr[5'h1c][ 3: 0];
    2'd1: tbk_lut = mmr[5'h1c][ 7: 4];
    2'd2: tbk_lut = mmr[5'h1c][11: 8];
    2'd3: tbk_lut = mmr[5'h1c][15:12];
endcase
wire [ 4:0] get_lookup = {1'b0, tbk_lut} | {cur_tile_bank, 4'b0};   // (reg1c nib) | (cur<<4)
wire [14:0] ptcode     = {get_lookup, code_p[9:0]};                 // (get_lookup<<10) | (code&0x3ff)
// ASTERIX tile_callback: toda la info del tile va en la PALABRA CODE (word impar); la word attr (par)
// no se usa. No hay flipY en tiles (golden: ty=ty0). flipy_p=0. attr_p queda sin uso (se sigue leyendo
// por no tocar la FSM; el waiver de abajo lo silencia).
wire       flipy_p = 1'b0;
wire [2:0] tyf     = flipy_p ? ~fty : fty;
wire _unused_attr  = &{1'b0, attr_p, 1'b0};

// Pen CONSUMIDOR — attr_c ahora contiene la palabra CODE del tile (ver handoff h_attr<=code_p).
//   flipx = code[12]; colnib = {0, code[15:13]} (los 3 bits de color; el colorbase CI lo pone el K053251).
// fpx<2 (tx=6,7 tras el shift, ver ses.34 arriba) pertenece a la tesela ANTERIOR -> usa prevattr_c/
// prevdata_c (guardados en C_IDLE), NO attr_c/romdata_c (que ya son de la tesela ACTUAL).
wire       use_prev = fpx < 3'd2;
wire [15:0] attr_eff = use_prev ? prevattr_c : attr_c;
wire [31:0] rom_eff  = use_prev ? prevdata_c : romdata_c;
wire       flipx_c = attr_eff[12];
wire [3:0] colnib_c= {1'b0, attr_eff[15:13]};
// ⭐ SESION 33: causa raiz REAL del "peine" encontrada por fin (todo lo de abajo, sesion 32, quedaba
// buscandola en el sitio equivocado). Metodo: capturas de HW real de la pantalla "POWER PLAY" (fondo
// negro, texto = tilemap puro, SIN el ruido visual de sprites/arte organico que enmascaraba el patron
// en la aldea tag=900) + sonda PEINEPROBE generalizada (banda de outpx, capa 2) comparada columna a
// columna contra tools/asterix_golden_prio.py. Resultado LIMPISIMO (17/17 columnas probadas, 0
// mismatches): la posicion REAL dentro de la tesela (la que golden llama `tx`, indice de
// `_BYTE_IN_ROW`) es SIEMPRE `(fpx-2) mod 8`, NUNCA `fpx` a secas. `fpx` es el contador del
// CONSUMIDOR (0..7, avanza 1/clk durante C_WRITE) y arrastra el MISMO retraso de 2 ciclos que ya se
// conocia y compensaba en el lado de LECTURA (`dpx=hdump+2`, linea ~497) — pero esa compensacion
// NUNCA se aplico al INDICE que entra a `tilepen()`, solo a la direccion de lectura del line buffer.
// direccion/tile (`curcol`) YA estaba correcta (verificado exhaustivamente en sesion 32, PEINEPROBE
// cont.11/12/13) — por eso "arreglar" solo la tabla `bs` (cont.10/11, golden completo: PEOR; cont.12,
// solo tx{6,7}: PEOR; cont.13, solo tx{4,5}: mejora PARCIAL) nunca cerraba el bug: se estaba
// permutando la tabla de bytes con el INDICE equivocado. Con el indice corregido, la tabla de bytes
// que hace falta es EXACTAMENTE `_BYTE_IN_ROW` del golden (bs={1,1,0,0,3,3,2,2}) sin necesidad de
// ningun ajuste ad-hoc — los grupos tx{0,1} y tx{4,5} que ya salian bien por casualidad (fpx{2,3} y
// fpx{6,7} tras el shift) coinciden exactamente con las mismas 2 tablas de bytes de siempre; los
// grupos tx{2,3} y tx{6,7} (fpx{4,5} y fpx{0,1} tras el shift) son los que de verdad estaban rotos.
// Pendiente: medir con `run_vfull.sh` en las 12 escenas antes de dar esto por definitivo — ver
// HANDOFF.md para la tabla completa. NO tocar sin repetir esa medida.
wire [2:0] tx0_true = fpx - 3'd2;    // posicion REAL en la tesela (corrige el retraso de 2 ciclos)
wire [2:0] pxf       = flipx_c ? ~tx0_true : tx0_true;
function [3:0] tilepen(input [2:0] tx, input [31:0] d);
    reg [1:0] bs; reg [7:0] b;
    begin
        // Con el indice YA corregido (tx = posicion real, ver arriba), la tabla de bytes es
        // literalmente `_BYTE_IN_ROW` del golden (tools/asterix_golden_prio.py): (1,1,0,0,3,3,2,2).
        case(tx) 3'd0,3'd1: bs=2'd1; 3'd2,3'd3: bs=2'd0; 3'd4,3'd5: bs=2'd3; default: bs=2'd2; endcase
        b = d[{bs,3'b000}+:8];
        tilepen = tx[0] ? b[3:0] : b[7:4];
    end
endfunction
wire [3:0] pen = tilepen(pxf, rom_eff);
// ⭐ SESION 32 cont.13 EXPERIMENTO (PROBADO Y REFUTADO): la teoria de que faltaba un "+2" aqui para
// alinear el limite de tesela con el dpx=hdump+2 de LECTURA (linea ~477) parecia PERFECTA en un modelo
// python puro (0/288 mismatches de curcol Y tx contra tools/asterix_golden_prio.py, ver HANDOFF.md
// cont.13) pero MEDIDO con el sim real (`run_vfull.sh 900`) el diff EMPEORA de 15,3971% a 25,0481% en
// L=0, y sigue peor en TODO el rango L=-6..+2 (no es cuestion de resincronizar con un shift global).
// Leccion identica a la de cont.10: la verificacion matematica pura no captura algo del pipeline real
// (latencia ROM, handoff productor-consumidor, etc.) — NO tocar este `+2` sin nueva evidencia medida.
wire signed [11:0] outpx_s = $signed({3'b0,wtile,3'b0}) - $signed({9'b0,subc}) + $signed({9'b0,fpx});
wire [8:0] outpx  = outpx_s[8:0];
wire       outpx_ok = (outpx_s>=0) && (outpx_s<384);
`ifdef PEINEPROBE
// SONDA PEINE (ses.32 cont.11, CORREGIDA cont.13): dato CRUDO de la escritura al line buffer que
// termina en la columna de PANTALLA "peine" conocida (267, capa 0, TODAS las filas -- el rango malo
// medido por rgbdiff era ~118-144/224). OJO cont.13: el lado de LECTURA usa dpx=hdump+2 (linea 477),
// o sea la escritura que se ve en pantalla en la columna X ocurre en outpx=X+2, NO outpx=X. Las
// sondas de cont.11/12 miraban outpx=267/270/14 (columna de PANTALLA 265/268/12, la de al lado, NO
// la mala) -- de ahi la contradiccion de cont.12 Hallazgo E. Aqui se corrige a outpx=269 (=267+2)
// para validar DIRECCION/DATO en la escritura que de verdad alimenta la columna de pantalla 267.
always @(posedge clk) if(cs_st==C_WRITE && wlyr==2'd2 && outpx>=9'd56 && outpx<=9'd72)
    $display("PEINE fline=%0d outpx=%0d wtile=%0d subc=%0d fpx=%0d tx=%0d curcol=%0d frow=%0d fty=%0d code_addr=%05x rom_addr=%05x code=%04x romdata=%08x pen=%0d colnib=%0d",
              fline, outpx, wtile, subc, fpx, pxf, dbg_curcol, dbg_frow, dbg_fty, dbg_codeaddr, dbg_romaddr, attr_c, romdata_c, pen, colnib_c);
`endif

assign rom_cs = (pf_st==P_ROM2);
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
            pf_st<=P_RS1;
        end
        // ---- PRODUCTOR: recorre (flyr,ftile), deja el tile en el handoff ----
        case(pf_st)
        P_IDLE:  ;                                               // espera arranque de linea (arriba)
        // B1c: al empezar CADA capa, lee su scroll de fila (constante para toda la linea). Se lee
        // siempre (cueste 3 clk/capa: 12/linea, despreciable) y solo se USA si rowscroll.
        P_RS1:   begin vid_addr<=rs_addr; pf_st<=P_RS2; end
        P_RS2:   pf_st<=P_RS3;                                   // latencia BRAM
        P_RS3:   begin rs_dx<=vram_qvid; pf_st<=P_SETUP; end
        P_SETUP: begin vid_addr<=attr_addr; pf_st<=P_ATTR; end   // flyr/ftile estables -> addr válida
        P_ATTR:  pf_st<=P_ATTR2;                                 // latencia BRAM
        P_ATTR2: begin attr_p<=vram_qvid; vid_addr<=code_addr; pf_st<=P_CODE; end
        P_CODE:  pf_st<=P_CODE2;                                 // latencia BRAM
        P_CODE2: begin code_p<=vram_qvid; pf_st<=P_ROM; end
        P_ROM:   begin rom_addr<={ptcode,3'b0}+{16'b0,tyf}; rom_lyr<=flyr; pf_st<=P_ROM2; end
        P_ROM2:  pf_st<=P_ROM3;                                  // latencia ROM (settle) + rom_cs
        P_ROM3:  if(rom_ok) begin romdata_p<=rom_data; pf_st<=P_DEP; end   // esperar ROM ok
        P_DEP:   if(!hs_valid) begin                             // depositar cuando el consumidor libere
                     h_attr<=code_p; h_rom<=romdata_p; h_tile<=ftile; h_lyr<=flyr; h_sub<=first_sub;
`ifdef PEINEPROBE
                     h_dbg_curcol<=curcol; h_dbg_frow<=frow; h_dbg_fty<=fty;
                     h_dbg_codeaddr<=code_addr; h_dbg_romaddr<=rom_addr;
`endif
                     hs_valid<=1'b1;
                     if(ftile==6'd48) begin
                         ftile<=0;
                         if(flyr==2'd3) pf_st<=P_IDLE;           // fetch completo (todas las capas)
                         else begin flyr<=flyr+2'd1; pf_st<=P_RS1; end   // B1c: scroll de la nueva capa
                     end else begin ftile<=ftile+6'd1; pf_st<=P_SETUP; end
                 end
        default: pf_st<=P_IDLE;
        endcase
        // ---- CONSUMIDOR: latchea el handoff y escribe 8 px al line buffer (1 px/clk) ----
        case(cs_st)
        C_IDLE: if(hs_valid) begin
                    prevdata_c<=romdata_c; prevattr_c<=attr_c;   // guarda la tesela SALIENTE (ver ses.34 arriba)
                    attr_c<=h_attr; romdata_c<=h_rom; wtile<=h_tile; wlyr<=h_lyr; subc<=h_sub;
`ifdef PEINEPROBE
                    dbg_curcol<=h_dbg_curcol; dbg_frow<=h_dbg_frow; dbg_fty<=h_dbg_fty;
                    dbg_codeaddr<=h_dbg_codeaddr; dbg_romaddr<=h_dbg_romaddr;
`endif
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
wire [7:0] lb_wd = {colnib_c, pen};
wire       lb_we = (cs_st==C_WRITE) && outpx_ok;
// Lectura: banco de display + columna. dpx cambia solo en pxl_cen -> dout registrado estable.
// +2: el K053251 (jtcolmix_053251, ci0/ci2/ci4 de las 3 capas de scroll) mete 2 clks de latencia
// interna que el FIX (lyrb) SI compensa (jtframe_sh #(.L(2)) en jtasterix_colmix.v, para re-sincronizar
// con pal_addr) pero que las capas de scroll NO tenian compensados en ningun sitio: solo llevaban el
// +3 del vtimer (HB_START), que cubre paleta->r8g8b8->bgr pero NO el propio K053251. Adelantar la
// lectura 2 columnas aqui hace que, tras esos 2 clks del chip, el pixel llegue en el instante correcto
// -> mismo efecto que el jtframe_sh del FIX, aplicado en el otro extremo del camino. Medido con vfull
// SPRZERO (tag 600, escena sin sprites): antes 21,875% en L=0 / 0,0000% en L=2 -> con este +2, 0,0000%
// en L=0. El FIX no se ve afectado (dpx avanza 2 Y jtframe_sh sigue retrasando 2 -> se cancela).
wire [8:0] dpx = hdump + 9'd2;     // HCNT_START=0 -> activo empieza en 0
wire [9:0] rdaddr = {dispbank, dpx};
wire [7:0] lb0_q, lb1_q, lb2_q, lb3_q;

jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf0(
    .clk(clk), .rd_addr(rdaddr), .dout(lb0_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd0) );
jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf1(
    .clk(clk), .rd_addr(rdaddr), .dout(lb1_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd1) );
jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf2(
    .clk(clk), .rd_addr(rdaddr), .dout(lb2_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd2) );
jtframe_rpwp_ram #(.DW(8),.AW(10)) u_lbuf3(
    .clk(clk), .rd_addr(rdaddr), .dout(lb3_q), .wr_addr(lb_wa), .din(lb_wd), .we(lb_we && wlyr==2'd3) );

assign lyrf_pxl = gfx_en[0] ? lb0_q : 8'd0;
assign lyra_pxl = gfx_en[1] ? lb1_q : 8'd0;
assign lyrb_pxl = gfx_en[2] ? lb2_q : 8'd0;
assign lyrc_pxl = gfx_en[3] ? lb3_q : 8'd0;

endmodule
