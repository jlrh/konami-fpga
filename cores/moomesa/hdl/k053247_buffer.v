// ─────────────────────────────────────────────────────────────────────────────────────────────
// FORK COWBOYS del line buffer de sprites (rol del 053247). Origen: modules/jtframe/hdl/ram/jtframe_obj_buffer.v
// Clonado 2026-07-20 (ses.27). ses.30: LINE BUFFER DE **CUÁDRUPLE** BANCO para permitir **4 escrituras
// por clk** (4 px/clk) — una BRAM sola admite 1 escritura/clk; el doble banco (ses.27) llegó a 2/clk.
//
// El dibujante (`k053247_draw.v`) emite en el caso `no_zoom` 4 píxeles consecutivos por clk en las
// direcciones buf_addr+0/+1/+2/+3. CUATRO enteros consecutivos SIEMPRE cubren los 4 residuos módulo 4
// (independientemente del alineamiento) => cada uno de los 4 puertos escribe en un BANCO DISTINTO
// (banco = addr[1:0]) => 4 escrituras simultáneas sin colisión. Es la misma idea que el doble banco
// (2 consecutivos cubren ambas paridades), extendida a addr[1:0].
//
// Banco de la RAM de línea: 4 (addr[1:0]), indexados por addr[AW-1:2]. Sombra: 4 bancos × 2 ping-pong = 8.
// Borrado (clave, ses.27): `rd=pxl_cen` (no continuo) y el borrado cae en la MISMA addr/banco que la
// lectura 1 clk después (rd_addr estable entre lectura y borrado) => banco de borrado = rd_addr[1:0],
// SIN desfase. Con solo el puerto A activo (zoom, 1 px/clk) el comportamiento es bit-exacto al original.
//
// ⚠️ KEEP_OLD (reverse priority) NO está soportado en el cuádruple banco (requeriría enrutar el readback
// old_a por banco); cowboys usa KEEP_OLD=0. jtframe NO se toca. Ver HANDOFF ses.30.
// ─────────────────────────────────────────────────────────────────────────────────────────────
/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 27-10-2017 */

module k053247_buffer #(parameter
    DW          = 8,
    AW          = 9,
    ALPHAW      = 4,
    ALPHA       = 32'HF,
    BLANK       = ALPHA,
    BLANK_DLY   = 2,
    FLIP_OFFSET = 0,
    SW          = 1,     // Shadow bits width (Use with SHADOW==1)
    SHADOW_PEN  = ALPHA, // Value used by only-shadow sprites. Use independently from shadow bits
    SHADOW      = 0,     // 1 enables shadows on data MSB
    KEEP_OLD    = 0
)(
    input   clk,
    input   LHBL,
    input   flip,
    // New data writes — 4 puertos (px 0..3) para 4 px/clk. Deja we2/we3/we4=0 para 1 px/clk.
    input   [DW-1:0] wr_data,        // puerto A (px 0)
    input   [AW-1:0] wr_addr,
    input   we,
    input   [DW-1:0] wr_data2,       // puerto B (px 1)
    input   [AW-1:0] wr_addr2,
    input   we2,
    input   [DW-1:0] wr_data3,       // puerto C (px 2)
    input   [AW-1:0] wr_addr3,
    input   we3,
    input   [DW-1:0] wr_data4,       // puerto D (px 3)
    input   [AW-1:0] wr_addr4,
    input   we4,
    // Old data reads (and erases)
    input   [AW-1:0] rd_addr,
    input   rd,                 // data will be erased after the rd event
    output reg [DW-1:0] rd_data
);

localparam EW = SHADOW==1 ? DW-SW : DW;
localparam IW = AW-2;          // index width within a bank (4 bancos por addr[1:0])

reg     line, last_LHBL;
reg [BLANK_DLY-1:0] dly;
wire                delete_we = dly[0];
wire [EW-1:0]       blank_data = BLANK[EW-1:0];
wire [DW-1:0]       dump_data;

`ifdef SIMULATION
initial line = 0;
`endif

always @(posedge clk) begin
    last_LHBL <= LHBL;
    if( !LHBL && last_LHBL ) line <= ~line;
end

always @(posedge clk) begin
    if( rd ) dly <= { 1'b1, {BLANK_DLY-1{1'b0}} };
    else     dly <= dly>>1;
    if( delete_we ) rd_data <= dump_data;
end

wire  [1:0]  rd_bank = rd_addr[1:0];
wire [IW-1:0] rd_idx = rd_addr[AW-1:2];

// ── Señales derivadas por puerto (empaquetadas en buses de 4) ─────────────────────────────────
wire [4*DW-1:0] praw_data = {wr_data4, wr_data3, wr_data2, wr_data };
wire [4*AW-1:0] praw_addr = {wr_addr4, wr_addr3, wr_addr2, wr_addr };
wire      [3:0] praw_we   = {we4,      we3,      we2,      we      };

wire [4*AW-1:0] af_bus;    // direccion ajustada por flip
wire [4*EW-1:0] wd_bus;    // dato de pixel (EW bits, sin bits de sombra)
wire      [3:0] nwe_bus;   // write-enable de pixel (opaco y no-solo-sombra)
wire      [3:0] shd_bus;   // shade flag por puerto
wire      [3:0] isshd_bus; // is_shadow flag por puerto
wire [4*SW-1:0] shbit_bus; // bits de sombra del dato por puerto

genvar gp;
generate
    for( gp=0; gp<4; gp=gp+1 ) begin : g_port
        wire [DW-1:0] d = praw_data[gp*DW +: DW];
        wire [AW-1:0] a = praw_addr[gp*AW +: AW];
        wire          w = praw_we[gp];
        wire [AW-1:0] af = flip ? ~a + FLIP_OFFSET[AW-1:0] : a;
        wire is_opaque = d[ALPHAW-1:0] != ALPHA[ALPHAW-1:0] && w;
        wire is_shadow = d[ALPHAW-1:0] == SHADOW_PEN[ALPHAW-1:0];
        wire shade     = d[DW-1-:SW] != 0;
        // KEEP_OLD no soportado en cuádruple banco (cowboys KEEP_OLD=0)
        wire new_we    = is_opaque & ~( (SHADOW==1) & is_shadow & shade );
        assign af_bus [gp*AW +: AW] = af;
        assign wd_bus [gp*EW +: EW] = d[EW-1:0];
        assign nwe_bus[gp]          = new_we;
        assign shd_bus[gp]          = shade;
        assign isshd_bus[gp]        = is_shadow;
        assign shbit_bus[gp*SW +: SW] = d[DW-1-:SW];
    end
endgenerate

// ── RAM de línea: 4 bancos (addr[1:0]) ────────────────────────────────────────────────────────
// port0 = escritura nueva (el pixel cuya addr[1:0] == banco). port1 = lectura+borrado (banco==rd_bank).
wire [4*EW-1:0] dump_bus;
assign dump_data[EW-1:0] = dump_bus[rd_bank*EW +: EW];

genvar gb;
generate
    for( gb=0; gb<4; gb=gb+1 ) begin : g_bank
        localparam [1:0] BK = gb[1:0];
        integer k;
        reg          we_b;
        reg [EW-1:0] wd_b;
        reg [IW-1:0] wi_b;
        always @* begin
            we_b = 1'b0; wd_b = {EW{1'b0}}; wi_b = {IW{1'b0}};
            for( k=0; k<4; k=k+1 )
                if( af_bus[k*AW +: 2] == BK ) begin  // exactamente 1 puerto por banco
                    we_b = nwe_bus[k];
                    wd_b = wd_bus[k*EW +: EW];
                    wi_b = af_bus[k*AW+2 +: IW];
                end
        end
        jtframe_dual_ram #(.AW(IW+1),.DW(EW)) u_line(
            .clk0(clk), .clk1(clk),
            .data0( wd_b ),        .addr0({ line, wi_b }),   .we0( we_b ),                        .q0(),
            .data1( blank_data ),  .addr1({~line, rd_idx }), .we1( delete_we & (rd_bank==BK) ),   .q1( dump_bus[gb*EW +: EW] )
        );
    end
endgenerate

// ── RAMs de sombra: mismo cuádruple banco, 2 ping-pong por banco (8 RAMs). Camino RMW de 1 clk. ──
generate
    if( SHADOW==1 ) begin : g_shadow
        // registro de las señales de sombra (1 clk), por puerto
        wire [4*SW-1:0] sh_din_bus;
        wire [4*AW-1:0] sh_wa_bus;
        wire      [3:0] sh_we_bus;

        genvar gs;
        for( gs=0; gs<4; gs=gs+1 ) begin : g_shreg
            reg  [SW-1:0] r_shdin;
            reg  [AW-1:0] r_shwa;
            reg           r_shwe;
            wire erase_shade = !shd_bus[gs] &  nwe_bus[gs];
            wire add_shade   =  shd_bus[gs] & praw_we[gs] & isshd_bus[gs];
            always @(posedge clk) begin
                r_shdin <= shbit_bus[gs*SW +: SW];
                r_shwa  <= af_bus[gs*AW +: AW];
                r_shwe  <= add_shade || erase_shade;
            end
            assign sh_din_bus[gs*SW +: SW] = r_shdin;
            assign sh_wa_bus [gs*AW +: AW] = r_shwa;
            assign sh_we_bus [gs]          = r_shwe;
        end

        // 4 bancos × 2 ping-pong. sh0 escribe con line=1 (lee/borra con ~line); sh1 al revés.
        wire [4*SW-1:0] shd0_bus, shd1_bus;
        genvar gsb;
        for( gsb=0; gsb<4; gsb=gsb+1 ) begin : g_shbank
            localparam [1:0] BK = gsb[1:0];
            integer k;
            reg          shwe_b;
            reg [SW-1:0] shwd_b;
            reg [IW-1:0] shwi_b;
            always @* begin
                shwe_b = 1'b0; shwd_b = {SW{1'b0}}; shwi_b = {IW{1'b0}};
                for( k=0; k<4; k=k+1 )
                    if( sh_wa_bus[k*AW +: 2] == BK ) begin
                        shwe_b = sh_we_bus[k];
                        shwd_b = sh_din_bus[k*SW +: SW];
                        shwi_b = sh_wa_bus[k*AW+2 +: IW];
                    end
            end
            jtframe_dual_ram #(.AW(IW),.DW(SW)) u_sh0(
                .clk0(clk),.clk1(clk),
                .data0( shwd_b ),      .addr0( shwi_b ), .we0(  line & shwe_b ),                        .q0(),
                .data1( {SW{1'b0}} ),  .addr1( rd_idx ), .we1( ~line & delete_we & (rd_bank==BK) ),     .q1( shd0_bus[gsb*SW +: SW] ));
            jtframe_dual_ram #(.AW(IW),.DW(SW)) u_sh1(
                .clk0(clk),.clk1(clk),
                .data0( shwd_b ),      .addr0( shwi_b ), .we0( ~line & shwe_b ),                        .q0(),
                .data1( {SW{1'b0}} ),  .addr1( rd_idx ), .we1(  line & delete_we & (rd_bank==BK) ),     .q1( shd1_bus[gsb*SW +: SW] ));
        end

        // salida de sombra: ping-pong (~line -> sh0, line -> sh1) y banco (rd_bank)
        wire [SW-1:0] shd0_sel = shd0_bus[rd_bank*SW +: SW];
        wire [SW-1:0] shd1_sel = shd1_bus[rd_bank*SW +: SW];
        assign dump_data[DW-1-:SW] = ~line ? shd0_sel : shd1_sel;
    end
endgenerate

endmodule
