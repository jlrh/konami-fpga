/* cowboys_lyro64.v — SLOT CUSTOM de LECTURA 64-bit para lyro (sprites), sesión 34.
   ⚠ GEMELO byte-idéntico de ver/cowboys/cowboys_lyro64.v (la del SIM FIEL). Mantener EN SINCRONÍA.
   Esta copia (hdl/) es la de SÍNTESIS (files.qip + sync a jtcores). Requiere JTFRAME_BA3_LEN=64.

   PROBLEMA (ses.33, diagnóstico del oráculo fiel): el corte del vagón es BUS-BANDWIDTH. Cada fila de
   tile de sprite necesita 64 bits (16 px × 4 planos) = 4 palabras de 16-bit consecutivas en la SDRAM.
   El dibujante (k053247_draw) las lee en DOS peticiones de 32-bit (F_RD0 H=0, F_RD1 H=1) => 2 comandos
   de bus por tile (2× overhead de CAS/ACTIVATE). Medido 11971@CLKDIV=6: 181.1 lecturas de sprite/línea.

   IDEA (recomendación del HANDOFF ses.34): las 2 mitades H YA son consecutivas en SDRAM
   (cowboys_obj:154 pone H en el LSB de la dirección de palabra). Un BLOCK-CACHE de LÍNEA de 64 bits
   (4 palabras) hace que la 2ª lectura (H=1) sea CACHE-HIT => 1 transacción de bus por tile en vez de 2.
   El dibujante NO se toca (sigue pidiendo 2× 32-bit); solo cambia cómo se sirve el bus.

   BYTE-EXACTO POR CONSTRUCCIÓN: sirve exactamente los mismos 32 bits que el slot stock por cada lectura
   (H=0 -> {w1,w0}=line[31:0]; H=1 -> {w3,w2}=line[63:32]) => 1800=0%, movimiento exacto. VERIFY_LYRO
   caza cualquier error de ensamblado del burst.

   REQUIERE burst-4 físico: poner BA3_LEN=64 en jtframe_sdram64 (=> BURSTLEN=64 GLOBAL, penaliza los
   reads de 32-bit de tiles: ocupan 4 ciclos de bus para 2 palabras útiles). El NET se MIDE en el oráculo.

   Reemplaza a `jtframe_rom_1slot` para el banco 3. Combina el rol del ctrl (drive sdram_rd, handle ack)
   y del cache (captura el burst, sirve dout). OKLATCH=0 (ok combinacional), como el slot lyro stock.
*/
module cowboys_lyro64 #(parameter
    SDRAMW = 22
)(
    input                rst,
    input                clk,

    input  [SDRAMW-1:0]  slot0_addr,   // {lyro_addr, 1'b0}  (dirección de PALABRA, [0]=0, [1]=H)
    output [31:0]        slot0_dout,
    input                slot0_cs,
    output               slot0_ok,

    // interfaz de banco (directa a jtframe_sdram64, banco 3)
    input                sdram_ack,
    output reg           sdram_rd,
    output reg [SDRAMW-1:0] sdram_addr,
    input                data_dst,     // ba_dst[3]  — primera palabra del burst
    input                data_rdy,     // ba_rdy[3]  — (no usado: contamos por data_dst + wc)
    input      [15:0]    data_read     // sdram_dout — 16 bits/ciclo
);

localparam [1:0] S_IDLE=0, S_ACK=1, S_DATA=2;

reg  [1:0]        st;
reg  [63:0]       line;          // {w3,w2,w1,w0}  (w0 en [15:0])
reg  [SDRAMW-3:0] tag;           // slot0_addr[SDRAMW-1:2]
reg               good;
reg               cap_run;
reg  [1:0]        wc;            // palabras capturadas tras data_dst

wire [SDRAMW-3:0] tag_req = slot0_addr[SDRAMW-1:2];
wire              hit     = good && (tag==tag_req);

assign slot0_ok   = slot0_cs & hit;
assign slot0_dout = slot0_addr[1] ? line[63:32] : line[31:0];  // [1]=H

wire   capturing  = data_dst | cap_run;

always @(posedge clk) begin
    if( rst ) begin
        st<=S_IDLE; sdram_rd<=0; sdram_addr<=0; good<=0; cap_run<=0; wc<=0; line<=0; tag<=0;
    end else begin
        // ── FSM de petición (una sola en vuelo) ──
        if( sdram_ack ) sdram_rd<=0;
        case( st )
            S_IDLE: if( slot0_cs && !hit ) begin
                        sdram_addr <= { tag_req, 2'b00 };  // base alineada a 4 palabras
                        sdram_rd   <= 1;
                        good       <= 1'b0;  // ⚠ invalidar YA: si no, hit se vuelve TRUE con la línea a
                        st         <= S_ACK; //   medio llenar (tag se latcha en data_dst) → sirve basura
                    end
            S_ACK:  if( sdram_ack ) st <= S_DATA;
            S_DATA: if( cap_run && wc==2'd3 ) st <= S_IDLE;  // 4ª palabra este ciclo
            default: st <= S_IDLE;
        endcase

        // ── captura del burst-4 (data_dst = w0, luego 3 más) ──
        if( capturing ) line <= { data_read, line[63:16] };
        if( data_dst ) begin
            cap_run <= 1; wc <= 2'd1;
            tag     <= tag_req;    // el addr está estable durante el burst (draw en F_RD0)
        end else if( cap_run ) begin
            wc <= wc + 2'd1;
            if( wc==2'd3 ) begin cap_run<=0; good<=1; end  // 4 palabras (w0..w3) en `line`
        end
    end
end

wire _unused = &{1'b0, data_rdy, 1'b0};

endmodule
