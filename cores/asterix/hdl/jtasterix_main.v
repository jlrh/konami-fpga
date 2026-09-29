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
    input                clk,
    input                LVBL,
    input                irq_en,

    output        [19:1] main_addr,
    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,
    output               cpu_we,

    output reg           rom_cs,
    output reg           ram_cs,
    output reg           oram_cs,
    output reg           eram_cs,
    output reg           objreg_cs,
    output reg           objreg_byte,
    output reg           pal_cs,
    output reg           vram_cs,
    output reg           tilereg_cs,
    output reg           tilereg_b_cs,
    output reg           romrd_cs,
    output reg           pcu_cs,
    output reg           spritebank_cs,
    output reg           prot_cs,

    output               snd_wrn,
    output        [ 7:0] snd_dout,
    input         [ 7:0] snd2main,
    output reg           sndon,

    input         [15:0] oram_dout,
    input         [15:0] eram_dout,
    input         [15:0] objreg_dout,
    input         [15:0] vram_dout,
    input         [15:0] pal_dout,
    input         [15:0] ram_dout,
    input         [15:0] rom_data,
    input                ram_ok,
    input                rom_ok,
    input                vdtac,

    output      [ 6:0]   nv_addr,
    input       [ 7:0]   nv_dout,
    output      [ 7:0]   nv_din,
    output               nv_we,

    output reg           tilebank,
    output reg   [15:0]  spritebank,

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
reg  [15:0] cur_control2;
wire        eep_rdy, eep_do, bus_cs, bus_busy, BUSn;
wire        dtac_mux, iack;
wire [15:0] cpu_dout_68k;

wire [23:1] blt_addr;
wire [15:0] blt_dout;
wire        blt_busy, blt_we, blt_stb, blt_stall;
wire [23:1] eff_addr = blt_busy ? blt_addr : A;
wire        eff_busn = blt_busy ? ~blt_stb : BUSn;
wire        eff_we   = blt_busy ?  blt_we  : ~RnW;
wire [ 1:0] eff_dsn  = blt_busy ? 2'b00    : {UDSn,LDSn};

reg  io_cs, in0_cs, in1_cs, control2_cs, sndmain_cs, sndirq_cs, watchdog_cs;
reg  [15:0] port_in;

assign main_addr= eff_addr[19:1];
assign ram_dsn  = eff_dsn;

assign bus_cs   = (rom_cs | ram_cs) & ~blt_busy;
assign bus_busy = ((rom_cs & ~rom_ok) | (ram_cs & ~ram_ok)) & ~blt_busy;
assign BUSn     = ASn | (LDSn & UDSn);
assign cpu_we   = eff_we;
assign cpu_dout = blt_busy ? blt_dout : cpu_dout_68k;
assign st_dout  = { tilebank, cur_control2[5:0], 1'b0 };

assign VPAn     = ~(&FC & ~ASn);
assign iack     =  &FC & ~ASn;

assign dtac_mux = DTACKn | ~vdtac | blt_stall;

assign snd_wrn  = ~(sndmain_cs & ~RnW & ~LDSn);
assign snd_dout = cpu_dout_68k[7:0];

`ifdef SIMULATION
reg none_cs;

integer n_none=0;
always @(posedge clk) if( none_cs ) begin
    n_none <= n_none+1;
    if( n_none<32 || n_none%100000==0 )
        $display("MAIN-NONE[%0d]: acceso SIN decode A=%06x RnW=%b (devuelve 0xffff)", n_none, {A,1'b0}, RnW);
end

reg [15:0] shadow[0:16383];
reg        wrote [0:16383];
integer    si;
initial for(si=0;si<16384;si=si+1) wrote[si]=0;
integer n_mis=0;
reg busn_dl=1;
always @(posedge clk) begin
    busn_dl <= BUSn;

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

always @(posedge clk) if( vram_cs & cpu_we & ~BUSn & cpu_dout_68k==16'h4012 )
    $display("MAIN-POST-NG: marcador de FALLO en VRAM %06x (tabla 0x27ef6 -> esa entrada del test)", {A,1'b0});

integer n_rd=0;
always @(posedge clk) if( rom_cs && rom_ok && !ASn && !blt_busy ) begin
    if( n_rd < 24 ) begin
        n_rd <= n_rd+1;
        $display("MAIN-RD[%0d] A=%06x data=%04x rom_ok=%b", n_rd, {A,1'b0}, rom_data, rom_ok);
    end
end

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

integer n_pc=0, n_post=0, n_hang=0, n_game=0, n_vec=0, n_test=0;
reg [23:1] amax=0;
reg        arranco=0;
always @(posedge clk) begin
    if( rom_cs && !blt_busy ) begin
        n_pc <= n_pc+1;
        if( A[23:1] > amax ) amax <= A[23:1];
        if     ( A[23:1] <  23'h200 )                        n_vec  <= n_vec+1;
        else if( A[23:1]>=23'h2818 && A[23:1]<=23'h2826 )     n_hang <= n_hang+1;
        else if( A[23:1] <  23'h2818 )                        n_post <= n_post+1;
        else                                                  n_test <= n_test+1;

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

    if( !ASn ) begin
        rom_cs      = eff_addr[23:20]==4'h0;

        ram_cs      = (eff_addr[23:15]==9'h20) & ~eff_busn;
        oram_cs     = eff_addr[23:11]==13'h300;

        eram_cs     = eff_addr[23:11]==13'h301;
        pal_cs      = eff_addr[23:12]==12'h280;
        objreg_cs   = (eff_addr[23:4]==20'h20000) |
                      (eff_addr[23:5]==19'h18000);
        objreg_byte = eff_addr[23:5]==19'h18000;
        vram_cs     = eff_addr[23:12]==12'h400;
        romrd_cs    = eff_addr[23:13]==11'h210;
        tilereg_cs  = eff_addr[23:6]==18'h11000;
        io_cs       = eff_addr[23:16]==8'h38;
        if( io_cs ) case( eff_addr[11:8] )
            4'h0: begin in0_cs = ~eff_addr[1]; in1_cs = eff_addr[1]; end
            4'h1: control2_cs   = 1;
            4'h2: sndmain_cs    = 1;
            4'h3: sndirq_cs     = 1;
            4'h4: spritebank_cs = 1;
            4'h5: pcu_cs        = 1;
            4'h6: watchdog_cs   = 1;
            4'h7: tilereg_b_cs  = 1;
            4'h8: prot_cs       = 1;
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~eff_busn & ~|{ rom_cs, ram_cs, oram_cs, eram_cs, objreg_cs, pal_cs, vram_cs, romrd_cs,
        tilereg_cs, tilereg_b_cs, pcu_cs, spritebank_cs, prot_cs,
        in0_cs, in1_cs, control2_cs, sndmain_cs, sndirq_cs, watchdog_cs };
`endif
end

function [7:0] konami_player( input [5:0] joy, input start );
    konami_player = { start, 1'b1, joy[5:0] };
endfunction

`ifdef BOOTPROBE_FORCE_TEST
wire dip_test_eff = 1'b1;
`elsif BOOTPROBE_FORCE_NORMAL
wire dip_test_eff = 1'b0;
`else
wire dip_test_eff = dip_test;
`endif
always @(*) begin
    port_in = 16'hffff;
    if( in0_cs ) port_in = { 5'h1f, service[0], coin[1], coin[0], konami_player(joystick1, cab_1p[0]) };
    if( in1_cs ) port_in = { 5'h00, dip_test_eff, eep_rdy, eep_do, konami_player(joystick2, cab_1p[1]) };
    if( sndmain_cs ) port_in = { 8'hff, snd2main };
    if( control2_cs) port_in = cur_control2;
end
`ifdef BOOTPROBE
reg [31:0] bootprobe_cyc;
reg        bootprobe_seen, bootprobe_wseen, bootprobe_iseen;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bootprobe_cyc   <= 0;
        bootprobe_seen  <= 0;
        bootprobe_wseen <= 0;
        bootprobe_iseen <= 0;
    end else begin
        bootprobe_cyc <= bootprobe_cyc + 1'd1;
        if( sndmain_cs && !cpu_we && !bootprobe_seen ) begin
            bootprobe_seen <= 1;
            $display("BOOTPROBE 68k first sndmain_cs READ: cyc=%0d dip_test=%b snd2main=%02x", bootprobe_cyc, dip_test_eff, snd2main);
        end
        if( !snd_wrn && !bootprobe_wseen ) begin
            bootprobe_wseen <= 1;
            $display("BOOTPROBE 68k first main->sub WRITE: cyc=%0d dip_test=%b snd_dout=%02x", bootprobe_cyc, dip_test_eff, snd_dout);
        end
        if( sndon && !bootprobe_iseen ) begin
            bootprobe_iseen <= 1;
            $display("BOOTPROBE 68k first sound IRQ (sndon): cyc=%0d dip_test=%b", bootprobe_cyc, dip_test_eff);
        end
    end
end
`endif

always @(posedge clk) begin
    cpu_din <= rom_cs     ? rom_data    :
               ram_cs     ? ram_dout    :
               oram_cs    ? oram_dout   :
               eram_cs    ? eram_dout   :
               objreg_cs  ? objreg_dout :
               vram_cs    ? vram_dout   :
               pal_cs     ? pal_dout    :
               (in0_cs|in1_cs|sndmain_cs|control2_cs) ? port_in : 16'hffff;
end

wire eep_di  = cur_control2[0];

wire eep_cs  = cur_control2[1];
wire eep_clk = cur_control2[2];

`ifdef EEPCUTPROBE
reg [31:0] eepcut_cyc;
reg        eepcut_cs_l, eepcut_clk_l;
reg [15:0] eepcut_bitcnt;
reg [15:0] eepcut_sesscnt;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        eepcut_cyc     <= 0;
        eepcut_cs_l    <= 0;
        eepcut_clk_l   <= 0;
        eepcut_bitcnt  <= 0;
        eepcut_sesscnt <= 0;
        $display("EEPCUTPROBE RST_ASSERT (state machine + control2 + jt5911 vuelven a limpio)");
    end else begin
        eepcut_cyc   <= eepcut_cyc + 1'd1;
        eepcut_cs_l  <= eep_cs;
        eepcut_clk_l <= eep_clk;
        if( eep_cs && !eepcut_cs_l ) begin
            eepcut_bitcnt  <= 0;
            eepcut_sesscnt <= eepcut_sesscnt + 1'd1;
            $display("EEPCUTPROBE cyc=%0d CS_OPEN sess=%0d di=%b jt5911.st=%0d jt5911.rdy=%b",
                eepcut_cyc, eepcut_sesscnt+1'd1, eep_di, u_eeprom.st, u_eeprom.rdy);
        end
        if( eep_clk && !eepcut_clk_l && eep_cs ) begin
            eepcut_bitcnt <= eepcut_bitcnt + 1'd1;
            $display("EEPCUTPROBE cyc=%0d CLK sess=%0d bit=%0d di=%b jt5911.st=%0d jt5911.rx_cnt=%0d jt5911.mem_we=%b jt5911.mem_addr=%0d jt5911.prog_en=%b",
                eepcut_cyc, eepcut_sesscnt, eepcut_bitcnt+1'd1, eep_di,
                u_eeprom.st, u_eeprom.rx_cnt, u_eeprom.mem_we, u_eeprom.mem_addr, u_eeprom.prog_en);
        end
        if( !eep_cs && eepcut_cs_l ) begin
            $display("EEPCUTPROBE cyc=%0d CS_CLOSE sess=%0d nbits=%0d jt5911.st=%0d jt5911.rdy=%b",
                eepcut_cyc, eepcut_sesscnt, eepcut_bitcnt, u_eeprom.st, u_eeprom.rdy);
        end
    end
end
`endif

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        cur_control2 <= 0;
        tilebank     <= 0;
    end else if( control2_cs & cpu_we & ~LDSn ) begin
        cur_control2[7:0] <= cpu_dout_68k[7:0];
        tilebank          <= cpu_dout_68k[5];
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) spritebank <= 0;
    else if( spritebank_cs & cpu_we ) begin
        if( ~LDSn ) spritebank[ 7:0] <= cpu_dout_68k[ 7:0];
        if( ~UDSn ) spritebank[15:8] <= cpu_dout_68k[15:8];
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) sndon <= 0;
    else      sndon <= sndirq_cs & cpu_we;
end

wire irq5_edge = ~LVBL;
wire irq5_q;
wire irq5_ack  = iack & (A[3:1]==3'd5);
jtframe_edge #(.QSET(1)) u_irq5(
    .rst( rst ), .clk( clk ), .edgeof( irq5_edge ), .clr( ~irq_en | irq5_ack ), .q( irq5_q ));
always @(posedge clk) IPLn <= irq5_q ? 3'b010 : 3'b111;

localparam [2:0] BLT_IDLE=3'd0, BLT_PRM=3'd1, BLT_RD=3'd2, BLT_WR=3'd3, BLT_STEP=3'd4;

reg  [15:0] prot[0:1];
reg  [23:1] blt_prma, blt_src, blt_dst, blt_addr_r;
reg  [63:0] blt_prm;
reg  [15:0] blt_dout_r;
reg  [ 8:0] blt_cnt;
reg  [ 2:0] blt_st;
reg  [ 1:0] blt_pidx, blt_wc;
reg         blt_busy_r, blt_we_r, blt_stb_r, blt_ph, blt_served;

wire [15:0] prot1_nx = { UDSn ? prot[1][15:8] : cpu_dout_68k[15:8],
                         LDSn ? prot[1][ 7:0] : cpu_dout_68k[ 7:0] };
wire [23:0] blt_cmda = { prot[0][7:0], prot1_nx };

wire blt_trig = prot_cs & eff_we & ~eff_busn & eff_addr[1] &
                (prot[0][15:8]==8'h64) & ~blt_served;
assign blt_stall = blt_busy_r | blt_trig;
assign blt_busy  = blt_busy_r;
assign blt_we    = blt_we_r;
assign blt_stb   = blt_stb_r;
assign blt_addr  = blt_addr_r;
assign blt_dout  = blt_dout_r;

wire blt_isrom = blt_addr_r[23:20]==4'h0;
wire blt_isram = blt_addr_r[23:15]==9'h20;
wire blt_ispal = blt_addr_r[23:12]==12'h280;
wire [15:0] blt_rdata = blt_isram ? ram_dout : blt_isrom ? rom_data : pal_dout;

wire blt_rdy   = blt_isram ? ram_ok : blt_isrom ? rom_ok : (blt_wc==2'd3);
wire [63:0] blt_prm_nx = { blt_prm[47:0], blt_rdata };

integer bi;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        blt_st <= BLT_IDLE; blt_busy_r <= 0; blt_we_r <= 0; blt_stb_r <= 0; blt_ph <= 0;
        blt_served <= 0; blt_wc <= 0; blt_pidx <= 0; blt_cnt <= 0; blt_prm <= 0;
        blt_prma <= 0; blt_src <= 0; blt_dst <= 0; blt_addr_r <= 0; blt_dout_r <= 0;
        for( bi=0; bi<2; bi=bi+1 ) prot[bi] <= 0;
    end else begin

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

            BLT_PRM: if( !blt_ph ) begin
                blt_addr_r <= blt_prma + {21'd0,blt_pidx};
                blt_we_r <= 0; blt_wc <= 0; blt_stb_r <= 1; blt_ph <= 1;
            end else begin
                blt_wc <= blt_wc + 2'd1;
                if( blt_rdy ) begin
                    blt_prm   <= blt_prm_nx;
                    blt_stb_r <= 0; blt_ph <= 0;
                    if( blt_pidx==2'd3 ) begin

                        blt_src <= blt_prm_nx[55:33];
                        blt_dst <= blt_prm_nx[23: 1];
                        blt_cnt <= {1'b0, blt_prm_nx[31:24]};
                        if( blt_prm_nx[63:56]==8'h22 ) begin
                            blt_st <= BLT_RD;
                        end else begin
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
                blt_src <= blt_src + 1'd1;
                blt_dst <= blt_dst + 1'd1;
                blt_cnt <= blt_cnt - 1'd1;

                if( blt_cnt==9'd0 ) begin blt_busy_r <= 0; blt_st <= BLT_IDLE; end
                else                      blt_st <= BLT_RD;
            end
            default: blt_st <= BLT_IDLE;
        endcase
    end
end

`ifdef SIMULATION

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

    if( blt_busy_r && blt_stb_r && !blt_isrom && !blt_isram && !blt_ispal && n_bad<16 ) begin
        n_bad <= n_bad+1;
        $display("PROT-RANGO[%0d]: acceso del blitter FUERA de rom/ram/paleta A=%06x we=%b",
                 n_bad, {blt_addr_r,1'b0}, blt_we_r);
    end
    if( ~blt_busy_r & blt_busy_l )
        $display("PROT: fin (copias acumuladas=%0d)", n_blt);
end
`endif

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
    .num        ( 5'd1      ),
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
`else
    initial begin
        rom_cs=0; ram_cs=0; oram_cs=0; eram_cs=0; objreg_cs=0; objreg_byte=0; pal_cs=0; vram_cs=0;
        tilereg_cs=0; tilereg_b_cs=0; romrd_cs=0; pcu_cs=0; spritebank_cs=0; prot_cs=0;
        sndon=0; tilebank=0; spritebank=0;
    end
    assign cpu_dout=0, cpu_we=0, main_addr=0, ram_dsn=0, snd_wrn=1, snd_dout=0,
           st_dout=0, nv_addr=0, nv_din=0, nv_we=0;
`endif
endmodule
