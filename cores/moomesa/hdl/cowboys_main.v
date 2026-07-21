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
    Version: 1.0
    Date: 7-7-2024

    FASE 1 (sesion 5, 2026-07-16): reescrito al mapa REAL de moomesa (moo.cpp
    moo_prot_state::moo_map). Antes heredaba el decode PAL de X-Men (mapa distinto).
    Referencias: research/moo.cpp lineas 520-587 (moo_map), 393-482 (control2/IRQ),
    663-701 (puertos). IRQ = patron simson/vendetta (jtframe_edge) mapeado a IRQ5/IRQ4.
*/

module cowboys_main(
    input                rst,
    input                clk, // 48 MHz
    input                LVBL,

    output        [20:1] main_addr,   // 21 bits de byte: la region maincpu son 0x180000 B (ver mem.yaml)
    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,
    // 8-bit interface
    output               cpu_we,
    output reg           pal_cs,
    output reg           pcu_cs,
    // Sound interface
    output               pair_we,   // K054321 (some latches)
    input         [ 7:0] pair_dout, // K054321 (X-Men)
    output               snd_wrn,   // K053260 (PCM sound)
    input         [ 7:0] snd2main,  // K053260 (PCM sound)
    output reg           sndon,     // irq trigger
    output reg           mute,

    output reg           rom_cs,
    output reg           ram_cs,
    output reg           vram_cs,
    output reg           tilereg_cs,  // K056832 regs 0x0c0000 (word_w) + 0x0d8000 (b_word_w VSCCS)
    output reg           alpha_cs,    // K054338 regs 0x0ca000
    output reg           obj_cs,

    input         [15:0] oram_dout,
    input         [15:0] vram_dout,
    input         [15:0] pal_dout,
    input         [15:0] ram_dout,
    input         [15:0] rom_data,
    input                ram_ok,
    input                rom_ok,
    input                vdtac,
    input                tile_irqn,

    // video configuration
    output reg           objreg_cs,
    output reg           objcha_n,
    output reg           rmrd,
    input                dma_bsy,
    // EEPROM
    output      [ 6:0]   nv_addr,
    input       [ 7:0]   nv_dout,
    output      [ 7:0]   nv_din,
    output               nv_we,
    // Cabinet
    input         [ 6:0] joystick1,
    input         [ 6:0] joystick2,
    input         [ 6:0] joystick3,
    input         [ 6:0] joystick4,
    input         [ 3:0] cab_1p,
    input         [ 3:0] coin,
    input         [ 3:0] service,
    input                dip_pause,
    input                dip_test,
    output        [ 7:0] st_dout,
    input         [ 7:0] debug_bus
);
`ifndef NOMAIN
wire [23:1] A;
wire        cpu_cen, cpu_cenb;
wire        UDSn, LDSn, RnW, ASn, VPAn, DTACKn;
wire [ 2:0] FC;
reg  [ 2:0] IPLn;
reg  [15:0] cpu_din;
reg  [15:0] cur_control2;   // 0x0de000 (moo.cpp control2_w)
wire        eep_rdy, eep_do, bus_cs, bus_busy, BUSn;
wire        dtac_mux, iack;
wire [15:0] cpu_dout_68k;   // dato del 68k ANTES del mux del blitter (ver moo_prot, Fase 4)

// --- bus efectivo: el blitter moo_prot es BUS MASTER y suplanta al 68k mientras opera ---
wire [23:1] blt_addr;
wire [15:0] blt_dout;
wire        blt_busy, blt_we, blt_stb, blt_stall;
wire [23:1] eff_addr = blt_busy ? blt_addr :  A;
wire        eff_asn  = blt_busy ? ~blt_stb : ASn;
wire        eff_busn = blt_busy ? ~blt_stb : BUSn;
wire        eff_we   = blt_busy ?  blt_we  : ~RnW;
wire [ 1:0] eff_dsn  = blt_busy ? 2'b00    : {UDSn,LDSn};

// I/O sub-selects (0x0c0000-0x0dffff region)
reg  io_cs, tilereg_b_cs, ccu_cs, sndirq_cs, pair_cs, romrd_cs,
     in0_cs, in1_cs, p1p3_cs, p2p4_cs, control2_cs, prot_cs;
reg  [15:0] port_in;

`ifdef SIMULATION
wire [23:0] A_full = {A,1'b0};
`endif
/* verilator tracing_off */
assign main_addr= eff_addr[20:1];
assign ram_dsn  = eff_dsn;
// El generador de DTACK solo debe ver los accesos DEL 68k: los del blitter se le ocultan
// (~blt_busy), o su recovery contaria ciclos de bus que la CPU no ha pedido.
assign bus_cs   = (rom_cs | ram_cs) & ~blt_busy;
assign bus_busy = ((rom_cs & ~rom_ok) | (ram_cs & ~ram_ok)) & ~blt_busy;
assign BUSn     = ASn | (LDSn & UDSn);
assign cpu_we   = eff_we;
assign cpu_dout = blt_busy ? blt_dout : cpu_dout_68k;
assign st_dout  = { rmrd, cur_control2[11], cur_control2[5], objcha_n, 4'd0 };
// 6800-style autovector during interrupt acknowledge (FC==7 CPU space)
assign VPAn     = ~(&FC & ~ASn);
assign iack     =  &FC & ~ASn;
// blt_stall estanca al 68k DENTRO del propio ciclo de escritura del trigger (0x0ce018): la CPU
// no completa el ciclo hasta que el blitter termina, igual que el chip real (que retiene el bus).
assign dtac_mux = DTACKn | ~vdtac | blt_stall;
// K054321 sound latch write (0x0d6000): LDS byte access
assign pair_we  = pair_cs & ~RnW & ~LDSn;
// K053260/PCM read strobe (unused path in moomesa reuse; keep inactive)
assign snd_wrn  = ~(sndirq_cs & ~RnW);

// ---------------- moomesa address decode (moo_prot_state::moo_map) ----------------
// A is the 68k WORD address [23:1]; byte address = {A,1'b0}.
//   0x000000-0x07ffff ROM        | 0x0c0000-0x0dffff I/O (subdecoded by A[16:13])
//   0x100000-0x17ffff ROM        | 0x180000-0x18ffff work RAM | 0x190000-0x19ffff spr RAM
//   0x1a0000-0x1a1fff VRAM (mirror 0x2000) | 0x1b0000-0x1b1fff tile ROM read | 0x1c0000-0x1c1fff palette
`ifdef SIMULATION
reg none_cs;
`endif
always @* begin
    rom_cs      = 0; ram_cs   = 0; obj_cs   = 0; vram_cs  = 0; pal_cs  = 0;
    tilereg_cs  = 0; tilereg_b_cs = 0; alpha_cs = 0; pcu_cs = 0; objreg_cs = 0;
    prot_cs     = 0; ccu_cs   = 0; sndirq_cs= 0; pair_cs  = 0; romrd_cs = 0;
    in0_cs      = 0; in1_cs   = 0; p1p3_cs  = 0; p2p4_cs  = 0; control2_cs = 0;
    io_cs       = 0;
    // OJO: el decode va sobre eff_addr/eff_asn/eff_busn (bus EFECTIVO), no sobre A/ASn/BUSn: durante
    // el blitter el 68k esta estancado con su A clavada en 0x0ce018 y sus strobes BAJOS.
    if( !eff_asn ) begin
        rom_cs  = (eff_addr[23:19]==5'b00000) | (eff_addr[23:19]==5'b00010); // 0x000000-7ffff | 0x100000-17ffff
        ram_cs  = (eff_addr[23:16]==8'h18) & ~eff_busn;          // 0x180000-18ffff work RAM
        obj_cs  = (eff_addr[23:16]==8'h19);                      // 0x190000-19ffff sprite RAM
        vram_cs = (eff_addr[23:14]==10'b00_0110_1000);          // 0x1a0000-1a3fff K056832 VRAM (mirror)
        romrd_cs= (eff_addr[23:13]==11'b000_1101_1000);         // 0x1b0000-1b1fff tile ROM passthrough
        pal_cs  = (eff_addr[23:13]==11'b000_1110_0000);         // 0x1c0000-1c1fff palette
        io_cs   = (eff_addr[23:17]==7'b0000_110);               // 0x0c0000-0x0dffff peripheral block
        if( io_cs ) case( eff_addr[16:13] )
            4'h0: tilereg_cs   = 1; // 0x0c0000 K056832 word_w
            4'h1: objreg_cs    = 1; // 0x0c2000 K053246 w
            4'h2: objreg_cs    = 1; // 0x0c4000 K053246 r  (status: dma_bsy/objcha)
            4'h5: alpha_cs     = 1; // 0x0ca000 K054338 (alpha)
            4'h6: pcu_cs       = 1; // 0x0cc000 K053251 (priority)
            4'h7: prot_cs      = 1; // 0x0ce000 moo_prot (blitter, Fase 4)
            4'h8: ccu_cs       = 1; // 0x0d0000 K053252 CCU (ignored)
            4'ha: sndirq_cs    = 1; // 0x0d4000 sound_irq_w
            4'hb: pair_cs      = 1; // 0x0d6000 K054321 (sound latch)
            4'hc: tilereg_b_cs = 1; // 0x0d8000 K056832 b_word_w (VSCCS)
            4'hd: begin p1p3_cs = ~eff_addr[1]; p2p4_cs = eff_addr[1]; end // 0x0da000/2 P1_P3 / P2_P4
            4'he: begin in0_cs  = ~eff_addr[1]; in1_cs  = eff_addr[1]; end // 0x0dc000/2 IN0 / IN1
            4'hf: control2_cs  = 1; // 0x0de000 control2
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~eff_busn & ~|{ rom_cs, ram_cs, obj_cs, vram_cs, pal_cs, romrd_cs,
        tilereg_cs, tilereg_b_cs, alpha_cs, pcu_cs, objreg_cs, prot_cs, ccu_cs,
        sndirq_cs, pair_cs, in0_cs, in1_cs, p1p3_cs, p2p4_cs, control2_cs };
`endif
end
// K056832 regs: word_w (0x0c0000) and b_word_w (VSCCS 0x0d8000) both go to the tile system reg port.
// tilereg_cs (above) already carries 0x0c0000; the video reg decoder must also accept VSCCS if needed.

// ---------------- input ports ----------------
// ⚠ POLARIDAD (GOTCHAS §A3) — los bits de cabina Konami son ACTIVO-BAJO, y jtframe YA los entrega en
// ACTIVO-BAJO: van **DIRECTOS, SIN INVERTIR**. Evidencia (no suposicion):
//   · `jtframe_dip.v:87` -> `assign dip_test = ~status[10] & game_test; // assumes it is always active low`
//   · `jtframe_inputs.v:184` -> el puerto interno se llama **`coin_n`** (_n = activo bajo)
//   · el core hermano simson los usa CRUDOS: `port_in <= { dipsw[23:20], coin[1:0], dip_test, service }`
// El `~` que habia aqui dejaba IN1 bit3 (PORT_SERVICE_NO_TOGGLE, moo.cpp:677, ACTIVE_LOW) clavado a 0
// = **SERVICIO ACTIVO** -> el juego arrancaba en **MODO TEST** (por eso el POST hacia el test de 64KB
// de work RAM, el del N4 y el BORRADO DESTRUCTIVO del EEPROM), y ademas dejaba las MONEDAS metidas.
// TODO (no bloquea el boot, todo suelto = 0xff): verificar el ORDEN de bits del joystick contra
// KONAMI16_LSB = {START,B3,B2,B1,DOWN,UP,LEFT,RIGHT} (bit7..bit0) vs jtframe joystick[6:0].
function [7:0] konami_player( input [6:0] joy, input start );
    konami_player = { start, joy[6:0] };
endfunction
always @(*) begin
    // defaults (DIP switches hardcoded to MAME defaults: 4 players, stereo, common coin — TODO wire dipsw)
    port_in = 16'hffff;
    if( p1p3_cs ) port_in = { konami_player(joystick3, cab_1p[2]), konami_player(joystick1, cab_1p[0]) };
    if( p2p4_cs ) port_in = { konami_player(joystick4, cab_1p[3]), konami_player(joystick2, cab_1p[1]) };
    // IN0 (moo.cpp:664-671): bit0-3 COIN1-4, bit4-7 SERVICE1-4 — todos ACTIVE_LOW
    if( in0_cs  ) port_in = { 8'hff, service[3:0], coin[3:0] };
    // IN1 (moo.cpp:674-687): bit0 eep_do, bit1 eep_rdy, bit2 unk(1), bit3 SERVICE (ACTIVE_LOW),
    // bit4 SndOut(0=Stereo), bit5 CoinMech(1=Common), bit7:6 Players(10=4) — defaults de MAME.
    if( in1_cs  ) port_in = { 8'hff, 2'b10, 1'b1, 1'b0, dip_test, 1'b1, eep_rdy, eep_do };
end

/* verilator tracing_off */
always @(posedge clk) begin
    cpu_din <= rom_cs     ? rom_data        :
               ram_cs     ? ram_dout        :
               obj_cs     ? oram_dout       :
               vram_cs    ? vram_dout       :  // ram_word_r: la VRAM del K056832 se lee en words
               pal_cs     ? pal_dout        :
               pair_cs    ? {8'hff,pair_dout}:
               control2_cs? cur_control2    :
               (p1p3_cs|p2p4_cs|in0_cs|in1_cs) ? port_in : 16'hffff;
end

// ---------------- control2 (0x0de000) + EEPROM ----------------
// moo.cpp control2_w: bit0 eep di, bit1 eep cs, bit2 eep clk, bit5 IRQ5 en, bit8 objcha (spr ROM read),
//                     bit10 watchdog, bit11 IRQ4 en. (control2 latched as a 16-bit register.)
wire eep_di  = cur_control2[0];
wire eep_cs  = cur_control2[1];
wire eep_clk = cur_control2[2];
wire irq5en  = cur_control2[5];
wire irq4en  = cur_control2[11];

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        cur_control2 <= 0;
        objcha_n     <= 1;
        rmrd         <= 0;
        mute         <= 0;
    end else begin
        if( control2_cs & cpu_we ) begin
            if( !LDSn ) cur_control2[ 7:0] <= cpu_dout[ 7:0];
            if( !UDSn ) cur_control2[15:8] <= cpu_dout[15:8];
        end
        // objcha line (sprite ROM readback) = control2[8]
        objcha_n <= ~cur_control2[8];
        // rmrd: tile ROM passthrough active during a 0x1b0000 read
        rmrd     <= romrd_cs;
        mute     <= 1'b0;   // moomesa has no explicit mute bit in control2
    end
end

// sound IRQ trigger: any write to 0x0d4000 pulses the Z80 IRQ (sound_irq_w -> HOLD_LINE)
always @(posedge clk, posedge rst) begin
    if( rst ) sndon <= 0;
    else      sndon <= sndirq_cs & cpu_we;
end

// ---------------- interrupts (IRQ5 vblank, IRQ4 dmaend) ----------------
// moo_interrupt: IRQ5 on vblank if control2[5]; IRQ4 (dmaend) if control2[11]. m68k autovector.
// jtframe_edge latches the request; cleared by the CPU's interrupt-ack cycle at that level.
wire irq5_edge = ~LVBL;      // enter vblank (LVBL high=active)
wire irq4_edge = ~dma_bsy;   // end of object DMA
wire irq5_q, irq4_q;
wire irq5_ack = iack & (A[3:1]==3'd5);
wire irq4_ack = iack & (A[3:1]==3'd4);

// QSET(1): q=1 (IRQ pending) on the edge, cleared to 0 by clr (disable or ack). Active-HIGH pending.
jtframe_edge #(.QSET(1)) u_irq5(
    .rst( rst ), .clk( clk ), .edgeof( irq5_edge ), .clr( ~irq5en | irq5_ack ), .q( irq5_q ));
jtframe_edge #(.QSET(1)) u_irq4(
    .rst( rst ), .clk( clk ), .edgeof( irq4_edge ), .clr( ~irq4en | irq4_ack ), .q( irq4_q ));

always @(posedge clk) begin
    // level 5 (IPLn=010) > level 4 (IPLn=011) > none (111).
    IPLn <= irq5_q ? 3'b010 :
            irq4_q ? 3'b011 : 3'b111;
end

// ================= moo_prot (053990): HLE del blitter — FASE 4 =================
// Spec EXACTA = research/moo.cpp:520-545 (moo_prot_state::moo_prot_w), autoridad validada.
//   protram[0..0xf] = 16 words en 0x0ce000-0x0ce01f (indice = A[4:1]).
//   Escribir el indice 0xc DISPARA:
//     src1={protram[1][7:0],protram[0]}  src2={protram[3][7:0],protram[2]}
//     dst ={protram[5][7:0],protram[4]}  length=protram[0xf]
//     while(length--) { *dst = *src1 + 2 * *src2; src1+=2; src2+=2; dst+=2; }
//   (protram[8..0xb] los escribe el juego pero MAME los IGNORA y funciona -> se ignoran aqui.)
//
// POR QUE ES REQUISITO DE ARRANQUE (medido, sesion 6): el POST programa y dispara el blitter en
// 0x49e7c..0x49edc y VERIFICA EL RESULTADO POR SOFTWARE en 0x49ee4..0x49f04. Sin blitter, dst
// sigue a 0 -> la verificacion falla -> rama de error -> "N4 DEVICE ERROR" -> address error ->
// cuelgue infinito en 0x1000. No es un extra posterior: sin esto el juego NO bootea.
//
// ⚠ TRAMPA DEL BUS (jtframe_ram_rq): "It requires addr_ok signal to toggle for each request" —
// solo lanza peticion en el FLANCO DE SUBIDA de cs, y mantiene data_ok mientras cs siga alto.
// El 68k estancado mantiene ASn/BUSn BAJOS todo el rato, asi que el blitter NO puede reusarlos:
// genera su PROPIO strobe (blt_stb) y BAJA cs entre accesos. Sin eso ram_ok se quedaria pegado a
// 1 del acceso anterior y el blitter leeria 255 veces el mismo word creyendo que va bien.
// (El propio jtframe_68kdtack lo dice: "DSn must also gate the SDRAM requests so you get a cs
// toggle in the middle of the read-modify-write cycles".)
localparam [2:0] BLT_IDLE=3'd0, BLT_RD1=3'd1, BLT_RD2=3'd2, BLT_WR=3'd3, BLT_STEP=3'd4,
                 BLT_VFY=3'd5;  // solo SIMULATION: relee dst[0] para probar que la escritura aterrizo

reg  [15:0] protram[0:15];
reg  [23:1] blt_src1, blt_src2, blt_dst, blt_addr_r;
reg  [15:0] blt_len, blt_a, blt_dout_r;
reg  [ 2:0] blt_st;
reg  [ 1:0] blt_wc;
reg         blt_busy_r, blt_we_r, blt_stb_r, blt_ph, blt_served;
integer     bi;

// direccion de byte de 24 bits (MAME) -> direccion de WORD [23:1]; +=2 bytes == +1 word
wire [23:0] blt_s1b = {protram[1][7:0], protram[0]};
wire [23:0] blt_s2b = {protram[3][7:0], protram[2]};
wire [23:0] blt_dsb = {protram[5][7:0], protram[4]};

// El trigger es COMBINACIONAL para que el estancamiento entre en el MISMO ciclo en que el 68k
// decodifica la escritura: si esperasemos un ciclo, DTACKn podria asertarse antes y la CPU
// completaria el ciclo mientras el blitter le muxea la direccion del bus bajo los pies.
// blt_served impide RE-disparar: al acabar el blitter el 68k sigue en el mismo ciclo de bus
// (prot_cs y cpu_we siguen activos) -> sin este latch el blitter se relanzaria para siempre.
wire blt_trig = prot_cs & eff_we & ~eff_busn & (eff_addr[4:1]==4'hc) & ~blt_served;
assign blt_stall = blt_busy_r | blt_trig;
assign blt_busy  = blt_busy_r;
assign blt_we    = blt_we_r;
assign blt_stb   = blt_stb_r;
assign blt_addr  = blt_addr_r;
assign blt_dout  = blt_dout_r;

// Destino del acceso ACTUAL del blitter (mismo decode que el principal). El POST usa
// src1=paleta(0x1c0000), src2=work RAM(0x180000), dst=work RAM(0x181000); se admite ROM por
// generalidad (MAME usa space.read_word, todo el mapa). VRAM/objram NO estan soportadas: el
// juego no las usa como operando del blitter -> ver GAPS si algun dia aparece.
wire blt_isram = blt_addr_r[23:16]==8'h18;
wire blt_isrom = (blt_addr_r[23:19]==5'b00000) | (blt_addr_r[23:19]==5'b00010);
wire [15:0] blt_rdata = blt_isram ? ram_dout : blt_isrom ? rom_data : pal_dout;
// SDRAM: handshake real (ram_ok/rom_ok). Paleta: es BRAM del colmix (q0 registrado, ~1 clk) y no
// tiene handshake -> espera fija holgada de 4 ciclos. Coste total 255x3 accesos ~= 100 us: nada.
wire blt_rdy   = blt_isram ? ram_ok : blt_isrom ? rom_ok : (blt_wc==2'd3);

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        blt_st <= BLT_IDLE; blt_busy_r <= 0; blt_we_r <= 0; blt_stb_r <= 0; blt_ph <= 0;
        blt_served <= 0; blt_wc <= 0; blt_len <= 0; blt_a <= 0; blt_dout_r <= 0;
        blt_src1 <= 0; blt_src2 <= 0; blt_dst <= 0; blt_addr_r <= 0;
        for( bi=0; bi<16; bi=bi+1 ) protram[bi] <= 0;
    end else begin
        // protram: escritura A NIVEL (direccion y dato ASENTADOS), no por flanco -> FASE-4 §4.2-3
        // y GOTCHAS §D1/§D2. Durante el blitter prot_cs=0 (eff_addr ya no apunta ahi) -> no se corrompe.
        if( prot_cs & eff_we & ~eff_busn ) begin
            if( !LDSn ) protram[eff_addr[4:1]][ 7:0] <= cpu_dout_68k[ 7:0];
            if( !UDSn ) protram[eff_addr[4:1]][15:8] <= cpu_dout_68k[15:8];
        end
        if( BUSn ) blt_served <= 0; else if( blt_trig ) blt_served <= 1;

        case( blt_st )
            BLT_IDLE: begin
                blt_stb_r <= 0; blt_we_r <= 0; blt_ph <= 0; blt_busy_r <= 0;
                if( blt_trig ) begin
                    blt_src1 <= blt_s1b[23:1];
                    blt_src2 <= blt_s2b[23:1];
                    blt_dst  <= blt_dsb[23:1];
                    blt_len  <= protram[15];
                    if( protram[15]!=16'd0 ) begin // length==0 -> MAME no hace NADA (while(length))
                        blt_busy_r <= 1;
                        blt_st     <= BLT_RD1;
                    end
                end
            end
            // Cada acceso = 2 fases. ph=0: cs BAJO (fuerza el toggle que exige jtframe_ram_rq y
            // limpia data_ok del acceso anterior) y coloca la direccion. ph=1: cs alto, esperar rdy.
            BLT_RD1: if( !blt_ph ) begin
                blt_addr_r <= blt_src1; blt_we_r <= 0; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    blt_a <= blt_rdata; blt_stb_r <= 0; blt_ph <= 0; blt_st <= BLT_RD2;
                end
            end
            BLT_RD2: if( !blt_ph ) begin
                blt_addr_r <= blt_src2; blt_we_r <= 0; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    // res = a + 2*b. MAME lo calcula en 32 bits y write_word TRUNCA a 16 ->
                    // el desbordamiento de 16 bits es el comportamiento correcto, no un bug.
                    blt_dout_r <= blt_a + {blt_rdata[14:0],1'b0};
                    blt_stb_r <= 0; blt_ph <= 0; blt_st <= BLT_WR;
                end
            end
            BLT_WR: if( !blt_ph ) begin
                blt_addr_r <= blt_dst; blt_we_r <= 1; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    blt_stb_r <= 0; blt_we_r <= 0; blt_ph <= 0; blt_st <= BLT_STEP;
                end
            end
            BLT_STEP: begin
                blt_src1 <= blt_src1 + 1'd1;   // +2 bytes = +1 word
                blt_src2 <= blt_src2 + 1'd1;
                blt_dst  <= blt_dst  + 1'd1;
                blt_len  <= blt_len  - 1'd1;
                if( blt_len==16'd1 ) begin
`ifdef SIMULATION
                    blt_st <= BLT_VFY;   // relee dst[0] antes de soltar el bus
`else
                    blt_busy_r <= 0; blt_st <= BLT_IDLE;
`endif
                end else                   blt_st <= BLT_RD1;
            end
`ifdef SIMULATION
            // Relectura de dst[0] por el MISMO camino que usa el blitter. Zanja la pregunta que la
            // sonda del lado CPU no consigue contestar: 0000 = la escritura aterrizo; 0080 = NO
            // aterrizo y sigue el VENENO que el POST dejo en 0x181000 (0x49e6a rellena 0x180f00-
            // 0x1810fe con 0..0xff; en 0x181000 toca 0x80).
            BLT_VFY: if( !blt_ph ) begin
                blt_addr_r <= blt_dsb[23:1]; blt_we_r <= 0; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    $display("PROT: RELECTURA dst[0]=%06x -> %04x   (0000=escritura OK | 0080=veneno intacto)",
                        {blt_dsb[23:1],1'b0}, blt_rdata);
                    blt_stb_r <= 0; blt_ph <= 0; blt_busy_r <= 0; blt_st <= BLT_IDLE;
                end
            end
`endif
            default: blt_st <= BLT_IDLE;
        endcase
    end
end

`ifdef SIMULATION
// Testigo del blitter: dice si DISPARO y con que parametros. Si el POST sigue muriendo, esta
// linea distingue "no dispara" (decode/trigger mal) de "dispara pero calcula mal" (datos).
reg blt_busy_l;
reg [7:0] blt_shown;
reg [15:0] blt_nwr;   // escrituras que REALMENTE cerraron su handshake (ram_ok) durante el blitter
always @(posedge clk) begin
    blt_busy_l <= blt_busy_r;
    if( blt_st==BLT_WR && blt_ph && blt_rdy ) blt_nwr <= blt_nwr + 16'd1;
    if( blt_busy_r & ~blt_busy_l ) begin
        blt_shown <= 0; blt_nwr <= 0;
        $display("PROT: blitter DISPARADO src1=%06x src2=%06x dst=%06x len=%0d",
            blt_s1b, blt_s2b, blt_dsb, protram[15]);
    end
    // Primeras 4 operaciones con sus OPERANDOS: el check exige pal[k]==0 para todo k (ver
    // desensamblado 0x49efa). Si algun a=... sale != 0, el check NO puede pasar y el problema
    // esta en la PALETA (lectura con perdida del byte alto, §D), no en el blitter.
    if( blt_st==BLT_WR && !blt_ph && blt_shown<8'd4 ) begin
        blt_shown <= blt_shown + 8'd1;
        $display("PROT:   op%0d dst=%06x <= a(pal)=%04x + 2*b(ram)=%04x => %04x",
            blt_shown, {blt_dst,1'b0}, blt_a, (blt_dout_r-blt_a)>>1, blt_dout_r);
    end
    if( ~blt_busy_r & blt_busy_l )
        $display("PROT: blitter FIN (ultimo dst=%06x dato=%04x) escrituras COMPLETADAS=%0d (deben ser 255)",
            {blt_dst,1'b0}, blt_dout_r, blt_nwr);
end

// ¿PASA el check de proteccion? Desensamblado: 0x49f04 `beq $49f28` (=dbra, sigue el bucle de 257
// iteraciones); si NO casa cae a 0x49f06 = rama de error -> "N4 DEVICE ERROR". 0x49f2c = el dbra
// se agoto SIN error = CHECK SUPERADO. Esta sonda distingue "sigue fallando el N4" de "el N4 pasa
// y lo que muere es OTRA cosa mas adelante" (ambos acaban en el mismo impresor 0x4a5e4 -> el
// backtrace por si solo NO los distingue).
// Que lee REALMENTE la CPU en las 3 direcciones del check. El anillo generico no sirve aqui (su
// ventana de captura no coincide con el instante en que el 68k toma el dato). Aqui se muestrea justo
// cuando la CPU LATCHEA: ciclo de lectura con DTACK ya asertado (~dtac_mux).
// ARMADO tras el disparo del blitter: el test de work RAM (f=13..28) machaca estas mismas
// direcciones con sus patrones (5555/aaaa...) y se comia el presupuesto de prints antes del check.
reg [7:0] chk_n;
reg       chk_arm;
always @(posedge clk, posedge rst) begin
    if( rst ) chk_arm <= 0; else if( blt_busy_r ) chk_arm <= 1;
end
always @(posedge clk, posedge rst) begin
    if( rst ) chk_n <= 0;
    else if( chk_arm && chk_n<8'd9 && ~ASn && RnW && ~BUSn && ~dtac_mux &&
             ( {A,1'b0}==24'h1c0000 || {A,1'b0}==24'h181000 || {A,1'b0}==24'h180000 ) ) begin
        chk_n <= chk_n + 8'd1;
        $display("CHK: la CPU lee %06x -> cpu_din=%04x (pal_dout=%04x ram_dout=%04x pal_cs=%0d ram_cs=%0d)",
            {A,1'b0}, cpu_din, pal_dout, ram_dout, pal_cs, ram_cs);
    end
end

// ⚠ TRAMPA DEL 68000: PREFETCH DE 2 WORDS. "el PC ha llegado a X" NO significa "X se ha ejecutado":
// tras un `beq` el 68k YA HA BUSCADO las 2 palabras siguientes, se tome la rama o no. La sonda
// anterior vigilaba 0x49f06 (la palabra pegada al `beq $49f28` de 0x49f04) y por eso gritaba
// "CHECK FALLADO" SIEMPRE, incluso con el check pasando. Hay que vigilar direcciones FUERA de la
// cola de prefetch (>= 3 words tras la bifurcacion):
//   0x49f0e = `lea $141a38,A0` -> 4 words tras el beq: solo se busca si la rama de error se EJECUTA.
//   0x49f34 = 2 instrucciones tras el `dbra` de 0x49f28 -> solo se busca al AGOTARSE el bucle (=OK).
reg n4_done;
wire n4_fetch = ~ASn & RnW & FC[1] & ~FC[0];  // = prog_fetch (se declara mas abajo; inline para no depender del orden)
always @(posedge clk, posedge rst) begin
    if( rst ) n4_done <= 0;
    else if( !n4_done && n4_fetch ) begin
        if( {A,1'b0}==24'h049f0e ) begin n4_done<=1; $display("*** N4: CHECK FALLADO (se EJECUTA la rama de error: 0x49f0e)"); end
        if( {A,1'b0}==24'h049f34 ) begin n4_done<=1; $display("*** N4: CHECK SUPERADO (0x49f34: el dbra de 257 vueltas se agoto sin error) <<<"); end
    end
end
`endif

`ifdef SIMULATION
// ---------------- TELEMETRIA DE BOOT (Fase 1, sesion 6) — solo simulacion ----------------
// A 28 s/frame no se puede diagnosticar el boot "corriendo mas frames": una linea por vblank
// dice si el 68k AVANZA (rango de PC) y si TOCA el hardware. Sin control2[5] no hay IRQ5 y el
// bucle principal nunca corre -> ese bit es el testigo clave de "arranco de verdad".
// RANGO DE DATOS POR FRAME (`dato=[lo-hi]`): el bucle de checksum de ROM (0x4a388) no se puede juzgar
// por el PC — el PC se queda quieto dentro del bucle tanto si AVANZA como si se repite. Lo que dice la
// verdad es POR DONDE VA EL PUNTERO (A0): si el checksum progresa, este rango BARRE hasta 0x07ffff.
reg [23:1] daf_lo, daf_hi;
wire       data_acc = ~ASn & ~FC[1] & FC[0];   // espacio de DATOS (FC=x01)
reg [23:1] pc_lo, pc_hi, pc_last, pcf_lo, pcf_hi;
reg [31:0] n_prog, n_ram_w, n_vram_w, n_pal_w, n_obj_w, n_ctl2_w, n_irq5, n_irq4;
reg [31:0] n_dma, n_objreg;
reg [ 7:0] cfg_seen;      // ultimo valor escrito al registro 5 del K053246 (= cfg; bit4 = dma_en)
reg        dmab_l;
reg [15:0] frame_id;
reg        lvbl_l, busn_l;
wire       prog_fetch = ~ASn & RnW & FC[1] & ~FC[0]; // FC=x10 program space (user/supervisor)
// OJO: contar `cpu_we & ~BUSn` por CICLO DE RELOJ infla ~13x (el 68k mantiene el strobe varios clk de 48MHz).
// Hay que contar 1 por CICLO DE BUS = flanco de bajada de BUSn (un long access da 2 strobes: correcto).
wire       wr_stb = busn_l & ~BUSn & cpu_we;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        pc_lo <= ~23'd0; pc_hi <= 0; pc_last <= 0; frame_id <= 0; lvbl_l <= 0;
        pcf_lo <= ~23'd0; pcf_hi <= 0; busn_l <= 1;
        daf_lo <= ~23'd0; daf_hi <= 0;
        n_prog<=0; n_ram_w<=0; n_vram_w<=0; n_pal_w<=0; n_obj_w<=0; n_ctl2_w<=0; n_irq5<=0; n_irq4<=0;
        n_dma<=0; n_objreg<=0; cfg_seen<=0; dmab_l<=0;
    end else begin
        lvbl_l <= LVBL;
        busn_l <= BUSn;
        // ¿CORRE el DMA de objetos? 1 por flanco de SUBIDA de dma_bsy. Si esto es 0 con irq4en=1,
        // la IRQ4 NO PUEDE dispararse nunca (irq4_edge = ~dma_bsy no tiene flanco que detectar).
        dmab_l <= dma_bsy;
        if( ~dmab_l & dma_bsy ) n_dma <= n_dma+1;
        if( data_acc ) begin
            if( A < daf_lo ) daf_lo <= A;
            if( A > daf_hi ) daf_hi <= A;
        end
        if( prog_fetch ) begin
            pc_last <= A; n_prog <= n_prog+1;
            if( A < pc_lo ) pc_lo <= A;   // acumulado (cuanto codigo se ha tocado)
            if( A > pc_hi ) pc_hi <= A;
            if( A < pcf_lo ) pcf_lo <= A; // POR FRAME = extension del bucle actual
            if( A > pcf_hi ) pcf_hi <= A;
        end
        if( wr_stb ) begin
            if( ram_cs      ) n_ram_w  <= n_ram_w +1;
            if( vram_cs     ) n_vram_w <= n_vram_w+1;
            if( pal_cs      ) n_pal_w  <= n_pal_w +1;
            if( obj_cs      ) n_obj_w  <= n_obj_w +1;
            if( control2_cs ) n_ctl2_w <= n_ctl2_w+1;
            if( objreg_cs   ) begin
                n_objreg <= n_objreg+1;
                // reg 5 del K053246 = cfg. El juego hace `move.b $180013,$c2005` (BYTE a impar -> LDS).
                // Mismo decode que jt053246_mmr en modo 16-bit: case(cpu_addr[2:1])==2 + ~cpu_dsn[0].
                if( eff_addr[2:1]==2'd2 && !eff_dsn[0] ) cfg_seen <= cpu_dout[7:0];
            end
        end
        if( irq5_ack ) n_irq5 <= n_irq5+1;
        if( irq4_ack ) n_irq4 <= n_irq4+1;
        if( lvbl_l & ~LVBL ) begin // caida de LVBL = 1 informe por frame
            frame_id <= frame_id+1;
            $display("BOOT f=%0d PC=%06x bucle=[%06x-%06x] dato=[%06x-%06x] visto=[%06x-%06x] | wr ram=%0d vram=%0d pal=%0d obj=%0d ctl2=%0d | ctl2=%04x irq5en=%0d irq4en=%0d ack5=%0d ack4=%0d | objreg=%0d cfg=%02x dma_en=%0d DMA/f=%0d",
                frame_id, {pc_last,1'b0}, {pcf_lo,1'b0}, {pcf_hi,1'b0}, {daf_lo,1'b0}, {daf_hi,1'b0},
                {pc_lo,1'b0}, {pc_hi,1'b0},
                n_ram_w, n_vram_w, n_pal_w, n_obj_w, n_ctl2_w,
                cur_control2, irq5en, irq4en, n_irq5, n_irq4,
                n_objreg, cfg_seen, cfg_seen[4], n_dma);
            // contadores y rango `bucle` = POR FRAME; `visto` = acumulado. wr_* = ciclos de BUS reales.
            n_prog<=0; n_ram_w<=0; n_vram_w<=0; n_pal_w<=0; n_obj_w<=0; n_ctl2_w<=0;
            n_dma<=0; n_objreg<=0;   // por frame (cfg_seen NO: es un estado, no un contador)
            pcf_lo <= ~23'd0; pcf_hi <= 0;
            daf_lo <= ~23'd0; daf_hi <= 0;
        end
    end
end
`endif

`ifdef SIMULATION
// ---------------- BACKTRACE DEL FALLO (Fase 1, sesion 6) — solo simulacion ----------------
// Los vectores 2 (bus error) y 3 (address error) apuntan AMBOS a 0x1000, que acaba en `nop; bra self`
// (bucle infinito). Sintoma en la telemetria: PC clavado en bucle=[001006-00100a] con 0 escrituras.
// Como BERRn esta atado a 1, solo puede ser ADDRESS ERROR (acceso word/long a direccion IMPAR).
// Esto vuelca las ultimas 32 direcciones de PROGRAMA distintas + los ultimos accesos a DATOS,
// para identificar QUE codigo salto/leyo mal. Se dispara UNA vez, al entrar en el handler.
reg [23:1] trc[0:31];
reg [23:1] dtrc[0:15];      // anillo de accesos a DATOS: dice QUE operando/cadena estaba tocando.
reg [15:0] dval[0:15];      // ...y su VALOR. Sin el valor el anillo dice DONDE mira pero no QUE ve.
reg [23:1] da_last;
reg [ 4:0] tptr;
reg [ 3:0] dptr;
reg        dumped;
reg [ 3:0] dpend;
reg        dpend_v;
integer    k;
// Volcar en la RAMA DE ERROR del check N4 (0x49f06), no solo en el handler de address error: para
// entonces el anillo ya se ha llevado por delante los operandos culpables. Aqui los ultimos accesos
// son justo pal[k] (0x1c0000+2k), dst[k] (0x181000+2k) y ram[k] (0x180000+2k) -> la direccion da el
// k que falla y el valor dice cual de los tres no vale lo que deberia.
// 0x49f0e (NO 0x49f06): la palabra pegada al `beq` de 0x49f04 la PREFETCHA el 68k siempre -> vigilarla
// disparaba este volcado en todos los runs, incluso con el check pasando. Ver la sonda n4_done.
wire       in_fault = prog_fetch & ( (({A,1'b0}>=24'h1000) & ({A,1'b0}<=24'h100a))
                                   | ({A,1'b0}==24'h049f0e) );
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        tptr <= 0; dptr <= 0; dumped <= 0; da_last <= 0; dpend <= 0; dpend_v <= 0;
        for( k=0; k<32; k=k+1 ) trc[k] <= 0;
        for( k=0; k<16; k=k+1 ) begin dtrc[k] <= 0; dval[k] <= 0; end
    end else begin
        // ultimos accesos a espacio de DATOS (FC=x01). OJO: los 2 ultimos seran 0x0c/0x0e = la LECTURA
        // DEL VECTOR 3 que hace el propio 68k al fallar; los anteriores son el operando culpable.
        if( ~ASn & ~FC[1] & FC[0] & (A!=da_last) ) begin
            da_last <= A;
            dtrc[dptr] <= A; dptr <= dptr+1;
            dpend  <= dptr;
            dpend_v<= RnW;       // solo tiene sentido para LECTURAS
        end
        // El dato NO esta listo al principio del ciclo (la SDRAM tarda). Refrescar durante TODO el
        // strobe: el ultimo valor con ~BUSn es el que se lleva la CPU. (El intento anterior capturaba
        // con BUSn ALTO y devolvia el dato del acceso ANTERIOR -> instrumento mentiroso.)
        if( dpend_v & ~BUSn ) dval[dpend] <= cpu_din;
        if( prog_fetch & (A!=pc_last) ) begin trc[tptr] <= A; tptr <= tptr+1; end
        if( in_fault & ~dumped ) begin
            dumped <= 1;
            $display("*** FALLO en PC=%06x (0x49f06 = rama de error del check N4; 0x1000 = handler de address error)", {A,1'b0});
            $display("*** ultimos accesos a DATOS (antiguo -> reciente). En el check N4:");
            $display("***   1c0000+2k = pal[k] | 181000+2k = dst[k] (blitter) | 180000+2k = ram[k]");
            for( k=0; k<16; k=k+1 )
                $display("***   dato %06x = %04x", {dtrc[(dptr+k)&4'hf],1'b0}, dval[(dptr+k)&4'hf]);
            $display("*** backtrace de PC (antiguo -> reciente):");
            for( k=0; k<32; k=k+1 )
                $display("***   %06x", {trc[(tptr+k)&5'h1f],1'b0});
        end
    end
end
`endif

// pause via HALTn (as the inherited main did): dip_pause low -> CPU halted
reg HALTn;
always @(posedge clk) HALTn <= dip_pause & ~rst;

jt5911 #(.SIMFILE("nvram.bin")) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sclk       ( eep_clk   ),
    .sdi        ( eep_di    ),
    .sdo        ( eep_do    ),
    .rdy        ( eep_rdy   ),
    .scs        ( eep_cs    ),
    .mem_addr   ( nv_addr   ),
    .mem_din    ( nv_din    ),
    .mem_we     ( nv_we     ),
    .mem_dout   ( nv_dout   ),
    .dump_clr   ( 1'b0      ),
    .dump_flag  (           )
);

jtframe_68kdtack_cen #(.W(6),.RECOVERY(1)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( bus_cs    ),
    .bus_busy   ( bus_busy  ),
    .bus_legit  ( 1'b0      ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    .num        ( 5'd1      ),  // 16MHz = 48/3
    .den        ( 6'd3      ),
    .DTACKn     ( DTACKn    ),
    .wait2      ( 1'b0      ),
    .wait3      ( 1'b0      ),
    .fave       (           ),
    .fworst     (           )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),

    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout_68k),

    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( VPAn        ),
    .FC         ( FC          ),

    .BERRn      ( 1'b1        ),
    .HALTn      ( HALTn       ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),

    .DTACKn     ( dtac_mux    ),
    .IPLn       ( IPLn        )
);
`else
    initial begin
        obj_cs    = 0;
        objcha_n  = 1;
        objreg_cs = 0;
        pal_cs    = 0;
        pcu_cs    = 0;
        ram_cs    = 0;
        rmrd      = 0;
        rom_cs    = 0;
        sndon     = 0;
        vram_cs   = 0;
        tilereg_cs= 0;
        alpha_cs  = 0;
        mute      = 0;
    end
    assign
        cpu_dout  = 0,
        cpu_we    = 0,
        main_addr = 0,
        ram_dsn   = 0,
        snd_wrn   = 0,
        st_dout   = 0,
        nv_addr   = 0,
        nv_din    = 0,
        pair_we   = 0,
        nv_we     = 0;
`endif
endmodule
