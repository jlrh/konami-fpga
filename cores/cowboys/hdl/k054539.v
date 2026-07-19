/*  k054539 — Konami 054539 (TOP) PCM Sound Chip. Implementacion PROPIA para COWBOYS / Moo Mesa.

    NO es el modulo privado `jt539` de Jotego (sponsor-gated, no clonable aqui). Escrito de cero
    contra el golden de MAME (k054539.cpp) y la RE de silicio de Furrtek
    (github.com/furrtek/SiliconRE/Konami/054539). Modelo de referencia: ver/cowboys/k054539_ref.cpp.

    ================================ ESTADO: Fase 3 ====================================
    Implementado:
      - Register file con el mapeo de bus real {A[9],A[7:0]} (se pierde A[8]) + read-back (POST).
      - FSM serial de 8 canales, un sample cada 384 `cen` (48 kHz), acumulador pos/frac.
      - Los TRES formatos que usa Moo Mesa (medido con el tap: 8bit 240 / 16bit 187 / DPCM 43):
          * 8-bit PCM  (type 0x0): 1 byte, val=byte<<8, terminador 0x80.
          * 16-bit PCM (type 0x4): 2 bytes LE, terminador 0x8000.
          * 4-bit DPCM (type 0x8): nibble + tabla de pasos, acumulacion, terminador 0x88.
      - Mezcla fixed-point Q16 con tablas voltab/pantab ($readmemh) + pan L/R (incl. rango 0x8x),
        key on/off. Salida = PCM PURO (canal propio hacia el rcmix de jtframe). La FM (jt51) es un
        CANAL SEPARADO (mem.yaml: fm + pcm) -> jtframe mezcla en precision ancha, sin comprometer
        headroom. Trim de PCM en vivo por debug_bus[7:4] (default unidad) para calibrar el balance.
    TODO (siguiente incremento):
      - reverb RAM 0x4000 (BRAM)   - reverse (no usado en moomesa: 0/470)   - latch UPDATE_AT_KEYON
        exacto (aqui: restart por flanco de keyon leyendo regs 0x0c-0e directo).

    ⭐ El READ-BACK del register file es comportamiento REAL y REQUISITO DE ARRANQUE (sesion 11):
    el POST del Z80 escribe/relee 0xE000-0xE1FF; con dout=0 el 68k cuelga en "RAM C4 BAD".
*/
module k054539 #(parameter VOLSHIFT=0) (
    input               rst,
    input               clk,
    input               cen,     // 18.432 MHz gated (pcm). 384 cen = 1 sample (48 kHz)
    output              timeout,

    // CPU interface (addr = {A[9],A[7:0]}, 9 bits; A[8] se pierde en el bus)
    input      [ 8:0]   addr,
    input               we,
    input               rd,
    input               cs,
    input      [ 7:0]   din,
    output     [ 7:0]   dout,

    // ROM (PCM samples) en SDRAM COMPARTIDO -> HAY que esperar rom_ok (el dato NO es de latencia cero:
    // bajo contencion video+cpu+sonido llega tarde -> leer sin esperar = falso terminador = sonido que falta).
    output reg          rom_cs,
    output reg [23:0]   rom_addr,
    input      [ 7:0]   rom_data,
    input               rom_ok,

    // Sound output (PCM PURO — la FM va por su propio canal en el rcmix de jtframe)
    output reg signed [15:0] left,
    output reg signed [15:0] right,

    input      [ 7:0]   debug_bus,
    output     [ 7:0]   st_dout
);

// ---------------------------------------------------------------------------
// Register file (direccionado por la addr de MODULO {A9,A7:0}).
// Mapeo offsets MAME -> modulo: canales 0x0xx igual; control 0x2xx -> 0x1xx
//   active=0x22c->0x12c  ctrl=0x22f->0x12f  keyon=0x214->0x114  keyoff=0x215->0x115
//   canal ch base1=0x20*ch (igual)   base2=0x200+2*ch -> 0x100+2*ch
// CPU es el UNICO que escribe regs[] (un solo driver). keyon/keyoff/terminador tocan `active`.
// ---------------------------------------------------------------------------
reg  [7:0] regs [0:511];
integer    gi;
initial for (gi=0; gi<512; gi=gi+1) regs[gi] = 8'd0;

always @(posedge clk) begin
    if (cs && we) regs[addr] <= din;
end

assign dout    = regs[addr];
assign timeout = 1'b0;
assign st_dout = 8'd0;

// ---------------------------------------------------------------------------
// Tablas de volumen/pan (Q16) — mismas que k054539_ref.cpp modo FIXED.
// ---------------------------------------------------------------------------
reg [15:0] voltab [0:255];   // <= 0x4000
reg [16:0] pantab [0:14];    // <= 0x10000
initial begin
    $readmemh("voltab.hex", voltab);
    $readmemh("pantab.hex", pantab);
end

// ---------------------------------------------------------------------------
// Estado por canal (autoritativo; en unidades de BYTE entre samples)
// ---------------------------------------------------------------------------
reg [23:0] cpos   [0:7];
reg [15:0] cpfrac [0:7];
reg signed [15:0] cval  [0:7];
reg signed [15:0] cpval [0:7];

reg  [7:0] active;    // canales sonando (MAME 0x22c)
reg  [7:0] restart;   // re-arranque por flanco de keyon

// ---------------------------------------------------------------------------
// Secuenciador
// ---------------------------------------------------------------------------
localparam [3:0]
    S_IDLE = 4'd0, S_LOAD = 4'd1, S_ACC = 4'd2,
    S_R8   = 4'd3, S_R16L = 4'd4, S_R16H = 4'd5, S_RD = 4'd6,
    S_MIX  = 4'd7, S_NEXT = 4'd8, S_DONE = 4'd9,
    S_REVRD= 4'd10, S_RVWR = 4'd11;   // reverb: lee feedback @revpos ; RMW del canal @widx

reg [3:0]  state;
reg [8:0]  sample_cnt;
reg [2:0]  ch;

// registros de trabajo del canal en curso
reg [24:0] w_pos;              // 25b: DPCM trabaja en unidades de NIBBLE (pos<<1)
reg [31:0] w_pfrac;
reg signed [15:0] w_val, w_pval;
reg [23:0] w_loop;
reg [7:0]  w_lo;              // byte bajo del sample 16-bit
reg [7:0]  w_vol;
reg [3:0]  w_pan;
reg [1:0]  w_type;           // 0=8bit, 1=16bit(0x4), 2=DPCM(0x8)
reg        w_loopen;

// acumuladores en Q16 (como MAME: suma en full-precision, >>16 UNA vez al final)
reg signed [39:0] accL, accR;

// ---------------------------------------------------------------------------
// Reverb — linea de retardo mono (MAME k054539.cpp). rbase = int16[0x2000] en BRAM.
// Por sample: se LEE+LIMPIA rram[reverb_pos] (feedback, se suma a L y R por igual);
// cada canal ACUMULA su muestra atenuada en rram[(rdelta+reverb_pos)&0x1fff]; luego reverb_pos++.
// Lectura REGISTRADA (sincrona) -> infiere BRAM (leccion sesion 16: async => logica).
// Init 0 via $readmemh (NO `initial for`: Quartus limita el desenrollado a 5000 iter -> Error 10106
// con 8192; Verilator/lint lo tragan -> nueva cara del C-06). rram_zero.hex = 8192x"0000".
// ---------------------------------------------------------------------------
reg  signed [15:0] rram [0:8191];
initial $readmemh("rram_zero.hex", rram);
reg  [12:0] reverb_pos;
reg  [12:0] rr_addr;             // direccion de ESCRITURA (clear @revpos / RMW @widx)
reg         rr_we;
reg  signed [15:0] rr_din;
reg  signed [15:0] rr_dout;      // lectura registrada de rram[rd_addr] (1 ciclo de latencia)
// direccion de LECTURA combinacional: en S_MIX lee @widx (para el RMW del canal en S_RVWR);
// en cualquier otro estado lee @reverb_pos (feedback, usado en S_REVRD tras emitir en S_IDLE).
wire [12:0] rd_addr = (state==S_MIX) ? widx : reverb_pos;
always @(posedge clk) begin
    rr_dout <= rram[rd_addr];
    if (rr_we) rram[rr_addr] <= rr_din;
end

// --- volumen L/R del canal en curso (Q16) ---
wire [16:0] vt   = {1'b0, voltab[w_vol]};
wire [16:0] pl   = pantab[w_pan];
wire [16:0] pr   = pantab[4'd14 - w_pan];
wire [33:0] lfull= vt * pl;
wire [33:0] rfull= vt * pr;
wire [16:0] lvol = lful_clamp(lfull[32:16]);
wire [16:0] rvol = lful_clamp(rfull[32:16]);
function [16:0] lful_clamp(input [16:0] v);
    lful_clamp = (v > 17'h1CCCC) ? 17'h1CCCC : v;   // VOL_CAP=1.8 en Q16
endfunction

// contribucion del canal en Q16 (SIN truncar): w_val * vol. Se acumula asi y se redondea al final.
wire signed [33:0] cprodL = $signed(w_val) * $signed({1'b0, lvol});
wire signed [33:0] cprodR = $signed(w_val) * $signed({1'b0, rvol});
wire signed [39:0] contribL = {{6{cprodL[33]}}, cprodL};
wire signed [39:0] contribR = {{6{cprodR[33]}}, cprodR};

// --- Reverb: parametros del canal en curso (MAME, modo FIXED) ---
//   rdelta = ({base1[7],base1[6]} >> 3);  rdelta = (rdelta+revpos)&0x3fff;
//   widx   = (rdelta + revpos) & 0x1fff;  (revpos sumado DOS veces: quirk exacto de MAME)
//   bval   = min(vol + base1[4], 255);    rbvol = (voltab[bval]*32768)>>16 = voltab[bval]>>1
//   rev_contrib = (int16)((cur_val * rbvol) >> 16)  -> se ACUMULA (int16, wrap) en rram[widx]
wire [12:0] rrd  = {regs[b1+9'd7], regs[b1+9'd6]} >> 3;          // 16b >>3 = 13b
wire [13:0] rd14 = ({1'b0,rrd} + {1'b0,reverb_pos}) & 14'h3fff;
wire [14:0] wsum = {1'b0,rd14} + {2'b0,reverb_pos};
wire [12:0] widx = wsum[12:0];                                    // &0x1fff
wire [8:0]  bsum = {1'b0,w_vol} + {1'b0, regs[b1+9'd4]};
wire [7:0]  bval = bsum[8] ? 8'd255 : bsum[7:0];                  // clamp 255
wire [15:0] rbvol = {1'b0, voltab[bval][15:1]};                   // voltab>>1 (< VOL_CAP siempre)
wire signed [32:0] rprod = $signed(w_val) * $signed({1'b0, rbvol});
wire signed [15:0] rev_contrib = rprod[31:16];                   // (>>16) truncado a int16

// direcciones base del canal
wire [8:0] b1 = {1'b0, ch, 5'b0};            // 0x20*ch
wire [8:0] b2 = 9'h100 + {5'b0, ch, 1'b0};   // 0x100 + 2*ch
wire [23:0] delta_now = {regs[b1+9'd2], regs[b1+9'd1], regs[b1+9'd0]};
wire [1:0]  type_now  = (regs[b2] & 8'h0c)==8'h00 ? 2'd0 :
                        (regs[b2] & 8'h0c)==8'h04 ? 2'd1 : 2'd2;

// tabla de pasos DPCM (x0x100)
function signed [15:0] dpcm_step(input [3:0] n);
    case (n)
        4'd0:  dpcm_step =  16'sd0;      4'd1:  dpcm_step =  16'sd256;
        4'd2:  dpcm_step =  16'sd512;    4'd3:  dpcm_step =  16'sd1024;
        4'd4:  dpcm_step =  16'sd2048;   4'd5:  dpcm_step =  16'sd4096;
        4'd6:  dpcm_step =  16'sd8192;   4'd7:  dpcm_step =  16'sd16384;
        4'd8:  dpcm_step =  16'sd0;      4'd9:  dpcm_step = -16'sd16384;
        4'd10: dpcm_step = -16'sd8192;   4'd11: dpcm_step = -16'sd4096;
        4'd12: dpcm_step = -16'sd2048;   4'd13: dpcm_step = -16'sd1024;
        4'd14: dpcm_step = -16'sd512;    4'd15: dpcm_step = -16'sd256;
    endcase
endfunction

// clamp a int16
function signed [15:0] clip16(input signed [23:0] v);
    clip16 = (v >  24'sd32767) ? 16'sd32767 :
             (v < -24'sd32768) ? -16'sd32768 : v[15:0];
endfunction
// trim de PCM en vivo: (PCM*pg) >> 3, con clamp. pg de debug_bus[7:4] (ver abajo).
function signed [15:0] trimg(input signed [15:0] pcm16, input [4:0] pg);
    trimg = clip16( (pcm16*$signed({1'b0,pg})) >>> 3 );
endfunction
function [3:0] pan_idx(input [7:0] p);
    if      (p >= 8'h81 && p <= 8'h8f) pan_idx = p[3:0] - 4'd1;
    else if (p >= 8'h11 && p <= 8'h1f) pan_idx = p[3:0] - 4'd1;
    else                               pan_idx = 4'd7;
endfunction

// nibble DPCM actual segun paridad de la posicion (unidad nibble)
wire [3:0] dnib = w_pos[0] ? rom_data[7:4] : rom_data[3:0];
wire signed [15:0] ds = dpcm_step(dnib);

// --- Trim de PCM AJUSTABLE EN VIVO por debug_bus (calibrar el balance sin recompilar) ---
//   debug_bus[7:4] = trim PCM (/8; 0 -> default 8 = UNIDAD). El balance base FM/PCM lo fija el
//   rcmix de jtframe (mem.yaml: canales fm + pcm); este trim es solo para el ajuste fino en vivo.
//   (La FM se trimea en su propio canal, en jtcowboys_sound.v con debug_bus[3:0].)
wire [4:0] pcm_g = (debug_bus[7:4]==4'd0) ? 5'd8 : {1'b0, debug_bus[7:4]};
// avance de posicion (unidades de w_pos)
wire [24:0] npos1 = w_pos + 25'd1;
wire [24:0] npos2 = w_pos + 25'd2;

integer ci;
always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE; sample_cnt <= 0; ch <= 0;
        rom_cs <= 0; rom_addr <= 0;
        left <= 0; right <= 0; accL <= 0; accR <= 0;
        active <= 0; restart <= 0;
        reverb_pos <= 0; rr_we <= 0; rr_addr <= 0; rr_din <= 0;   // reverb (rram init por `initial`)
        for (ci=0; ci<8; ci=ci+1) begin
            cpos[ci] <= 0; cpfrac[ci] <= 0; cval[ci] <= 0; cpval[ci] <= 0;
        end
    end else begin
        // key on/off desde la CPU (corre a clk, no a cen)
        if (cs && we) begin
            case (addr)
                9'h114: begin restart <= restart | (din & ~active); active <= active | din; end
                9'h115: active <= active & ~din;
                default: ;
            endcase
        end

        if (cen) begin
            sample_cnt <= (sample_cnt == 9'd383) ? 9'd0 : sample_cnt + 9'd1;
            rom_cs <= 1'b0;
            rr_we  <= 1'b0;   // por defecto sin escritura de reverb (patron rom_cs)

            case (state)
            S_IDLE: if (sample_cnt == 9'd0) begin
                        ch <= 0;
                        if (regs[9'h12f][0]) begin
                            state <= S_REVRD;   // rd_addr=reverb_pos (emitido); rr_dout listo en S_REVRD
                        end else begin
                            accL <= 0; accR <= 0; state <= S_LOAD;     // chip off: sin reverb
                        end
                    end

            // ---------- reverb: feedback @reverb_pos -> init de accL/accR, y LIMPIA el slot ----------
            S_REVRD: begin
                accL <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };   // rbase[revpos]<<16 (Q40, sext)
                accR <= { {8{rr_dout[15]}}, rr_dout, 16'b0 };
                rr_addr <= reverb_pos; rr_din <= 16'sd0; rr_we <= 1'b1;   // rram[reverb_pos] <= 0
                state <= S_LOAD;
            end

            // ---------- carga de parametros + setup del acumulador ----------
            S_LOAD: begin
                if (!active[ch] || !regs[9'h12f][0]) begin
                    state <= S_NEXT;
                end else begin
                    w_vol    <=  regs[b1+3];
                    w_loop   <= {regs[b1+9'ha], regs[b1+9'h9], regs[b1+9'h8]};
                    w_loopen <=  regs[b2+1][0];
                    w_pan    <=  pan_idx(regs[b1+5]);
                    w_type   <=  type_now;
                    // pos/frac base (unidad byte). Para DPCM se escala a nibble abajo.
                    if (type_now == 2'd2) begin
                        // DPCM: pos<<1, frac<<1, ajuste de acarreo, +=delta
                        if (restart[ch]) begin
                            w_pos   <= {regs[b1+9'he], regs[b1+9'hd], regs[b1+9'hc]} << 1;
                            w_pfrac <= {8'b0, delta_now};                 // (0<<1)=0, +delta
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin
                            // frac<<1; si bit16 -> pos|1, frac&0xffff; luego +delta
                            w_pos   <= ({cpos[ch],1'b0}) | (cpfrac[ch][15] ? 25'd1 : 25'd0);
                            w_pfrac <= {15'b0, cpfrac[ch], 1'b0} + {8'b0, delta_now}
                                       - (cpfrac[ch][15] ? 32'h0001_0000 : 32'd0);
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end else begin
                        if (restart[ch]) begin
                            w_pos   <= {1'b0, regs[b1+9'he], regs[b1+9'hd], regs[b1+9'hc]};
                            w_pfrac <= {8'b0, delta_now};
                            w_val   <= 0; w_pval <= 0;
                            restart[ch] <= 1'b0;
                        end else begin
                            w_pos   <= {1'b0, cpos[ch]};
                            w_pfrac <= {16'b0, cpfrac[ch]} + {8'b0, delta_now};
                            w_val   <= cval[ch]; w_pval <= cpval[ch];
                        end
                    end
                    state <= S_ACC;
                end
            end

            // ---------- while(cur_pfrac & ~0xffff): avanza y lee ----------
            S_ACC: begin
                if (|w_pfrac[31:16]) begin
                    w_pfrac <= w_pfrac - 32'h0001_0000;
                    case (w_type)
                    2'd0: begin // 8-bit: +1 byte
                        w_pos    <= npos1;
                        rom_addr <= npos1[23:0];
                        rom_cs   <= 1'b1; state <= S_R8;
                    end
                    2'd1: begin // 16-bit: +2 bytes (lee low y luego high)
                        w_pos    <= npos2;
                        rom_addr <= npos2[23:0];
                        rom_cs   <= 1'b1; state <= S_R16L;
                    end
                    default: begin // DPCM: +1 nibble; lee byte pos>>1
                        w_pos    <= npos1;
                        rom_addr <= npos1[24:1];
                        rom_cs   <= 1'b1; state <= S_RD;
                    end
                    endcase
                end else begin
                    state <= S_MIX;
                end
            end

            // ---------- captura 8-bit (espera rom_ok: dato del SDRAM listo) ----------
            S_R8: if (rom_ok) begin
                w_pval <= w_val;
                if (rom_data == 8'h80) begin
                    if (w_loopen) begin
                        w_pos <= {1'b0, w_loop}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_R8;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, 8'h00}); state <= S_ACC;
                end
            end

            // ---------- captura 16-bit (byte bajo, luego alto) — espera rom_ok en cada byte ----------
            S_R16L: if (rom_ok) begin
                w_lo     <= rom_data;
                rom_addr <= w_pos[23:0] + 24'd1;   // byte alto
                rom_cs   <= 1'b1; state <= S_R16H;
            end
            S_R16H: if (rom_ok) begin
                w_pval <= w_val;
                if ({rom_data, w_lo} == 16'h8000) begin
                    if (w_loopen) begin
                        w_pos <= {1'b0, w_loop}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_R16L;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_val <= $signed({rom_data, w_lo}); state <= S_ACC;
                end
            end

            // ---------- captura DPCM (espera rom_ok) ----------
            S_RD: if (rom_ok) begin
                if (rom_data == 8'h88) begin
                    if (w_loopen) begin
                        w_pos <= {w_loop, 1'b0}; rom_addr <= w_loop; rom_cs <= 1'b1; state <= S_RD;
                    end else begin
                        active[ch] <= 1'b0; w_val <= 16'sd0; state <= S_MIX;
                    end
                end else begin
                    w_pval <= w_val;
                    w_val  <= clip16( {{8{w_val[15]}}, w_val} + {{8{ds[15]}}, ds} );
                    state  <= S_ACC;
                end
            end

            // ---------- mezcla + writeback (des-escala DPCM) ----------
            S_MIX: begin
                accL <= accL + contribL;
                accR <= accR + contribR;
                if (w_type == 2'd2) begin
                    cpos[ch]   <= w_pos[24:1];                             // pos>>1
                    cpfrac[ch] <= {1'b0, w_pfrac[15:1]} | (w_pos[0] ? 16'h8000 : 16'h0);
                end else begin
                    cpos[ch]   <= w_pos[23:0];
                    cpfrac[ch] <= w_pfrac[15:0];
                end
                cval[ch]  <= w_val;
                cpval[ch] <= w_pval;
                state <= S_RVWR;        // rd_addr=widx (emitido en S_MIX); rr_dout listo en S_RVWR
            end

            // ---------- reverb RMW: rram[widx] += rev_contrib (int16, wrap) ----------
            S_RVWR: begin
                rr_addr <= widx;                   // direccion de escritura (ch aun sin incrementar)
                rr_din  <= rr_dout + rev_contrib;  // rr_dout = rram[widx] (viejo, leido via rd_addr en S_MIX)
                rr_we   <= 1'b1;                    // commit durante S_NEXT
                state   <= S_NEXT;
            end

            S_NEXT: begin
                if (ch == 3'd7) state <= S_DONE;
                else begin ch <= ch + 3'd1; state <= S_LOAD; end
            end

            S_DONE: begin  // Q16 -> entero (>>16), clamp del PCM (como MAME), y trim de PCM en vivo
                left  <= trimg( clip16($signed(accL[39:16])), pcm_g );
                right <= trimg( clip16($signed(accR[39:16])), pcm_g );
                if (regs[9'h12f][0]) reverb_pos <= reverb_pos + 13'd1;  // congela si chip OFF (ref: early return)
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
end

endmodule
