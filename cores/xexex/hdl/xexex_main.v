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
    Date: 7-7-2024 */

module xexex_main(
    input                rst,
    input                clk,
    input                LVBL,
    input         [ 8:0] vdump,

    output        [20:1] main_addr,
    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,

    output               cpu_we,
    output reg           pal_cs,
    output reg           pcu_cs,

    output               pair_we,
    input         [ 7:0] pair_dout,
    output               snd_wrn,
    input         [ 7:0] snd2main,
    output reg           sndon,
    output reg           mute,

    output reg           rom_cs,
    output reg           ram_cs,
    output reg           vram_cs,
    output reg           tilereg_cs,
    output reg           alpha_cs,
    output reg           obj_cs,

    output reg           lvcram_cs,
    output reg           lvcreg_cs,
    output reg           lvcrom_cs,
    input                lvc_ok,
    input         [15:0] lvc_dout,

    input         [15:0] oram_dout,
    input         [15:0] vram_dout,
    input         [15:0] pal_dout,
    input         [15:0] ram_dout,
    input         [15:0] rom_data,
    input                ram_ok,
    input                rom_ok,
    input                vdtac,
    input                tile_irqn,

    output reg           objreg_cs,
    output reg           objcha_n,
    output reg           rmrd,
    output               alpha_off,
    input                dma_bsy,

    output      [ 6:0]   nv_addr,
    input       [ 7:0]   nv_dout,
    output      [ 7:0]   nv_din,
    output               nv_we,

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

reg  io_cs, tilereg_b_cs, ccu_cs, sndirq_cs, pair_cs, romrd_cs,
     p1_cs, p2_cs, sys_cs, eep_cs, control2_cs;
reg  [15:0] port_in;

/* verilator tracing_off */
assign main_addr= A[20:1];
assign ram_dsn  = {UDSn,LDSn};

assign bus_cs   = rom_cs | ram_cs | lvcrom_cs;
assign bus_busy = (rom_cs & ~rom_ok) | (ram_cs & ~ram_ok) | (lvcrom_cs & ~lvc_ok);
assign BUSn     = ASn | (LDSn & UDSn);
assign cpu_we   = ~RnW;
assign alpha_off= cur_control2[9];
assign st_dout  = { rmrd, cur_control2[11], cur_control2[6], objcha_n, 4'd0 };

assign VPAn     = ~(&FC & ~ASn);
assign iack     =  &FC & ~ASn;
assign dtac_mux = DTACKn | ~vdtac;

assign pair_we  = pair_cs & ~RnW & ~LDSn;
assign snd_wrn  = ~(sndirq_cs & ~RnW);

`ifdef SIMULATION
reg none_cs;
`endif
always @* begin
    rom_cs      = 0; ram_cs   = 0; obj_cs   = 0; vram_cs  = 0; pal_cs  = 0;
    tilereg_cs  = 0; tilereg_b_cs = 0; alpha_cs = 0; pcu_cs = 0; objreg_cs = 0;
    ccu_cs      = 0; sndirq_cs= 0; pair_cs  = 0; romrd_cs = 0;
    p1_cs       = 0; p2_cs    = 0; sys_cs   = 0; eep_cs   = 0; control2_cs = 0;
    lvcram_cs   = 0; lvcreg_cs= 0; lvcrom_cs= 0;
    io_cs       = 0;
    if( !ASn ) begin
        rom_cs   = (A[23:19]==5'b00000) | (A[23:19]==5'b00010);
        ram_cs   = (A[23:16]==8'h08) & ~BUSn;
        obj_cs   = (A[23:16]==8'h09);
        vram_cs  = (A[23:14]==10'b00_0110_0000);
        romrd_cs = (A[23:13]==11'b000_1100_1000);
        lvcrom_cs= (A[23:13]==11'b000_1101_0000);
        pal_cs   = (A[23:13]==11'b000_1101_1000);
        io_cs    = (A[23:17]==7'b0000_110);
        if( io_cs ) case( A[16:13] )
            4'h0: tilereg_cs   = 1;
            4'h1: objreg_cs    = 1;
            4'h2: objreg_cs    = 1;
            4'h3: lvcram_cs    = 1;
            4'h4: lvcreg_cs    = 1;
            4'h5: alpha_cs     = 1;
            4'h6: pcu_cs       = 1;
            4'h8: ccu_cs       = 1;
            4'ha: sndirq_cs    = 1;
            4'hb: pair_cs      = 1;
            4'hc: tilereg_b_cs = 1;
            4'hd: begin p1_cs  = ~A[1]; p2_cs  = A[1]; end
            4'he: begin sys_cs = ~A[1]; eep_cs = A[1]; end
            4'hf: control2_cs  = 1;
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~BUSn & ~|{ rom_cs, ram_cs, obj_cs, vram_cs, pal_cs, romrd_cs, lvcrom_cs,
        tilereg_cs, tilereg_b_cs, alpha_cs, pcu_cs, objreg_cs, ccu_cs, lvcram_cs, lvcreg_cs,
        sndirq_cs, pair_cs, p1_cs, p2_cs, sys_cs, eep_cs, control2_cs };
`endif
end

function [7:0] konami_player( input [5:0] joy, input start );
    konami_player = { start, 1'b1, joy[5:0] };
endfunction
always @(*) begin
    port_in = 16'hffff;
    if( p1_cs  ) port_in = { 8'h00, konami_player(joystick1, cab_1p[0]) };
    if( p2_cs  ) port_in = { 8'h00, konami_player(joystick2, cab_1p[1]) };

    if( sys_cs ) port_in = { 8'hff, 2'b11, service[1:0], 2'b11, coin[1:0] };

    if( eep_cs ) port_in = { 8'h00, 4'h0, dip_test, 1'b0, eep_rdy, eep_do };
end

/* verilator tracing_off */
always @(posedge clk) begin
    cpu_din <= rom_cs     ? rom_data        :
               ram_cs     ? ram_dout        :
               obj_cs     ? oram_dout       :
               vram_cs    ? vram_dout       :
               pal_cs     ? pal_dout        :
               (lvcram_cs|lvcreg_cs|lvcrom_cs) ? lvc_dout :
               pair_cs    ? {8'hff,pair_dout}:

               control2_cs? cur_control2    :
               (p1_cs|p2_cs|sys_cs|eep_cs) ? port_in : 16'hffff;
end

wire eep_di  = cur_control2[0];
wire eep_scs = cur_control2[1];
wire eep_clk = cur_control2[2];
wire irq6en  = cur_control2[5];
wire irq5en  = cur_control2[6];
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
        objcha_n <= ~cur_control2[8];
        rmrd     <= romrd_cs;
        mute     <= 1'b0;
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) sndon <= 0;
    else      sndon <= sndirq_cs & cpu_we;
end

reg  line0_l;
wire line0     = vdump==9'h100;
wire irq4_edge = ~LVBL;
wire irq5_edge = ~dma_bsy;
wire irq6_edge = line0;
wire irq4_q, irq5_q, irq6_q;
wire irq4_ack = iack & (A[3:1]==3'd4);
wire irq5_ack = iack & (A[3:1]==3'd5);
wire irq6_ack = iack & (A[3:1]==3'd6);

jtframe_edge #(.QSET(1)) u_irq4(
    .rst( rst ), .clk( clk ), .edgeof( irq4_edge ), .clr( ~irq4en | irq4_ack ), .q( irq4_q ));
jtframe_edge #(.QSET(1)) u_irq5(
    .rst( rst ), .clk( clk ), .edgeof( irq5_edge ), .clr( ~irq5en | irq5_ack ), .q( irq5_q ));
jtframe_edge #(.QSET(1)) u_irq6(
    .rst( rst ), .clk( clk ), .edgeof( irq6_edge ), .clr( ~irq6en | irq6_ack ), .q( irq6_q ));

always @(posedge clk) begin

    IPLn <= irq6_q ? 3'b001 :
            irq5_q ? 3'b010 :
            irq4_q ? 3'b011 : 3'b111;
end

`ifdef SIMULATION

reg [23:1] daf_lo, daf_hi;
wire       data_acc = ~ASn & ~FC[1] & FC[0];
reg [23:1] pc_lo, pc_hi, pc_last, pcf_lo, pcf_hi;
reg [31:0] n_prog, n_ram_w, n_vram_w, n_pal_w, n_obj_w, n_ctl2_w, n_irq4, n_irq5, n_irq6;
reg [31:0] n_dma, n_objreg, n_lvc_w, n_sndpoll;
reg [ 7:0] snd_seen;
reg        dmab_l;
reg [15:0] frame_id;
reg        lvbl_l, busn_l;
wire       prog_fetch = ~ASn & RnW & FC[1] & ~FC[0];

wire       wr_stb = busn_l & ~BUSn & cpu_we;
wire       rd_stb = busn_l & ~BUSn & ~cpu_we;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        pc_lo <= ~23'd0; pc_hi <= 0; pc_last <= 0; frame_id <= 0; lvbl_l <= 0;
        pcf_lo <= ~23'd0; pcf_hi <= 0; busn_l <= 1;
        daf_lo <= ~23'd0; daf_hi <= 0;
        n_prog<=0; n_ram_w<=0; n_vram_w<=0; n_pal_w<=0; n_obj_w<=0; n_ctl2_w<=0;
        n_irq4<=0; n_irq5<=0; n_irq6<=0; n_dma<=0; n_objreg<=0; n_lvc_w<=0; n_sndpoll<=0;
        snd_seen<=0; dmab_l<=0;
    end else begin
        lvbl_l <= LVBL;
        busn_l <= BUSn;
        dmab_l <= dma_bsy;
        if( ~dmab_l & dma_bsy ) n_dma <= n_dma+1;
        if( data_acc ) begin
            if( A < daf_lo ) daf_lo <= A;
            if( A > daf_hi ) daf_hi <= A;
        end
        if( prog_fetch ) begin
            pc_last <= A; n_prog <= n_prog+1;
            if( A < pc_lo ) pc_lo <= A;
            if( A > pc_hi ) pc_hi <= A;
            if( A < pcf_lo ) pcf_lo <= A;
            if( A > pcf_hi ) pcf_hi <= A;
        end
        if( wr_stb ) begin
            if( ram_cs      ) n_ram_w  <= n_ram_w +1;
            if( vram_cs     ) n_vram_w <= n_vram_w+1;
            if( pal_cs      ) n_pal_w  <= n_pal_w +1;
            if( obj_cs      ) n_obj_w  <= n_obj_w +1;
            if( control2_cs ) n_ctl2_w <= n_ctl2_w+1;
            if( objreg_cs   ) n_objreg <= n_objreg+1;
            if( lvcram_cs   ) n_lvc_w  <= n_lvc_w +1;
        end
        if( rd_stb && pair_cs && A[4:1]==4'ha ) n_sndpoll <= n_sndpoll+1;
        if( pair_cs && A[4:1]==4'ha && ~BUSn && ~dtac_mux ) snd_seen <= pair_dout;
        if( irq4_ack ) n_irq4 <= n_irq4+1;
        if( irq5_ack ) n_irq5 <= n_irq5+1;
        if( irq6_ack ) n_irq6 <= n_irq6+1;
        if( lvbl_l & ~LVBL ) begin
            frame_id <= frame_id+1;
            $display("BOOT f=%0d PC=%06x bucle=[%06x-%06x] dato=[%06x-%06x] visto=[%06x-%06x] | wr ram=%0d vram=%0d pal=%0d obj=%0d lvc=%0d ctl2=%0d | ctl2=%04x ack4=%0d ack5=%0d ack6=%0d | objreg=%0d DMA/f=%0d | sndpoll=%0d snd=%02x",
                frame_id, {pc_last,1'b0}, {pcf_lo,1'b0}, {pcf_hi,1'b0}, {daf_lo,1'b0}, {daf_hi,1'b0},
                {pc_lo,1'b0}, {pc_hi,1'b0},
                n_ram_w, n_vram_w, n_pal_w, n_obj_w, n_lvc_w, n_ctl2_w,
                cur_control2, n_irq4, n_irq5, n_irq6, n_objreg, n_dma, n_sndpoll, snd_seen);
            n_prog<=0; n_ram_w<=0; n_vram_w<=0; n_pal_w<=0; n_obj_w<=0; n_ctl2_w<=0;
            n_dma<=0; n_objreg<=0; n_lvc_w<=0; n_sndpoll<=0;
            pcf_lo <= ~23'd0; pcf_hi <= 0;
            daf_lo <= ~23'd0; daf_hi <= 0;
        end
    end
end

reg [4:0] rp_n;
reg       rp_cs_l;
always @(posedge clk, posedge rst) begin
    if( rst ) begin rp_n <= 0; rp_cs_l <= 0; end
    else begin
        rp_cs_l <= rom_cs & rom_ok & ~BUSn;
        if( rom_cs & rom_ok & ~BUSn & ~rp_cs_l & rp_n<5'd16 ) begin
            rp_n <= rp_n + 5'd1;
            $display("ROMPROBE #%0d A=%06x dato=%04x", rp_n, {A,1'b0}, rom_data);
        end
    end
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
    .scs        ( eep_scs   ),
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

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),

    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout    ),

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
        lvcram_cs = 0;
        lvcreg_cs = 0;
        lvcrom_cs = 0;
        mute      = 0;
    end
    assign
        cpu_dout  = 0,
        cpu_we    = 0,
        main_addr = 0,
        ram_dsn   = 0,
        snd_wrn   = 0,
        st_dout   = 0,
        alpha_off = 0,
        nv_addr   = 0,
        nv_din    = 0,
        pair_we   = 0,
        nv_we     = 0;
`endif
endmodule
