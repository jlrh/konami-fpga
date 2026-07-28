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

    FASE 1 (2026-07-19): escrito al mapa REAL de asterix (konami/asterix.cpp
    asterix_state::main_map, lineas 295-317). Base: jtcowboys_main.v (hermano Konami:
    68k+dtack+jt5911+contrato jtframe), pero el mapa, control2, IRQ, inputs, sprites
    (K053244/45) y la proteccion son de asterix (chip/mapa distintos a moomesa).

    Mapa 68k (byte addr = {A,1'b0}):
      000000-0FFFFF ROM         100000-107FFF work RAM
      180000-1807FF K053245 spr-RAM (word)   180800-180FFF RAM extra
      200000-20000F K053244 regs (word)      300000-30001F K053244 regs (umask 00ff)
      280000-280FFF paleta (xBGR555)
      380000 IN0   380002 IN1   380100 control2  380200-3 K053260 main
      380300 sound_irq  380400 spritebank  380500-51F K053251  380600 watchdog
      380700-707 K056832 b_word_w   380800-3 protection (blitter, Fase 4)
      400000-400FFF K056832 VRAM    420000-421FFF tile-ROM passthrough   440000-44003F K056832 regs
*/

module jtasterix_main(
    input                rst,
    input                clk,       // 48 MHz
    input                LVBL,
    input                irq_en,    // K056832 is_irq_enabled(0): enmascara la IRQ5 de vblank (asterix.cpp:229)

    output        [19:1] main_addr, // region maincpu = 0x100000 B -> [19:1] (ver cfg/mem.yaml)
    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,
    output               cpu_we,

    // chip-selects (asterix decode)
    output reg           rom_cs,
    output reg           ram_cs,
    output reg           oram_cs,     // K053245 sprite-RAM  0x180000-1807FF (k053245_word_r/w)
    output reg           eram_cs,     // RAM extra           0x180800-180FFF (asterix.cpp:300 .ram())
    output reg           objreg_cs,   // K053244 regs        0x200000 (word) / 0x300000 (byte)
    output reg           objreg_byte, // 1 = ventana 0x300000 (umask 00ff, acceso a byte impar)
    output reg           pal_cs,      // paleta              0x280000
    output reg           vram_cs,     // K056832 VRAM        0x400000 (ram_half_word)
    output reg           tilereg_cs,  // K056832 word_w      0x440000
    output reg           tilereg_b_cs,// K056832 b_word_w    0x380700 (VSCCS)
    output reg           romrd_cs,    // K056832 tile-ROM    0x420000 (old_rom_word_r passthrough)
    output reg           pcu_cs,      // K053251 prioridad   0x380500
    output reg           spritebank_cs,// spritebank_w       0x380400
    output reg           prot_cs,     // proteccion (blitter) 0x380800  (Fase 4)

    // sonido (K053260 main port + IRQ)
    output               snd_wrn,     // strobe de escritura del 68k al K053260 (main->sub)
    output        [ 7:0] snd_dout,    // dato main->sub  (0x380201/0x380203)
    input         [ 7:0] snd2main,    // main_read (sub->main): el Z80 contesta aqui (POST boot-gate)
    output reg           sndon,       // sound_irq_w 0x380300 -> IRQ al Z80

    // datos de periféricos (leidos por el 68k)
    input         [15:0] oram_dout,   // K053245 spr-RAM
    input         [15:0] eram_dout,   // RAM extra 0x180800-180FFF
    input         [15:0] objreg_dout, // K053244 regs (status: dma/objcha)
    input         [15:0] vram_dout,   // K056832 VRAM (ram_word_r)
    input         [15:0] pal_dout,
    input         [15:0] ram_dout,
    input         [15:0] rom_data,
    input                ram_ok,
    input                rom_ok,
    input                vdtac,       // DTACK del subsistema de video (busy)

    // EEPROM ER5911
    output      [ 6:0]   nv_addr,
    input       [ 7:0]   nv_dout,
    output      [ 7:0]   nv_din,
    output               nv_we,

    // control2 -> video/sonido
    output reg           tilebank,    // control2 bit5 -> K056832 set_tile_bank (m_cur_tile_bank)
    output reg   [15:0]  spritebank,  // 0x380400 (reset_spritebank) -> code de sprite (K053245)

    // Cabina (asterix = 2 botones -> joystick jtframe = [BUTTONS+3:0] = [5:0])
    input         [ 5:0] joystick1,
    input         [ 5:0] joystick2,
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
reg  [15:0] cur_control2;   // 0x380100 (asterix.cpp control2_w)
wire        eep_rdy, eep_do, bus_cs, bus_busy, BUSn;
wire        dtac_mux, iack;
wire [15:0] cpu_dout_68k;   // dato del 68k ANTES del mux del blitter (ver "proteccion", abajo)

// --- bus EFECTIVO: el blitter de la proteccion (0x380800) es BUS MASTER y suplanta al 68k ---
// Mismo patron que cowboys (moo_prot): mientras `blt_busy` el decode, la direccion, el dato y el
// we salen del blitter, y el 68k queda estancado DENTRO de su ciclo de escritura (blt_stall).
wire [23:1] blt_addr;
wire [15:0] blt_dout;
wire        blt_busy, blt_we, blt_stb, blt_stall;
wire [23:1] eff_addr = blt_busy ? blt_addr : A;
wire        eff_busn = blt_busy ? ~blt_stb : BUSn;
wire        eff_we   = blt_busy ?  blt_we  : ~RnW;
wire [ 1:0] eff_dsn  = blt_busy ? 2'b00    : {UDSn,LDSn};

// sub-selects del bloque 0x380000
reg  io_cs, in0_cs, in1_cs, control2_cs, sndmain_cs, sndirq_cs, watchdog_cs;
reg  [15:0] port_in;

assign main_addr= eff_addr[19:1];
assign ram_dsn  = eff_dsn;
// El generador de DTACK solo debe ver los accesos DEL 68k: los del blitter se le ocultan, o su
// recovery contaria ciclos de bus que la CPU no ha pedido.
assign bus_cs   = (rom_cs | ram_cs) & ~blt_busy;
assign bus_busy = ((rom_cs & ~rom_ok) | (ram_cs & ~ram_ok)) & ~blt_busy;
assign BUSn     = ASn | (LDSn & UDSn);
assign cpu_we   = eff_we;
assign cpu_dout = blt_busy ? blt_dout : cpu_dout_68k;
assign st_dout  = { tilebank, cur_control2[5:0], 1'b0 };
// autovector 6800-style durante interrupt-ack (FC==7 CPU space)
assign VPAn     = ~(&FC & ~ASn);
assign iack     =  &FC & ~ASn;
// blt_stall estanca al 68k DENTRO del propio ciclo de escritura de 0x380802: la CPU no completa
// el ciclo hasta que el blitter termina, igual que el chip real (que retiene el bus).
assign dtac_mux = DTACKn | ~vdtac | blt_stall;
// K053260 main write: byte a 0x380201/0x380203 (umask 00ff -> LDS)
assign snd_wrn  = ~(sndmain_cs & ~RnW & ~LDSn);
assign snd_dout = cpu_dout_68k[7:0];

// ---------------- asterix address decode (asterix_state::main_map) ----------------
`ifdef SIMULATION
reg none_cs;
// SONDA de DECODE: accesos del 68k que no caen en NINGUN chip-select. Un hueco en el mapa no da
// error — devuelve 0xffff y el fallo aparece lejos y disfrazado. Asi se cazo el 0x180800-0x180FFF
// (`map(...).ram()` que faltaba): el test de RAM del POST no releia el patron y colgaba en 0x5030.
integer n_none=0;
always @(posedge clk) if( none_cs ) begin
    n_none <= n_none+1;
    if( n_none<32 || n_none%100000==0 )
        $display("MAIN-NONE[%0d]: acceso SIN decode A=%06x RnW=%b (devuelve 0xffff)", n_none, {A,1'b0}, RnW);
end
// SONDA DE DATOS de la work RAM: volcado literal de los ciclos de bus en una ventana ESTRECHA
// (0x104000-0x10401F) para ver que se escribe y que se relee, sin teorizar. El test de RAM del POST
// solo hace accesos de LONG (los dos bytes SIEMPRE habilitados), asi que un fallo limitado al lane
// UDS NO puede ser un problema de byte-enables: hay que mirar el dato real.
// La ventana de 32 bytes salio PERFECTA en las 5 pasadas (0000/5555/aaaa/ffff e incremental), asi
// que los fallos son DISPERSOS por los 16 KB (28 por lane sobre 4096 longs ~ 0,7%). Un volcado fijo
// no vale: hace falta un SHADOW auto-comprobante de toda la region que imprima SOLO los desajustes.
reg [15:0] shadow[0:16383];   // 0x100000-0x107FFF = 16K words
reg        wrote [0:16383];   // solo se compara lo que se ha escrito antes
integer    si;
initial for(si=0;si<16384;si=si+1) wrote[si]=0;
integer n_mis=0;
reg busn_dl=1;
always @(posedge clk) begin
    busn_dl <= BUSn;
    // ⚠ `!blt_busy` en TODAS las sondas que cuelgan de un *_cs: desde la ses.26 esos cs tambien los
    // genera el BLITTER (bus master), y sus accesos no son ciclos del 68k. Sin esto la sonda de PC
    // contaria las lecturas de ROM del blitter y AMAX saldria falseado.
    if( busn_dl && !BUSn && ram_cs && cpu_we && !blt_busy ) begin
        if( !UDSn ) shadow[A[14:1]][15:8] <= cpu_dout_68k[15:8];
        if( !LDSn ) shadow[A[14:1]][ 7:0] <= cpu_dout_68k[ 7:0];
        if( !UDSn && !LDSn ) wrote[A[14:1]] <= 1;
    end
    if( !busn_dl && BUSn && RnW && A[23:15]==9'h20 && wrote[A[14:1]]
        && cpu_din!==shadow[A[14:1]] && n_mis<40 ) begin
        n_mis <= n_mis+1;
        $display("RAMMIS[%0d] A=%06x leido=%04x esperado=%04x", n_mis, {A,1'b0}, cpu_din, shadow[A[14:1]]);
    end
end

// SONDA "PANTALLA DE TEST": QUE test del POST ha fallado, sin adivinar.
// El POST no se limita a colgarse: antes PINTA la pantalla de resultados de Konami (0x4fee-0x502c).
// Recorre 14 entradas; por cada bit de D7 escribe en VRAM el marcador de FALLO **0x4012** (y si el
// bit esta a 0, rellena con 0x0060 = hueco). La direccion de destino sale de la tabla de punteros
// de 0x27ef6, asi que la DIRECCION del write identifica la entrada:
//   [0]0x40049e [1]0x40059e [2]0x40069e [3]0x40079e [4]0x40089c [5]0x40099c [6]0x400a9c
//   [7]0x400b9c [8]0x400c9c [9]0x400d1c [10]0x4004ba [11]0x40063a [12]0x4007ba [13]0x40093a
// (los rotulos de texto de cada linea estan en 0x27f32, formato [dir 4B][tiles..][ff fe]).
always @(posedge clk) if( vram_cs & cpu_we & ~BUSn & cpu_dout_68k==16'h4012 )
    $display("MAIN-POST-NG: marcador de FALLO en VRAM %06x (tabla 0x27ef6 -> esa entrada del test)", {A,1'b0});

// SONDA temporal (Fase 3): ¿avanza el POST o esta colgado en el bucle de error 0x5030?
// El POST acumula fallos en D7 y en 0x5048 hace `tst.w D7 / bne $5030 / jmp $6c8`. Se reporta
// la zona de PC que mas se visita en cada ventana: si domina 0x5030-0x504c -> COLGADO (D7!=0);
// si aparece >=0x6c8 fuera de la zona del POST -> ARRANCO.
// Primeras lecturas de ROM: si el vector de reset no llega bien, el 68k arranca con un PC malo.
// Esperado: A=000000 -> 0010, A=000002 -> 4600 (SP=0x00104600); A=000004 -> 0000, A=000006 -> 0400
// (PC=0x00000400 = entrada del POST).
integer n_rd=0;
always @(posedge clk) if( rom_cs && rom_ok && !ASn && !blt_busy ) begin
    if( n_rd < 24 ) begin
        n_rd <= n_rd+1;
        $display("MAIN-RD[%0d] A=%06x data=%04x rom_ok=%b", n_rd, {A,1'b0}, rom_data, rom_ok);
    end
end

// Boot-gate: que ESCRIBE el 68k al K053260, si emite la IRQ, y que LEE del puerto sub->main.
// ⚠ Detectar FLANCO del ciclo de bus: los *_cs duran varios relojes, asi que sin flanco un solo
// acceso dispara decenas de muestras (y agota cualquier limite antes de llegar al caso interesante).
reg sw_l=0, si_l=0, sr_l=0;
wire sw_now = sndmain_cs & cpu_we & ~BUSn;
wire si_now = sndirq_cs  & cpu_we & ~BUSn;
wire sr_now = sndmain_cs & RnW    & ~BUSn;
integer n_sr=0;
always @(posedge clk) begin
    sw_l <= sw_now; si_l <= si_now; sr_l <= sr_now;
    if( sw_now && !sw_l )
        $display("MAIN-SND: escribe main->sub A=%06x dato=%02x", {A,1'b0}, cpu_dout_68k[7:0]);
    if( si_now && !si_l )
        $display("MAIN-SND: IRQ al Z80");
    if( sr_now && !sr_l ) begin
        n_sr <= n_sr+1;
        if( n_sr<40 || snd2main[7]==0 )
            $display("MAIN-SND: LEE sub->main A=%06x -> %02x (bit7=%b : 0 = pasa el test)",
                     {A,1'b0}, snd2main, snd2main[7]);
    end
end

// ⚠⚠ BORRADAS las sondas "PC/lectura == dirección del `ori ...,D7`" (0x4eea/0x4efe/0x4f0e/0x5080)
// y la del test de RAM (tablas 0x5264/0x5268). NO SON FIABLES y me han engañado DOS VECES:
//   (a) PREFETCH: el 68000 lee por delante, así que ver la dirección de un `ori` NO implica ejecutarlo.
//   (b) BARRIDO DE CHECKSUM: la rutina 0x5052 LEE LOS 8 MB DE ROM COMO DATOS con paso 2, o sea que
//       pasa por CUALQUIER dirección que se vigile — incluidas 0x5264/0x5266/0x5268/0x526a y 0x6c8.
//       Por eso "POST-FALLA: TEST DE RAM" salía 28 veces por lane con la RAM PERFECTA (los shadows
//       RAMMIS/RAMMIS2 dieron 0 desajustes y el long de 0x180FFC leía 0xFCFDFEFF = el valor CORRECTO),
//       y por eso ARRANCO se encendía a mitad del POST.
// REGLA: en este POST solo valen como indicador las ESCRITURAS (no tienen prefetch ni las genera el
// barrido de checksum). El bueno es MAIN-POST-NG, más abajo: el marcador 0x4012 en VRAM.



integer n_pc=0, n_post=0, n_hang=0, n_game=0, n_vec=0, n_test=0;
reg [23:1] amax=0;
reg        arranco=0;
always @(posedge clk) begin
    if( rom_cs && !blt_busy ) begin
        n_pc <= n_pc+1;
        if( A[23:1] > amax ) amax <= A[23:1];
        if     ( A[23:1] <  23'h200 )                        n_vec  <= n_vec+1;   // <0x400 vectores
        else if( A[23:1]>=23'h2818 && A[23:1]<=23'h2826 )     n_hang <= n_hang+1;  // 0x5030..0x504c
        else if( A[23:1] <  23'h2818 )                        n_post <= n_post+1;  // <0x5030 (POST *y* juego)
        else                                                  n_test <= n_test+1;  // >0x504c rutinas de test
        // ⚠ 0x6c8 (entrada del juego) esta POR DEBAJO de 0x5030, asi que las BANDAS no separan
        // POST de juego. El indicador positivo es este flag pegajoso: a 0x6c8 solo se llega por el
        // `jmp $6c8.l` de 0x504c, que solo se ejecuta si D7==0 (POST OK).
        // ⚠⚠ OBLIGATORIO gatear por FC=110 (PROGRAM, supervisor). Sin eso da FALSO POSITIVO: el
        // barrido de checksum (0x5052) LEE los 8 MB de ROM como DATOS con paso 2, asi que pasa por
        // 0x6c8 y encendia el flag a mitad del POST. Me lo trago una vez: el flag decia ARRANCO=1
        // mientras el 68k seguia dentro del POST. FC=101 seria DATA supervisor.
        if( A[23:1]==23'h364 && FC==3'b110 && !arranco ) begin
            arranco <= 1;
            $display("MAIN-PC: *** POST SUPERADO *** salta a 0x6c8 (entrada del juego) tras %0d accesos", n_pc);
        end
        if( n_pc % 1000000 == 0 )
            $display("MAIN-PC: acc=%0dM | vec=%0d POST/juego(<0x5030)=%0d BUCLE-ERR(0x5030)=%0d TESTS(>0x504c)=%0d ARRANCO=%b | A=%06x AMAX=%06x",
                     n_pc/1000000, n_vec, n_post, n_hang, n_test, arranco, {A,1'b0}, {amax,1'b0});
    end
end
`endif
always @* begin
    rom_cs      = 0; ram_cs   = 0; oram_cs  = 0; objreg_cs = 0; objreg_byte = 0;
    pal_cs      = 0; vram_cs  = 0; tilereg_cs = 0; tilereg_b_cs = 0; romrd_cs = 0;
    pcu_cs      = 0; spritebank_cs = 0; prot_cs = 0; eram_cs = 0;
    io_cs       = 0; in0_cs = 0; in1_cs = 0; control2_cs = 0;
    sndmain_cs  = 0; sndirq_cs = 0; watchdog_cs = 0;
    // ⚠ TODO el decode va sobre `eff_addr`/`eff_busn`, NO sobre A/BUSn: cuando el blitter de la
    // proteccion tiene el bus es EL quien direcciona (ROM -> paleta). Con `!ASn` basta para el 68k
    // porque mientras el blitter opera la CPU esta estancada con ASn BAJO.
    if( !ASn ) begin
        rom_cs      = eff_addr[23:20]==4'h0;          // 000000-0FFFFF ROM (prog+datos)
        // ⚠ `& ~BUSn` OBLIGATORIO, y SOLO aqui (igual que cowboys, cowboys_main.v:155). La work RAM
        // es la unica RW que vive en SDRAM: el slot del banco captura `wrmask` = `ram_dsn` en el
        // instante en que ve `cs & wen`. El 68000 baja AS MEDIO CICLO ANTES que UDS/LDS, asi que con
        // el cs colgado solo de ASn hay una ventana con cs=1, we=1 y dsn=11 (= "no escribas ningun
        // byte"): el slot da la escritura por servida con la mascara vacia y su cache `expected`
        // conserva el valor viejo.
        // MEDIDO: el test de RAM del POST (0x5088 desde 0x4e94) fallaba SOLO en el byte alto —
        // lee la tabla de bits en 0x5264+D5 con D5=0 y D5=2, que son los dos bytes del lane UDS —
        // y el 68k se quedaba en el bucle de error 0x5030. Las demas RW (oram/eram/pal/vram) NO
        // necesitan esto porque son BRAM y ya gatean con `we = cs & cpu_we & ~ram_dsn`; por eso el
        // test de 0x180000 pasaba y este no.
        ram_cs      = (eff_addr[23:15]==9'h20) & ~eff_busn; // 100000-107FFF work RAM (32KB)
        oram_cs     = eff_addr[23:11]==13'h300;       // 180000-1807FF K053245 spr-RAM
        // 180800-180FFF: RAM DE VERDAD, no un mirror del spr-RAM (asterix.cpp:300 `map(...).ram()`).
        // MEDIDO: el test de RAM del POST (0x5088, llamado desde 0x4eae con A0=0x180000 y D0=0) barre
        // los 4 KB 0x180000-0x180FFF de una tacada. Sin este decode la mitad alta no existia -> el
        // patron incremental (0x10203 + 0x4040404) no se releia -> D7 |= bits -> `bne $5030` = cuelgue.
        eram_cs     = eff_addr[23:11]==13'h301;       // 180800-180FFF RAM extra (2 KB)
        pal_cs      = eff_addr[23:12]==12'h280;       // 280000-280FFF paleta
        objreg_cs   = (eff_addr[23:4]==20'h20000) |   // 200000-20000F K053244 regs (word)
                      (eff_addr[23:5]==19'h18000);    // 300000-30001F K053244 regs (byte, umask 00ff)
        objreg_byte = eff_addr[23:5]==19'h18000;
        vram_cs     = eff_addr[23:12]==12'h400;       // 400000-400FFF K056832 VRAM
        romrd_cs    = eff_addr[23:13]==11'h210;       // 420000-421FFF tile-ROM passthrough
        tilereg_cs  = eff_addr[23:6]==18'h11000;      // 440000-44003F K056832 word_w
        io_cs       = eff_addr[23:16]==8'h38;         // 380000-38FFFF bloque de periféricos
        if( io_cs ) case( eff_addr[11:8] )
            4'h0: begin in0_cs = ~eff_addr[1]; in1_cs = eff_addr[1]; end // 380000 IN0 / 380002 IN1
            4'h1: control2_cs   = 1;                       // 380100 control2
            4'h2: sndmain_cs    = 1;                       // 380200-3 K053260 main
            4'h3: sndirq_cs     = 1;                       // 380300 sound_irq
            4'h4: spritebank_cs = 1;                       // 380400 spritebank
            4'h5: pcu_cs        = 1;                       // 380500-51F K053251
            4'h6: watchdog_cs   = 1;                       // 380600 watchdog (noprw)
            4'h7: tilereg_b_cs  = 1;                       // 380700-707 K056832 b_word_w
            4'h8: prot_cs       = 1;                       // 380800-3 proteccion (blitter de paleta)
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~eff_busn & ~|{ rom_cs, ram_cs, oram_cs, eram_cs, objreg_cs, pal_cs, vram_cs, romrd_cs,
        tilereg_cs, tilereg_b_cs, pcu_cs, spritebank_cs, prot_cs,
        in0_cs, in1_cs, control2_cs, sndmain_cs, sndirq_cs, watchdog_cs };
`endif
end

// ---------------- input ports ----------------
// Konami: bits de cabina ACTIVO-BAJO, jtframe ya los entrega asi -> DIRECTOS, sin invertir (GOTCHAS §A3).
// IN0 (asterix.cpp:332): low byte KONAMI16_LSB(1,UNKNOWN,START1) = {START1,-,B2,B1,UP,DOWN,LEFT,RIGHT};
//     bit8 COIN1, bit9 COIN2, bit10 SERVICE1 (todos ACTIVE_LOW).
// IN1 (asterix.cpp:339): low byte KONAMI16_LSB(2,...,START2); bit8 eep_do, bit9 eep_rdy, bit10 SERVICE.
// 🐞 SESION 23 — **LOS BITS 15:11 NO TIENEN LA MISMA POLARIDAD EN LOS DOS PUERTOS.** Los dos son
// `IPT_UNKNOWN` y a simple vista parecen el mismo relleno, pero asterix.cpp los declara distintos:
//     IN0: PORT_BIT( 0xf800, IP_ACTIVE_LOW,  IPT_UNKNOWN )  -> en reposo valen 1
//     IN1: PORT_BIT( 0xf800, IP_ACTIVE_HIGH, IPT_UNKNOWN )  -> en reposo valen 0
// Aqui estaban los dos a `5'h1f` (copiados de IN0). SINTOMA: el juego pasa el POST entero, salta a
// 0x6c8 y se queda **CLAVADO en 0x000c98**:
//     00c98: move.b $380002.l,D0   ; byte PAR = bits 15:8 de IN1
//     00c9e: andi.b #$8,D0         ; bit 3 del byte = **bit 11 de la palabra**
//     00ca2: bne    $c98           ; espera a que sea 0 -> con 5'h1f no lo es NUNCA
// O sea: nunca llega al attract, nunca pide musica, y el `test.wav` sale a CERO ABSOLUTO. El humo de
// audio de Fase 3 lo destapo; ninguna prueba de video podia verlo.
// ⚠ El contador `ARRANCO` (fetch de 0x6c8) SI se enciende, asi que "el juego arranca" NO basta como
// criterio: hay que mirar tambien que el PC del 68k RECORRA codigo, no que oscile en 3 direcciones.
// KONAMI16_LSB byte = {START, button3(=UNKNOWN,inactive), B2, B1, UP, DOWN, LEFT, RIGHT}.
// jtframe joystick[5:0] = {B2,B1,U,D,L,R} (activo-bajo). El slot button3 va a 1 (inactivo).
function [7:0] konami_player( input [5:0] joy, input start );
    konami_player = { start, 1'b1, joy[5:0] };  // TODO Fase 2: confirmar orden de bits vs KONAMI16_LSB
endfunction
always @(*) begin
    port_in = 16'hffff;
    if( in0_cs ) port_in = { 5'h1f, service[0], coin[1], coin[0], konami_player(joystick1, cab_1p[0]) };
    if( in1_cs ) port_in = { 5'h00, dip_test, eep_rdy, eep_do, konami_player(joystick2, cab_1p[1]) };
    if( sndmain_cs ) port_in = { 8'hff, snd2main };
    if( control2_cs) port_in = cur_control2;
end

always @(posedge clk) begin
    cpu_din <= rom_cs     ? rom_data    :
               ram_cs     ? ram_dout    :
               oram_cs    ? oram_dout   :
               eram_cs    ? eram_dout   :
               objreg_cs  ? objreg_dout :
               vram_cs    ? vram_dout   :  // K056832 ram_word_r: la VRAM se lee en words
               pal_cs     ? pal_dout    :
               (in0_cs|in1_cs|sndmain_cs|control2_cs) ? port_in : 16'hffff;
end

// ---------------- control2 (0x380100) + EEPROM ----------------
// asterix.cpp control2_w (ACCESSING_BITS_0_7): bit0 eep di, bit1 eep cs(activo-bajo), bit2 eep clk,
//   bit3/4 coin counters, bit5 select tile bank (K056832), bit6/7 coin lockout.
wire eep_di  = cur_control2[0];
// VERIFICADO (asterix.cpp:347-349): los 3 bits son IP_ACTIVE_HIGH y se escriben directos al
// eeprom_serial_er5911_device -> misma polaridad que espera jt5911 (scs activo-alto). Idem cowboys.
wire eep_cs  = cur_control2[1];
wire eep_clk = cur_control2[2];

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        cur_control2 <= 0;
        tilebank     <= 0;
    end else if( control2_cs & cpu_we & ~LDSn ) begin
        cur_control2[7:0] <= cpu_dout_68k[7:0];
        tilebank          <= cpu_dout_68k[5];   // bit5 -> K056832 m_cur_tile_bank
    end
end

// spritebank (0x380400, reset_spritebank de asterix.cpp): word completo -> K053245 code.
always @(posedge clk, posedge rst) begin
    if( rst ) spritebank <= 0;
    else if( spritebank_cs & cpu_we ) begin
        if( ~LDSn ) spritebank[ 7:0] <= cpu_dout_68k[ 7:0];
        if( ~UDSn ) spritebank[15:8] <= cpu_dout_68k[15:8];
    end
end

// sound IRQ trigger: escritura a 0x380300 -> HOLD_LINE al Z80
always @(posedge clk, posedge rst) begin
    if( rst ) sndon <= 0;
    else      sndon <= sndirq_cs & cpu_we;
end

// ---------------- interrupts: SOLO IRQ5 (vblank), enmascarada por el K056832 ----------------
// asterix.cpp interrupt(): if(!k056832->is_irq_enabled(0)) return; set_input_line(5,HOLD_LINE).
// (Un unico vector; no hay IRQ4/dmaend como en moomesa.)
wire irq5_edge = ~LVBL;                 // entrada a vblank
wire irq5_q;
wire irq5_ack  = iack & (A[3:1]==3'd5);
jtframe_edge #(.QSET(1)) u_irq5(
    .rst( rst ), .clk( clk ), .edgeof( irq5_edge ), .clr( ~irq_en | irq5_ack ), .q( irq5_q ));
always @(posedge clk) IPLn <= irq5_q ? 3'b010 : 3'b111;

// ================= proteccion 0x380800 = BLITTER DE PALETA (bus master) =================
// Spec EXACTA = research/mame/asterix.cpp:256-292 (asterix_state::protection_w):
//   m_prot[0..1] en 0x380800/0x380802 (COMBINE_DATA). Escribir el offset 1 DISPARA:
//     cmd = (prot[0]<<16) | prot[1]
//     if( cmd>>24 == 0x64 ) {
//        param1 = rd(cmd&ffffff)<<16 | rd(cmd&ffffff +2)
//        param2 = rd(cmd&ffffff +4)<<16 | rd(cmd&ffffff +6)
//        if( param1>>24 == 0x22 ) { size=param2>>24; src=param1&ffffff; dst=param2&ffffff;
//                                   while(size>=0){ wr(dst,rd(src)); src+=2; dst+=2; size--; } }
//     }
//   O sea size+1 WORDS. Cualquier otro cmd/param no hace NADA (los `switch` no tienen default).
//
// 🔴 SESION 26 — POR QUE ESTO NO ERA UN "EXTRA DE FASE 4": ES EL QUE PINTA LOS COLORES.
// Hasta ahora aqui solo se latcheaban los dos words (stub) y en la PLACA se veia la aldea gala con
// "suelo rojo, cielo verde". El tap sobre MAME (`tools/mame_prottap.lua`, 3300 frames de attract)
// dice que las 383 copias que dispara el juego son TODAS `ROM -> 0x280000` (paleta), ninguna a otro
// sitio, y la PRIMERA cae en el frame 619 — justo al entrar la aldea — copiando 128 words a
// 0x280000, o sea los colores 0..127 = exactamente el rango del plano 0 del fondo (CI0 base 0).
// Sin blitter la paleta se queda en lo que hubiera antes; y las escenas cuyo palette llega SOLO por
// aqui se quedan a 0 = NEGRO (el "luego negro" que se veia). Verdad-terreno del tap:
//   f619  COPY 0bf5d4 -> 280000 words=128   [bloque de parametros en 0x104258 = work RAM]
//   f1102 COPY 0bf5d4 -> 280200 words=128 / 0bf734 -> 280000 words=32 / 0bea94 -> 280800 words=32
// Regiones que el blitter toca de verdad: parametros en work RAM, origen en ROM, destino en paleta.
//
// ⚠ TRAMPA DEL BUS (jtframe_ram_rq): solo lanza peticion en el FLANCO DE SUBIDA de cs y mantiene
// data_ok mientras cs siga alto. El 68k estancado mantiene ASn/BUSn BAJOS todo el rato, asi que el
// blitter NO puede reusarlos: genera su PROPIO strobe (blt_stb) y BAJA cs entre accesos. Sin eso
// rom_ok se quedaria pegado a 1 del acceso anterior y leeriamos 128 veces el mismo word.
localparam [2:0] BLT_IDLE=3'd0, BLT_PRM=3'd1, BLT_RD=3'd2, BLT_WR=3'd3, BLT_STEP=3'd4;

reg  [15:0] prot[0:1];
reg  [23:1] blt_prma, blt_src, blt_dst, blt_addr_r;
reg  [63:0] blt_prm;        // los 4 words del bloque de parametros, w0 el mas antiguo
reg  [15:0] blt_dout_r;
reg  [ 8:0] blt_cnt;        // words que QUEDAN (arranca en size; se copia mientras cnt>=0)
reg  [ 2:0] blt_st;
reg  [ 1:0] blt_pidx, blt_wc;
reg         blt_busy_r, blt_we_r, blt_stb_r, blt_ph, blt_served;

// COMBINE_DATA: MAME calcula `cmd` DESPUES de escribir el word, asi que el disparo tiene que ver el
// valor NUEVO de prot[1] — y prot[1] no se registra hasta este mismo flanco. prot[0] SI esta
// asentado (lo escribe el ciclo de bus anterior del `move.l`), asi que ese se lee del registro.
wire [15:0] prot1_nx = { UDSn ? prot[1][15:8] : cpu_dout_68k[15:8],
                         LDSn ? prot[1][ 7:0] : cpu_dout_68k[ 7:0] };
wire [23:0] blt_cmda = { prot[0][7:0], prot1_nx };          // cmd & 0xffffff

// Trigger COMBINACIONAL: el estancamiento tiene que entrar en el MISMO ciclo en que el 68k decodifica
// la escritura; si esperasemos un ciclo, DTACKn podria asertarse antes y la CPU completaria el ciclo
// mientras el blitter le muxea la direccion bajo los pies.
// `blt_served` impide RE-disparar: al acabar, el 68k sigue en el mismo ciclo de bus (prot_cs y we
// siguen activos) -> sin el latch el blitter se relanzaria para siempre.
// Si cmd>>24 != 0x64 NO se dispara ni se estanca: MAME no hace nada y el 68k debe seguir.
wire blt_trig = prot_cs & eff_we & ~eff_busn & eff_addr[1] &
                (prot[0][15:8]==8'h64) & ~blt_served;
assign blt_stall = blt_busy_r | blt_trig;
assign blt_busy  = blt_busy_r;
assign blt_we    = blt_we_r;
assign blt_stb   = blt_stb_r;
assign blt_addr  = blt_addr_r;
assign blt_dout  = blt_dout_r;

// Destino del acceso ACTUAL del blitter (mismo decode que el principal). Soportadas las 3 regiones
// que el tap ve usadas: ROM (origen), work RAM (parametros) y paleta (destino). Cualquier otra
// region lee 0 y la sonda BLT-RANGO de abajo la CANTA (no falla en silencio).
wire blt_isrom = blt_addr_r[23:20]==4'h0;      // 000000-0FFFFF ROM
wire blt_isram = blt_addr_r[23:15]==9'h20;     // 100000-107FFF work RAM
wire blt_ispal = blt_addr_r[23:12]==12'h280;   // 280000-280FFF paleta
wire [15:0] blt_rdata = blt_isram ? ram_dout : blt_isrom ? rom_data : pal_dout;
// SDRAM: handshake real (ram_ok/rom_ok). Paleta: es BRAM del colmix (q0 registrado, ~1 clk) y no
// tiene handshake -> espera fija holgada de 4 ciclos. Coste peor caso 128x(rd+wr): unos pocos us.
wire blt_rdy   = blt_isram ? ram_ok : blt_isrom ? rom_ok : (blt_wc==2'd3);
wire [63:0] blt_prm_nx = { blt_prm[47:0], blt_rdata };   // bloque con el word que entra AHORA

integer bi;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        blt_st <= BLT_IDLE; blt_busy_r <= 0; blt_we_r <= 0; blt_stb_r <= 0; blt_ph <= 0;
        blt_served <= 0; blt_wc <= 0; blt_pidx <= 0; blt_cnt <= 0; blt_prm <= 0;
        blt_prma <= 0; blt_src <= 0; blt_dst <= 0; blt_addr_r <= 0; blt_dout_r <= 0;
        for( bi=0; bi<2; bi=bi+1 ) prot[bi] <= 0;
    end else begin
        // prot[]: escritura A NIVEL (direccion y dato ASENTADOS), no por flanco. Durante el blitter
        // prot_cs=0 (eff_addr ya no apunta ahi) -> no se corrompe.
        if( prot_cs & eff_we & ~eff_busn ) begin
            if( !LDSn ) prot[eff_addr[1]][ 7:0] <= cpu_dout_68k[ 7:0];
            if( !UDSn ) prot[eff_addr[1]][15:8] <= cpu_dout_68k[15:8];
        end
        if( BUSn ) blt_served <= 0; else if( blt_trig ) blt_served <= 1;

        case( blt_st )
            BLT_IDLE: begin
                blt_stb_r <= 0; blt_we_r <= 0; blt_ph <= 0; blt_busy_r <= 0;
                if( blt_trig ) begin
                    blt_prma   <= blt_cmda[23:1];
                    blt_pidx   <= 0;
                    blt_busy_r <= 1;
                    blt_st     <= BLT_PRM;
                end
            end
            // Cada acceso = 2 fases. ph=0: cs BAJO (fuerza el toggle que exige jtframe_ram_rq y
            // limpia data_ok del acceso anterior) y coloca la direccion. ph=1: cs alto, esperar rdy.
            //
            // 4 lecturas seguidas: param1={w0,w1}, param2={w2,w3}.
            BLT_PRM: if( !blt_ph ) begin
                blt_addr_r <= blt_prma + {21'd0,blt_pidx};
                blt_we_r <= 0; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    blt_prm   <= blt_prm_nx;
                    blt_stb_r <= 0; blt_ph <= 0;
                    if( blt_pidx==2'd3 ) begin
                        // ⚠ decidir con blt_prm_nx, NO con blt_prm: el 4o word aun no esta registrado.
                        blt_src <= blt_prm_nx[55:33];        // param1 & 0xffffff -> word addr
                        blt_dst <= blt_prm_nx[23: 1];        // param2 & 0xffffff -> word addr
                        blt_cnt <= {1'b0, blt_prm_nx[31:24]};// size = param2>>24  (=> size+1 words)
                        if( blt_prm_nx[63:56]==8'h22 ) begin
                            blt_st <= BLT_RD;
                        end else begin                        // param1>>24 != 0x22 -> MAME no copia
                            blt_busy_r <= 0; blt_st <= BLT_IDLE;
                        end
                    end else blt_pidx <= blt_pidx + 2'd1;
                end
            end
            BLT_RD: if( !blt_ph ) begin
                blt_addr_r <= blt_src; blt_we_r <= 0; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    blt_dout_r <= blt_rdata;
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
                blt_src <= blt_src + 1'd1;   // +2 bytes = +1 word
                blt_dst <= blt_dst + 1'd1;
                blt_cnt <= blt_cnt - 1'd1;
                // `while(size>=0)` = size+1 iteraciones: se para DESPUES de copiar con cnt==0.
                if( blt_cnt==9'd0 ) begin blt_busy_r <= 0; blt_st <= BLT_IDLE; end
                else                      blt_st <= BLT_RD;
            end
            default: blt_st <= BLT_IDLE;
        endcase
    end
end

`ifdef SIMULATION
// Testigo del blitter: distingue "no dispara" (decode/trigger mal) de "dispara pero copia mal".
// Se contrasta LINEA A LINEA con `debug/mame_prot_trace.txt` (mismo formato: origen -> destino y
// numero de words), que es la verdad-terreno medida sobre MAME.
integer n_blt=0, n_bad=0;
reg blt_busy_l=0;
always @(posedge clk) begin
    blt_busy_l <= blt_busy_r;
    if( blt_trig )
        $display("PROT: TRIGGER cmd=%02x%06x (bloque de parametros en %06x)",
                 prot[0][15:8], blt_cmda, {blt_cmda[23:1],1'b0});
    if( blt_st==BLT_PRM && blt_pidx==2'd3 && blt_ph && blt_rdy ) begin
        if( blt_prm_nx[63:56]==8'h22 ) begin
            n_blt <= n_blt+1;
            $display("PROT: COPY %06x -> %06x  words=%0d",
                     {blt_prm_nx[55:33],1'b0}, {blt_prm_nx[23:1],1'b0}, blt_prm_nx[31:24]+1);
        end else
            $display("PROT: cmd 0x64 pero param1>>24=%02x (!=22) -> no se copia nada",
                     blt_prm_nx[63:56]);
    end
    // ⚠ El blitter solo sabe leer ROM / work RAM / paleta. Si algun dia apunta a otra region
    // leeria 0 en SILENCIO -> se canta aqui en vez de aparecer disfrazado 20 frames despues.
    if( blt_busy_r && blt_stb_r && !blt_isrom && !blt_isram && !blt_ispal && n_bad<16 ) begin
        n_bad <= n_bad+1;
        $display("PROT-RANGO[%0d]: acceso del blitter FUERA de rom/ram/paleta A=%06x we=%b",
                 n_bad, {blt_addr_r,1'b0}, blt_we_r);
    end
    if( ~blt_busy_r & blt_busy_l )
        $display("PROT: fin (copias acumuladas=%0d)", n_blt);
end
`endif

// pausa via HALTn
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
    .num        ( 5'd1      ),  // 12MHz = 48/4  -> num/den por calibrar en Fase 2
    .den        ( 6'd4      ),
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
`else // NOMAIN: stub para sims de solo-video
    initial begin
        rom_cs=0; ram_cs=0; oram_cs=0; eram_cs=0; objreg_cs=0; objreg_byte=0; pal_cs=0; vram_cs=0;
        tilereg_cs=0; tilereg_b_cs=0; romrd_cs=0; pcu_cs=0; spritebank_cs=0; prot_cs=0;
        sndon=0; tilebank=0; spritebank=0;
    end
    assign cpu_dout=0, cpu_we=0, main_addr=0, ram_dsn=0, snd_wrn=1, snd_dout=0,
           st_dout=0, nv_addr=0, nv_din=0, nv_we=0;
`endif
endmodule
