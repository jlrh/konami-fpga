/*  blswhstl — CPU principal 68000 y mapa de memoria.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module blswhstl_main(
    input                rst,
    input                clk,
    input                LVBL,

    output        [18:1] main_addr,
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
    output reg           k054000_cs,
    output reg           watchdog_cs,

    output               snd_wrn,
    output        [ 7:0] snd_dout,
    input         [ 7:0] snd2main,
    output reg           sndirq,

    input         [15:0] oram_dout,
    input         [15:0] objreg_dout,
    input         [15:0] tile_dout,
    input         [15:0] pal_dout,
    input         [ 7:0] k054000_dout,
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
    output reg           tile_rombank,

    input                tile_irqn,

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
wire        eep_rdy, eep_do, bus_cs, bus_busy, BUSn;
wire        dtac_mux, iack;
wire [15:0] cpu_dout_68k;

assign main_addr = A[18:1];
assign ram_dsn   = {UDSn,LDSn};
assign bus_cs    = rom_cs | ram_cs;
assign bus_busy  = (rom_cs & ~rom_ok) | (ram_cs & ~ram_ok);
assign BUSn      = ASn | (LDSn & UDSn);
assign cpu_we    = ~RnW;
assign cpu_dout  = cpu_dout_68k;
assign VPAn      = ~(&FC & ~ASn);
assign iack      =  &FC & ~ASn;
assign dtac_mux  = DTACKn | ~vdtac;

assign snd_wrn   = ~(sndmain_cs & ~RnW & ~LDSn);
assign snd_dout  = cpu_dout_68k[7:0];
assign st_dout   = 8'd0;

reg  io_cs, p1_cs, p2_cs, coins_cs, eepromr_cs, eepromw_cs, ctrl700300_cs;
reg  sndmain_cs, soundkludge_cs;
reg  [15:0] port_in;
`ifdef SIMULATION
reg  none_cs;
`endif

always @* begin
    rom_cs = 0; ram_cs = 0; pal_cs = 0; oram_cs = 0; objreg_cs = 0; tile_cs = 0;
    pcu_cs = 0; k054000_cs = 0; watchdog_cs = 0;
    io_cs = 0; p1_cs = 0; p2_cs = 0; coins_cs = 0;
    eepromr_cs = 0; eepromw_cs = 0; ctrl700300_cs = 0; sndmain_cs = 0; soundkludge_cs = 0;
    if( !ASn ) begin

        rom_cs        = A[23:19]==5'h00;

        ram_cs        = (A[23:14]==10'h081) & ~BUSn;
        pal_cs        = A[23:12]==12'h400;
        oram_cs       = A[23:14]==10'h0C0;

        objreg_cs     = (A[23:5] ==19'h34000) & ~BUSn;

        tile_cs       = (A[23:14]==10'h060) & ~BUSn;

        k054000_cs    = (A[23:6] ==18'h14000) & ~BUSn;
        pcu_cs        = A[23:5] ==19'h3C038;
        sndmain_cs    = A[23:2] ==22'h1E0180;
        soundkludge_cs= A[23:1] ==23'h3C0302;
        io_cs         = A[23:12]==12'h700;
        if( io_cs ) case( A[11:8] )

            4'h0: begin
                p1_cs      = (A[2:1]==2'd0);
                p2_cs      = (A[2:1]==2'd1);
                coins_cs   = (A[2:1]==2'd2);
                eepromr_cs = (A[2:1]==2'd3);
            end
            4'h2: eepromw_cs    = 1;
            4'h3: ctrl700300_cs = 1;
            4'h4: watchdog_cs   = 1;
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~BUSn & ~|{ rom_cs, ram_cs, pal_cs, oram_cs, objreg_cs, tile_cs, pcu_cs, k054000_cs,
        watchdog_cs, p1_cs, p2_cs, coins_cs, eepromr_cs, eepromw_cs, ctrl700300_cs,
        sndmain_cs, soundkludge_cs };
`endif
end

function [7:0] konami_player( input [5:0] joy );
    konami_player = { 2'b11, joy[5:0] };
endfunction
always @(*) begin
    port_in = 16'hffff;
    if( p1_cs      ) port_in = { 8'hff, konami_player(joystick1) };
    if( p2_cs      ) port_in = { 8'hff, konami_player(joystick2) };
    if( coins_cs   ) port_in = { 8'hff, 1'b1, 1'b0, cab_1p[1], cab_1p[0],
                                        dip_test, service[0], coin[1], coin[0] };
    if( eepromr_cs ) port_in = { 8'hff, 6'b111111, eep_rdy, eep_do };
    if( sndmain_cs ) port_in = { 8'hff, snd2main };
end

always @(posedge clk) begin
    cpu_din <= rom_cs      ? rom_data    :
               ram_cs      ? ram_dout    :
               oram_cs     ? oram_dout   :
               objreg_cs   ? objreg_dout :
               tile_cs     ? tile_dout   :
               pal_cs      ? pal_dout    :

               k054000_cs  ? { 8'h00, k054000_dout } :

               watchdog_cs ? 16'h0000 :
               (p1_cs|p2_cs|coins_cs|eepromr_cs|sndmain_cs) ? port_in : 16'hffff;
end

reg [2:0] cur_eep;
wire eep_di  = cur_eep[0];
wire eep_cs  = cur_eep[1];
wire eep_clk = cur_eep[2];
always @(posedge clk, posedge rst) begin
    if( rst ) cur_eep <= 0;
    else if( eepromw_cs & cpu_we & ~LDSn ) cur_eep <= cpu_dout_68k[2:0];
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        rmrd <= 0; tile_rombank <= 0;
    end else if( ctrl700300_cs & cpu_we & ~LDSn ) begin
        rmrd         <= cpu_dout_68k[3];
        tile_rombank <= cpu_dout_68k[7];
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) sndirq <= 0;
    else      sndirq <= soundkludge_cs & cpu_we;
end

reg HALTn;
always @(posedge clk) HALTn <= dip_pause & ~rst;

`ifdef SIMULATION

integer n_none=0;
always @(posedge clk) if( none_cs ) begin
    n_none <= n_none+1;
    if( n_none<32 || n_none%100000==0 )
        $display("MAIN-NONE[%0d]: acceso SIN decode A=%06x RnW=%b (devuelve 0xffff)", n_none, {A,1'b0}, RnW);
end

integer abs_cyc = 0;
always @(posedge clk) abs_cyc <= abs_cyc + 1;

integer n_rd=0, n_seq=0;
reg [31:0] boot_sp, boot_pc;
wire bus_done = !ASn && !dtac_mux && RnW;

reg rom_ok_l=0;
integer n_slot=0;
always @(posedge clk) begin
    rom_ok_l <= rom_ok;
    if( rom_cs && rom_ok && !rom_ok_l && n_slot<24 ) begin
        n_slot <= n_slot+1;
        $display("MAIN-SLOT[%0d] abs_cyc=%0d main_addr=%05x (byte %06x) rom_data=%04x",
                 n_slot, abs_cyc, main_addr, {main_addr,1'b0}, rom_data);
    end
end
always @(posedge clk) if( bus_done && rom_cs ) begin
    if( n_rd < 24 ) begin
        n_rd <= n_rd+1;
        $display("MAIN-RD[%0d] abs_cyc=%0d A=%06x din=%04x rom_data=%04x ok=%b", n_rd, abs_cyc, {A,1'b0}, cpu_din, rom_data, rom_ok);
    end
    case( {A,1'b0} )
        24'h000000: boot_sp[31:16] <= cpu_din;
        24'h000002: boot_sp[15:0]  <= cpu_din;
        24'h000004: boot_pc[31:16] <= cpu_din;
        24'h000006: begin
            boot_pc[15:0] <= cpu_din;
            $display("MAIN-BOOTVEC: SP=%08x PC=%08x", {boot_sp[31:16],boot_sp[15:0]}, {boot_pc[31:16],cpu_din});
        end
        default:;
    endcase
    if( n_seq<400 ) begin
        n_seq <= n_seq+1;
        $display("MAIN-SEQ[%0d]: A=%06x din=%04x", n_seq, {A,1'b0}, cpu_din);
    end
end

integer n_objreg=0;
reg     objreg_wr_l=0;
wire    objreg_wr = objreg_cs & cpu_we & ~BUSn;
always @(posedge clk) objreg_wr_l <= objreg_wr;
always @(posedge clk) if( objreg_wr && !objreg_wr_l && n_objreg<24 ) begin
    n_objreg <= n_objreg+1;
    $display("BL-OBJREG[%0d] abs_cyc=%0d A=%06x dout=%04x dsn=%b%b",
             n_objreg, abs_cyc, {A,1'b0}, cpu_dout_68k, UDSn, LDSn);
end

integer n_k54=0;
always @(posedge clk) if( k054000_cs && !BUSn ) begin
    n_k54 <= n_k54+1;
    if( n_k54<64 )
        $display("MAIN-K054000[%0d]: abs_cyc=%0d A=%06x reg=%02d RnW=%b din=%02x dout=%02x",
                 n_k54, abs_cyc, {A,1'b0}, A[5:1], RnW, cpu_dout_68k[7:0], k054000_dout);
end
`endif

jt5911 #(.AW(7)) u_eeprom(
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

    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),

    .DTACKn     ( dtac_mux    ),
    .IPLn       ( IPLn        )
);
`else
    initial begin
        rom_cs=0; ram_cs=0; oram_cs=0; objreg_cs=0; pal_cs=0; tile_cs=0;
        pcu_cs=0; k054000_cs=0; watchdog_cs=0;
        sndirq=0; rmrd=0; tile_rombank=0;
    end
    assign cpu_dout=0, cpu_we=0, main_addr=0, ram_dsn=0, snd_wrn=1, snd_dout=0,
           st_dout=0, nv_addr=0, nv_din=0, nv_we=0;
`endif
endmodule
