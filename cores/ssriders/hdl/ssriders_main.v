/*  ssriders — CPU principal 68000 y mapa de memoria.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module ssriders_main(
    input                rst,
    input                clk,
    input                LVBL,

    output        [19:1] main_addr,
    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,
    output               cpu_we,

    output reg           rom_cs,
    output reg           ram_cs,
    output reg           pal_cs,
    output reg           oram_cs,
    output reg           objreg_cs,
    output reg           tile_cs,
    output reg           pcu_cs,
    output reg           prot_cs,
    output reg           watchdog_cs,
    output reg           ram1c05_cs,

    input                prot_brn,
    input                prot_bgackn,
    output               BGn,
    input         [15:0] prot_dout,

    output               snd_wrn,
    output        [ 7:0] snd_dout,
    input         [ 7:0] snd2main,
    output reg           sndirq,

    input         [15:0] oram_dout,
    input         [15:0] objreg_dout,
    input         [15:0] tile_dout,
    input         [15:0] ram1c05_dout,
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

    output reg           rmrd,
    output reg   [ 2:0]  dim_v,
    output reg   [ 1:0]  dim_c,
    output reg           objtest_bank,

    input                tile_irqn,

    input         [ 5:0] joystick1,
    input         [ 5:0] joystick2,
    input         [ 5:0] joystick3,
    input         [ 5:0] joystick4,
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
wire        eep_rdy, eep_do, bus_cs, bus_busy, BUSn;
wire        dtac_mux, iack;
wire [15:0] cpu_dout_68k;

assign main_addr = A[19:1];
assign ram_dsn   = {UDSn,LDSn};
assign bus_cs    = rom_cs | ram_cs;
assign bus_busy  = (rom_cs & ~rom_ok) | (ram_cs & ~ram_ok);
assign BUSn      = ASn | (LDSn & UDSn);
assign cpu_we    = ~RnW;
assign cpu_dout  = cpu_dout_68k;

reg [7:0] n_bgack=0, n_bgack_mid=0, n_bgack_lost=0;
reg       bgackn_l=1'b1;
wire      bgack_take     = bgackn_l && !prot_bgackn;
wire      bgack_evt_mid  = bgack_take && !ASn;
wire      bgack_evt_lost = bgack_evt_mid && cpu_we && oram_cs;

always @(posedge clk) begin
    if( rst ) begin
        n_bgack <= 0; n_bgack_mid <= 0; n_bgack_lost <= 0; bgackn_l <= 1'b1;
    end else begin
        bgackn_l <= prot_bgackn;
        if( bgack_take     && !(&n_bgack)     ) n_bgack     <= n_bgack     + 8'd1;
        if( bgack_evt_mid  && !(&n_bgack_mid) ) n_bgack_mid <= n_bgack_mid + 8'd1;
        if( bgack_evt_lost && !(&n_bgack_lost)) n_bgack_lost<= n_bgack_lost+ 8'd1;
    end
end

assign st_dout   = debug_bus[2:0]==3'd0 ? n_bgack_lost   :
                   debug_bus[2:0]==3'd1 ? n_bgack_mid    :
                   debug_bus[2:0]==3'd2 ? n_bgack        :
                   debug_bus[2:0]==3'd3 ? { 5'd0, dim_v } :

                   debug_bus[2:0]==3'd4 ? { 6'd0, dim_c } :
                   8'd0;
assign VPAn      = ~(&FC & ~ASn);
assign iack      =  &FC & ~ASn;
assign dtac_mux  = DTACKn | ~vdtac;

assign snd_wrn   = ~(sndmain_cs & ~RnW & ~LDSn);
assign snd_dout  = cpu_dout_68k[7:0];

reg  io_cs, p1_cs, p2_cs, p3_cs, p4_cs, coins_cs, eepromr_cs, eepromw_cs, unk1c0300_cs;
reg  sndmain_cs, soundkludge_cs;
reg  [15:0] port_in;

`ifdef SIMULATION

reg none_cs;
integer n_none=0;
always @(posedge clk) if( none_cs ) begin
    n_none <= n_none+1;
    if( n_none<32 || n_none%100000==0 )
        $display("MAIN-NONE[%0d]: acceso SIN decode A=%06x RnW=%b (devuelve 0xffff)", n_none, {A,1'b0}, RnW);
end

integer n_prot=0;
always @(posedge clk) if( prot_cs && !BUSn ) begin
    n_prot <= n_prot+1;
    if( n_prot<64 )
        $display("MAIN-PROT[%0d]: A=%06x RnW=%b dout=%04x din=%04x", n_prot, {A,1'b0}, RnW, prot_dout, cpu_dout_68k);
end

integer n_rd=0;
integer n_seq=0;
reg [31:0] boot_sp, boot_pc;
reg [23:1] last_rdA = 23'h7fffff;

integer abs_cyc = 0;
always @(posedge clk) abs_cyc <= abs_cyc + 1;
always @(posedge clk) if( rom_cs && rom_ok && !ASn ) begin
    if( n_rd < 24 ) begin
        n_rd <= n_rd+1;
        $display("MAIN-RD[%0d] abs_cyc=%0d A=%06x data=%04x rom_ok=%b", n_rd, abs_cyc, {A,1'b0}, rom_data, rom_ok);
    end
    if( A != last_rdA ) begin
        last_rdA <= A;
        case( {A,1'b0} )
            24'h000000: boot_sp[31:16] <= rom_data;
            24'h000002: boot_sp[15:0]  <= rom_data;
            24'h000004: boot_pc[31:16] <= rom_data;
            24'h000006: begin
                boot_pc[15:0] <= rom_data;
                $display("MAIN-BOOTVEC: SP=%08x PC=%08x", boot_sp, {boot_pc[31:16],rom_data});
            end
            default:;
        endcase

        if( n_seq<400 ) begin
            n_seq <= n_seq+1;
            $display("MAIN-SEQ[%0d]: A=%06x data=%04x RnW=%b", n_seq, {A,1'b0}, rom_data, RnW);
        end
    end
end

integer n_sndkludge=0;
always @(posedge clk) if( soundkludge_cs && cpu_we && n_sndkludge<20 ) begin
    n_sndkludge <= n_sndkludge+1;
    $display("MAIN-SNDKLUDGE[%0d]: abs_cyc=%0d A=%06x dout=%04x", n_sndkludge, abs_cyc, {A,1'b0}, cpu_dout_68k);
end

reg  z55_sndirq_l = 1'b0;
integer n_sndirq=0;
always @(posedge clk) begin
    z55_sndirq_l <= sndirq;
    if( sndirq !== z55_sndirq_l && n_sndirq<20 ) begin
        n_sndirq <= n_sndirq+1;
        $display("MAIN-SNDIRQ-EDGE[%0d]: sndirq %b->%b abs_cyc=%0d rst=%b soundkludge_cs=%b cpu_we=%b",
                  n_sndirq, z55_sndirq_l, sndirq, abs_cyc, rst, soundkludge_cs, cpu_we);
    end
end

integer n_hb68=0, n_wdog=0;
reg [23:1] last_hbA = 23'h7fffff;
always @(posedge clk) begin
    n_hb68 <= n_hb68 + 1;
    if( watchdog_cs && !ASn ) n_wdog <= n_wdog + 1;
    if( !ASn ) last_hbA <= A;
    if( n_hb68 % 4000000 == 0 )
        $display("MAIN-HB: A=%06x lastA=%06x RnW=%b rom_cs=%b ram_cs=%b ASn=%b BUSn=%b rst=%b abs_cyc=%0d wdog=%0d",
                  {A,1'b0}, {last_hbA,1'b0}, RnW, rom_cs, ram_cs, ASn, BUSn, rst, abs_cyc, n_wdog);
end

integer n_ramw=0, n_entry=0, n_ramr=0, n_romseq2=0;
reg entry_hit_l=0, ramw_hit_l=0, ramr_hit_l=0;
reg [22:0] last_romseq2A = 23'h7fffff;
always @(posedge clk) begin
    entry_hit_l <= rom_cs && rom_ok && !ASn && RnW && A==19'h00c38;

    ramw_hit_l  <= cpu_we && !ASn && (ram_cs|oram_cs|tile_cs|pal_cs|objreg_cs|pcu_cs|ram1c05_cs|prot_cs|watchdog_cs);

    if( rom_cs && rom_ok && !ASn && RnW && A==19'h00c38 && !entry_hit_l && n_entry<40 ) begin
        n_entry <= n_entry+1;
        $display("MAIN-ENTRY[%0d]: reentrada en PC=1870 (etiqueta num %0d impresa) abs_cyc=%0d",
                  n_entry, n_entry, abs_cyc);
    end

    if( cpu_we && !ASn && (ram_cs|oram_cs|tile_cs|pal_cs|objreg_cs|pcu_cs|ram1c05_cs|prot_cs|watchdog_cs) &&
        !ramw_hit_l && abs_cyc>32'd160_000_000 && n_ramw<16000 ) begin
        n_ramw <= n_ramw+1;
        $display("MAIN-RAMW[%0d]: A=%06x data=%04x ram_cs=%b oram_cs=%b tile_cs=%b pal_cs=%b objreg_cs=%b pcu_cs=%b ram1c05_cs=%b prot_cs=%b watchdog_cs=%b abs_cyc=%0d",
                  n_ramw, {A,1'b0}, cpu_dout_68k, ram_cs, oram_cs, tile_cs, pal_cs, objreg_cs, pcu_cs, ram1c05_cs, prot_cs, watchdog_cs, abs_cyc);
    end

    ramr_hit_l <= RnW && !ASn && !dtac_mux &&
                  (ram_cs|oram_cs|tile_cs|pal_cs|objreg_cs|pcu_cs|ram1c05_cs|prot_cs|watchdog_cs|
                   p1_cs|p2_cs|p3_cs|p4_cs|coins_cs|eepromr_cs|eepromw_cs|unk1c0300_cs|sndmain_cs|soundkludge_cs);
    if( RnW && !ASn && !dtac_mux &&
        (ram_cs|oram_cs|tile_cs|pal_cs|objreg_cs|pcu_cs|ram1c05_cs|prot_cs|watchdog_cs|
         p1_cs|p2_cs|p3_cs|p4_cs|coins_cs|eepromr_cs|eepromw_cs|unk1c0300_cs|sndmain_cs|soundkludge_cs) &&

        !ramr_hit_l && abs_cyc>32'd64_900_000 && n_ramr<0 ) begin
        n_ramr <= n_ramr+1;
        $display("MAIN-RAMR[%0d]: A=%06x data=%04x ram_cs=%b oram_cs=%b tile_cs=%b pal_cs=%b objreg_cs=%b pcu_cs=%b ram1c05_cs=%b prot_cs=%b watchdog_cs=%b io=%b%b%b%b%b%b%b%b%b%b abs_cyc=%0d",
                  n_ramr, {A,1'b0}, cpu_din, ram_cs, oram_cs, tile_cs, pal_cs, objreg_cs, pcu_cs, ram1c05_cs, prot_cs, watchdog_cs,
                  p1_cs,p2_cs,p3_cs,p4_cs,coins_cs,eepromr_cs,eepromw_cs,unk1c0300_cs,sndmain_cs,soundkludge_cs, abs_cyc);
    end

    if( rom_cs && rom_ok && !ASn && RnW && A!=last_romseq2A &&

        abs_cyc>32'd64_900_000 && abs_cyc<32'd127_250_000 && n_romseq2<0 ) begin
        last_romseq2A <= A;
        n_romseq2 <= n_romseq2+1;
        $display("MAIN-ROMSEQ2[%0d]: A=%06x data=%04x abs_cyc=%0d", n_romseq2, {A,1'b0}, rom_data, abs_cyc);
    end
end

localparam RINGN = 128;
reg [22:0] ring_a [0:RINGN-1];
reg [15:0] ring_d [0:RINGN-1];
reg [ 4:0] ring_cs[0:RINGN-1];
reg        ring_rw[0:RINGN-1];
reg [31:0] ring_c [0:RINGN-1];
integer ring_wr = 0;
integer n_trapdump = 0;
reg in_trap_l = 0, ring_hit_l = 0;
integer ri;
reg s78_hit_l = 0;
integer n_s78 = 0;

reg [4:0] cs_code;
always @* begin
    cs_code = rom_cs        ? 5'd1  : ram_cs     ? 5'd2  : pal_cs        ? 5'd3  :
              oram_cs       ? 5'd4  : objreg_cs  ? 5'd5  : tile_cs       ? 5'd6  :
              pcu_cs        ? 5'd7  : ram1c05_cs ? 5'd8  : prot_cs       ? 5'd9  :
              watchdog_cs   ? 5'd10 : p1_cs      ? 5'd11 : p2_cs         ? 5'd12 :
              p3_cs         ? 5'd13 : p4_cs      ? 5'd14 : coins_cs      ? 5'd15 :
              eepromr_cs    ? 5'd16 : eepromw_cs ? 5'd17 : unk1c0300_cs  ? 5'd18 :
              sndmain_cs    ? 5'd19 : soundkludge_cs ? 5'd20 : 5'd0;
end

reg rst_l = 0, prev_rnw = 1;
integer n_rstedge = 0;

localparam BRN = 64;
reg [22:0] br_from[0:BRN-1], br_to[0:BRN-1];
reg [31:0] br_c   [0:BRN-1];
integer br_wr = 0;
reg [22:0] last_romA = 23'h7fffff;
always @(posedge clk) begin

    ring_hit_l <= !ASn && !dtac_mux;
    if( !ASn && !dtac_mux && !ring_hit_l ) begin
        ring_a [ring_wr[6:0]] <= A;
        ring_d [ring_wr[6:0]] <= RnW ? cpu_din : cpu_dout_68k;
        ring_cs[ring_wr[6:0]] <= cs_code;
        ring_rw[ring_wr[6:0]] <= RnW;
        ring_c [ring_wr[6:0]] <= abs_cyc;
        ring_wr  <= ring_wr + 1;
        prev_rnw <= RnW;

        if( rom_cs && RnW ) begin
            last_romA <= A;
            if( A != last_romA + 23'd1 ) begin
                br_from[br_wr[5:0]] <= last_romA;
                br_to  [br_wr[5:0]] <= A;
                br_c   [br_wr[5:0]] <= abs_cyc;
                br_wr <= br_wr + 1;
            end
        end

        if( rom_cs && rom_ok && RnW && A < 23'h80 && !prev_rnw && !in_trap_l && n_trapdump<8 ) begin
            n_trapdump <= n_trapdump+1;
            in_trap_l  <= 1;
            $display("MAIN-EXC[%0d]: EXCEPCION real, vector #%0d (byte 0x%03x) en abs_cyc=%0d",
                     n_trapdump, A>>1, {A,1'b0}, abs_cyc);
            for( ri=0; ri<BRN; ri=ri+1 )
                $display("MAIN-EXCBR[%0d]: %06x -> %06x cyc=%0d", ri,
                    {br_from[(br_wr[5:0]+ri[5:0])&6'h3f],1'b0}, {br_to[(br_wr[5:0]+ri[5:0])&6'h3f],1'b0},
                    br_c   [(br_wr[5:0]+ri[5:0])&6'h3f]);
            for( ri=0; ri<RINGN; ri=ri+1 )
                $display("MAIN-EXCBUS[%0d]: A=%06x data=%04x RnW=%b cs=%0d cyc=%0d", ri,
                    {ring_a[(ring_wr[6:0]+ri[6:0])&7'h7f],1'b0}, ring_d[(ring_wr[6:0]+ri[6:0])&7'h7f],
                    ring_rw[(ring_wr[6:0]+ri[6:0])&7'h7f], ring_cs[(ring_wr[6:0]+ri[6:0])&7'h7f],
                    ring_c [(ring_wr[6:0]+ri[6:0])&7'h7f]);
        end else begin
            in_trap_l <= 0;
        end
    end

    if( cpu_we && !ASn && pal_cs && A[12:1]==11'h002 && cpu_dout_68k==16'h02ff &&
        !s78_hit_l && n_s78<3 ) begin
        n_s78 <= n_s78+1;
        $display("SESION78-TRIGGER[%0d]: escritura corruptora detectada, A=%06x data=%04x abs_cyc=%0d",
                  n_s78, {A,1'b0}, cpu_dout_68k, abs_cyc);
        for( ri=0; ri<BRN; ri=ri+1 )
            $display("SESION78-BR[%0d]: %06x -> %06x cyc=%0d", ri,
                {br_from[(br_wr[5:0]+ri[5:0])&6'h3f],1'b0}, {br_to[(br_wr[5:0]+ri[5:0])&6'h3f],1'b0},
                br_c   [(br_wr[5:0]+ri[5:0])&6'h3f]);
        for( ri=0; ri<RINGN; ri=ri+1 )
            $display("SESION78-BUS[%0d]: A=%06x data=%04x RnW=%b cs=%0d cyc=%0d", ri,
                {ring_a[(ring_wr[6:0]+ri[6:0])&7'h7f],1'b0}, ring_d[(ring_wr[6:0]+ri[6:0])&7'h7f],
                ring_rw[(ring_wr[6:0]+ri[6:0])&7'h7f], ring_cs[(ring_wr[6:0]+ri[6:0])&7'h7f],
                ring_c [(ring_wr[6:0]+ri[6:0])&7'h7f]);
    end
    s78_hit_l <= cpu_we && !ASn && pal_cs && A[12:1]==11'h002 && cpu_dout_68k==16'h02ff;
    rst_l <= rst;
    if( rst && !rst_l && n_rstedge<40 ) begin
        n_rstedge <= n_rstedge+1;
        $display("MAIN-RSTEDGE[%0d]: flanco de subida de rst en abs_cyc=%0d", n_rstedge, abs_cyc);
    end
end

always @(posedge clk) begin
    if( !rst ) begin
        if( bgack_evt_mid && !bgack_evt_lost )
            $display("SONDA-BGACK-MID: bus tomado con ciclo en curso (no era escritura a spriteram) -- A=%06x RnW=%b oram_cs=%b abs_cyc=%0d",
                {A,1'b0}, RnW, oram_cs, abs_cyc);
        if( bgack_evt_lost )
            $display("SONDA-BGACK-PERDIDA: escritura de CPU al SPRITERAM descartada por la toma de bus del DMA -- A=%06x data=%04x dsn=%b abs_cyc=%0d",
                {A,1'b0}, cpu_dout_68k, {UDSn,LDSn}, abs_cyc);
        if( abs_cyc!=0 && (abs_cyc % 20000000)==0 )
            $display("SONDA-BGACK-RESUMEN: tomas=%0d con_ciclo_en_curso=%0d escrituras_spriteram_perdidas=%0d abs_cyc=%0d",
                n_bgack, n_bgack_mid, n_bgack_lost, abs_cyc);
    end
end
`endif

always @* begin
    rom_cs = 0; ram_cs = 0; pal_cs = 0; oram_cs = 0; objreg_cs = 0; tile_cs = 0;
    pcu_cs = 0; prot_cs = 0; watchdog_cs = 0; ram1c05_cs = 0;
    io_cs = 0; p1_cs = 0; p2_cs = 0; p3_cs = 0; p4_cs = 0; coins_cs = 0;
    eepromr_cs = 0; eepromw_cs = 0; unk1c0300_cs = 0; sndmain_cs = 0; soundkludge_cs = 0;
    if( !ASn ) begin

        rom_cs        = (A[23:20]==4'h0) && (A[19:18]!=2'b11);

        ram_cs        = (A[23:14]==10'h041) & ~BUSn;
        pal_cs        = A[23:12]==12'h140;
        oram_cs       = A[23:14]==10'h060;

        objreg_cs     = (A[23:5] ==19'h2D000) & ~BUSn;

        tile_cs       = (A[23:14]==10'h180) & ~BUSn;
        pcu_cs        = A[23:5] ==19'h2E038;
        sndmain_cs    = A[23:2] ==22'h170180;
        soundkludge_cs= A[23:1] ==23'h2E0302;
        io_cs         = A[23:12]==12'h1C0;
        if( io_cs ) case( A[11:8] )
            4'h0: begin
                p1_cs = (A[2:1]==2'd0); p2_cs = (A[2:1]==2'd1);
                p3_cs = (A[2:1]==2'd2); p4_cs = (A[2:1]==2'd3);
            end
            4'h1: begin coins_cs = ~A[1]; eepromr_cs = A[1]; end
            4'h2: eepromw_cs    = 1;
            4'h3: unk1c0300_cs  = 1;
            4'h4: watchdog_cs   = 1;
            4'h5: ram1c05_cs    = 1;
            4'h8: prot_cs       = 1;
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~BUSn & ~|{ rom_cs, ram_cs, pal_cs, oram_cs, objreg_cs, tile_cs, pcu_cs, prot_cs,
        watchdog_cs, ram1c05_cs, p1_cs, p2_cs, p3_cs, p4_cs, coins_cs, eepromr_cs, eepromw_cs,
        unk1c0300_cs, sndmain_cs, soundkludge_cs };
`endif
end

function [7:0] konami_player( input [5:0] joy, input start_n );
    konami_player = { start_n, 1'b1, joy[5:0] };
endfunction
always @(*) begin
    port_in = 16'hffff;
    if( p1_cs      ) port_in = { 8'hff, konami_player(joystick1, cab_1p[0]) };
    if( p2_cs       ) port_in = { 8'hff, konami_player(joystick2, cab_1p[1]) };
    if( p3_cs       ) port_in = { 8'hff, konami_player(joystick3, cab_1p[2]) };
    if( p4_cs       ) port_in = { 8'hff, konami_player(joystick4, cab_1p[3]) };
    if( coins_cs    ) port_in = { 8'hff, service[3:0], coin[3:0] };

    if( eepromr_cs  ) port_in = { 8'hff, dip_test, 2'b00, 1'b0, ~LVBL, 1'b0, eep_rdy, eep_do };
    if( sndmain_cs  ) port_in = { 8'hff, snd2main };
end

always @(posedge clk) begin
    cpu_din <= rom_cs      ? rom_data    :
               ram_cs      ? ram_dout    :
               oram_cs     ? oram_dout   :
               objreg_cs   ? objreg_dout :
               tile_cs     ? tile_dout   :
               ram1c05_cs  ? ram1c05_dout:
               pal_cs      ? pal_dout    :
               prot_cs     ? prot_dout   :
               (p1_cs|p2_cs|p3_cs|p4_cs|coins_cs|eepromr_cs|sndmain_cs) ? port_in : 16'hffff;
end

reg [7:0] cur_eep;
wire eep_di  = cur_eep[0];
wire eep_cs  = cur_eep[1];
wire eep_clk = cur_eep[2];
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        cur_eep <= 0; dim_c <= 0; objtest_bank <= 0;
    end else if( eepromw_cs & cpu_we & ~LDSn ) begin
        cur_eep      <= cpu_dout_68k[7:0];
        dim_c        <= cpu_dout_68k[4:3];
        objtest_bank <= cpu_dout_68k[5];
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        rmrd <= 0; dim_v <= 0;
    end else if( unk1c0300_cs & cpu_we & ~LDSn ) begin
        rmrd  <= cpu_dout_68k[3];
        dim_v <= cpu_dout_68k[6:4];
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) sndirq <= 0;
    else      sndirq <= soundkludge_cs & cpu_we;
end

reg HALTn;
always @(posedge clk) HALTn <= dip_pause & ~rst;

reg s80_rst_l=1, s80_haltn_l=0, s80_asn_l=1;
integer s80_cen_cnt=0, s80_cenb_cnt=0;
always @(posedge clk) begin

    if( 1'b0 && (rst != s80_rst_l || HALTn != s80_haltn_l || ASn != s80_asn_l) )
        $display("SESION80-EDGE: abs_cyc=%0d rst=%b->%b HALTn=%b->%b ASn=%b->%b dip_pause=%b rom_cs=%b rom_ok=%b cpu_cen=%b cpu_cenb=%b",
                  abs_cyc, s80_rst_l, rst, s80_haltn_l, HALTn, s80_asn_l, ASn, dip_pause, rom_cs, rom_ok, cpu_cen, cpu_cenb);
    s80_rst_l   <= rst;

    if( !rst && cpu_cenb ) begin
        s80_cenb_cnt <= s80_cenb_cnt + 1;
        if( s80_cenb_cnt < 20 || s80_cenb_cnt % 2000 == 0 )
            $display("SESION80-CENB[%0d]: abs_cyc=%0d cpu_cen=%b cpu_cenb=%b ASn=%b", s80_cenb_cnt, abs_cyc, cpu_cen, cpu_cenb, ASn);
    end
    if( !rst && cpu_cen ) begin
        s80_cen_cnt <= s80_cen_cnt + 1;
        if( s80_cen_cnt < 40 || s80_cen_cnt % 2000 == 0 )
            $display("SESION80-CEN[%0d]: abs_cyc=%0d A=%06x ASn=%b RnW=%b FC=%03b bus_cs=%b bus_busy=%b DTACKn=%b BRn=%b BGACKn=%b BGn=%b IPLn=%03b",
                      s80_cen_cnt, abs_cyc, {A,1'b0}, ASn, RnW, FC, bus_cs, bus_busy, dtac_mux, prot_brn, prot_bgackn, BGn, IPLn);
    end
    s80_haltn_l <= HALTn;
    s80_asn_l   <= ASn;
end

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
    .den        ( 6'd3      ),
    .DTACKn     ( DTACKn    ),
    .wait2      ( 1'b0      ),
    .wait3      ( 1'b0      ),
    .fave       (           ),
    .fworst     (           )
);

always @(posedge clk) IPLn <= ~tile_irqn ? 3'b011 : 3'b111;

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
    .BRn        ( prot_brn    ),
    .BGACKn     ( prot_bgackn ),
    .BGn        ( BGn         ),

    .DTACKn     ( dtac_mux    ),
    .IPLn       ( IPLn        )
);
`else
    initial begin
        rom_cs=0; ram_cs=0; oram_cs=0; objreg_cs=0; pal_cs=0; tile_cs=0;
        pcu_cs=0; prot_cs=0; watchdog_cs=0; ram1c05_cs=0;
        sndirq=0; rmrd=0; dim_v=0; dim_c=0; objtest_bank=0;
    end
    assign cpu_dout=0, cpu_we=0, main_addr=0, ram_dsn=0, snd_wrn=1, snd_dout=0,
           st_dout=0, nv_addr=0, nv_din=0, nv_we=0, BGn=1'b1;
`endif
endmodule
