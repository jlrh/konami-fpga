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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module mtlchamp_main(
    input                rst,
    input                clk,
    input                LVBL,
    input         [ 8:0] vdump,

    output        [21:1] main_addr,

    output        [ 1:0] ram_dsn,
    output        [15:0] cpu_dout,
    output               cpu_we,
    output reg           rom_cs,
    output reg           ram_cs,
    input         [15:0] rom_data,
    input         [15:0] ram_dout,
    input                rom_ok,
    input                ram_ok,

    output reg           objsys_cs,
    output reg           pcu_cs,
    output reg           objrom_cs,
    output reg           objreg_cs,
    output reg           obj46_cs,
    output reg           alpha_cs,
    output reg           tilereg_cs,
    output reg           prot_cs,
    output reg           tilereg_b_cs,
    output reg           ccu_cs,
    output reg           vram_cs,
    output reg           romrd_cs,
    output reg           pal_cs,
    output reg           rmrd,
    input         [15:0] oram_dout,
    input         [15:0] vram_dout,
    input         [15:0] pal_dout,
    input         [ 7:0] ccu_dout,
    input         [15:0] objrom_dout,
    input                vdtac,
    input                dma_bsy,

    input                obj_irqen,

    output               pair_we,
    input         [ 7:0] pair_dout,
    output reg           sndon,

    output        [ 6:0] nv_addr,
    input         [ 7:0] nv_dout,
    output        [ 7:0] nv_din,
    output               nv_we,

    input         [ 6:0] joystick1,
    input         [ 6:0] joystick2,
    input         [ 6:0] joystick3,
    input         [ 6:0] joystick4,
    input         [ 3:0] cab_1p,
    input         [ 3:0] coin,
    input                service,
    input         [ 3:0] dipsw,
    input                dip_pause,
    input                dip_test,
    output        [ 7:0] st_dout,
    output        [ 7:0] st_rd,
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
wire [15:0] cpu68_dout;

wire        blit_busy, blit_req, blit_we, blit_ok;
wire [23:1] blit_addr;
wire [ 1:0] blit_dsn;
wire [15:0] blit_dout;

wire [23:1] Abus   = blit_busy ? blit_addr : A;
wire [ 1:0] dsnbus = blit_busy ? blit_dsn  : {UDSn,LDSn};
wire        vldbus = blit_busy ? blit_req  : ~ASn;
wire        webus  = blit_busy ? blit_we   : ~RnW;

reg  io40_cs, io41_cs, eepw_cs, ctrl_cs, p1p2_cs, p3p4_cs, in0_cs, in1_cs,
     pair_cs, sndirq_cs;
reg  [15:0] port_in;

reg  eep_di, eep_cs, eep_clk;

reg  [ 7:0] mw_irq_ctrl;

`ifdef SIMULATION
wire [23:0] A_full = {A,1'b0};
`endif
/* verilator tracing_off */

assign main_addr= Abus[21:1];
assign ram_dsn  = dsnbus;
assign cpu_dout = blit_busy ? blit_dout : cpu68_dout;
assign bus_cs   = rom_cs | ram_cs;
assign bus_busy = (rom_cs & ~rom_ok) | (ram_cs & ~ram_ok);
assign BUSn     = ~vldbus | (dsnbus==2'b11);
assign cpu_we   = webus;

reg [ 6:0] hito;
reg        post_done;

reg [ 7:0] blit_fires;
reg [ 7:0] prot_wr;
reg [ 7:2] blit_flags;

assign st_dout  =

    debug_bus[5:2]==4'h0 ? { post_done, hito[6:0] } :
    debug_bus[5:2]==4'h1 ? pcf_hi_q[23:16]          :
    debug_bus[5:2]==4'h2 ? pcf_hi_q[15: 8]          :
    debug_bus[5:2]==4'h3 ? { pcf_hi_q[ 7: 1], 1'b0 }:
    debug_bus[5:2]==4'h4 ? pcf_lo_q[23:16]          :
    debug_bus[5:2]==4'h5 ? pcf_lo_q[15: 8]          :
    debug_bus[5:2]==4'h6 ? { pcf_lo_q[ 7: 1], 1'b0 }:
    debug_bus[5:2]==4'h7 ? daf_hi_q[23:16]          :
    debug_bus[5:2]==4'h8 ? daf_hi_q[15: 8]          :
    debug_bus[5:2]==4'h9 ? { daf_hi_q[ 7: 1], 1'b0 }:
    debug_bus[5:2]==4'hA ? daf_lo_q[23:16]          :
    debug_bus[5:2]==4'hB ? daf_lo_q[15: 8]          :
    debug_bus[5:2]==4'hC ? { daf_lo_q[ 7: 1], 1'b0 }:
    debug_bus[5:2]==4'hD ? frame_id[ 7:0]           :
    debug_bus[5:2]==4'hE ? mw_irq_ctrl              :

    debug_bus[5:2]==4'hF && debug_bus[1:0]==2'd1 ? blit_fires :
    debug_bus[5:2]==4'hF && debug_bus[1:0]==2'd2 ? prot_wr    :
    debug_bus[5:2]==4'hF && debug_bus[1:0]==2'd3 ? { blit_flags[7:2], blit_busy, prot_cs } :
    { rmrd, dma_bsy, mw_irq_ctrl[0], eep_cs, eep_clk, eep_di, 2'd0 };

assign VPAn     = ~(&FC & ~ASn);
assign iack     =  &FC & ~ASn;

assign dtac_mux = DTACKn | ~vdtac | blit_busy;

assign pair_we  = pair_cs & ~RnW & ~LDSn;

`ifdef SIMULATION
reg none_cs;
`endif
always @* begin
    rom_cs    = 0; ram_cs     = 0; objsys_cs   = 0; pcu_cs   = 0; objrom_cs = 0;
    objreg_cs = 0; obj46_cs   = 0; alpha_cs    = 0; tilereg_cs = 0; tilereg_b_cs = 0;
    ccu_cs    = 0; vram_cs    = 0; romrd_cs    = 0; pal_cs   = 0; prot_cs   = 0;
    io40_cs   = 0; io41_cs    = 0; eepw_cs     = 0; ctrl_cs  = 0;
    p1p2_cs   = 0; p3p4_cs    = 0; in0_cs      = 0; in1_cs   = 0;
    pair_cs   = 0; sndirq_cs  = 0;
    if( vldbus ) begin

        rom_cs    = (Abus[23:20]==4'h0) | (Abus[23:20]==4'h3);
        ram_cs    = (Abus[23:16]==8'h10) & ~BUSn;
        objsys_cs = (Abus[23:14]==10'h120);
        pal_cs    = (Abus[23:13]==11'h300);
        vram_cs   = (Abus[23:14]==10'h1a0);
        romrd_cs  = (Abus[23:14]==10'h1c0);
        io40_cs   = (Abus[23:16]==8'h40);
        io41_cs   = (Abus[23:16]==8'h41);
        if( io40_cs ) case( Abus[15:12] )
            4'h0: pcu_cs    = Abus[15:8]==8'h00;
            4'h2: begin
                objrom_cs = ~Abus[4];
                objreg_cs =  Abus[4];
            end
            4'h4: obj46_cs   = 1;
            4'ha: alpha_cs   = 1;
            4'hc: tilereg_cs = 1;
            4'he: prot_cs    = 1;
            default:;
        endcase
        if( io41_cs ) case( Abus[15:12] )
            4'h0: eepw_cs = 1;
            4'h2: ctrl_cs = 1;
            4'h4: begin p1p2_cs = ~Abus[1]; p3p4_cs = Abus[1]; end
            4'h6: begin in0_cs  = ~Abus[1]; in1_cs  = Abus[1]; end
            4'h8: pair_cs = 1;
            4'ha: sndirq_cs = 1;
            4'hc: ccu_cs  = 1;
            4'he: tilereg_b_cs = 1;
            default:;
        endcase
    end
`ifdef SIMULATION
    none_cs = ~BUSn & ~|{ rom_cs, ram_cs, objsys_cs, vram_cs, romrd_cs, pal_cs, prot_cs,
        pcu_cs, objrom_cs, objreg_cs, obj46_cs, alpha_cs, tilereg_cs, tilereg_b_cs,
        ccu_cs, eepw_cs, ctrl_cs, p1p2_cs, p3p4_cs, in0_cs, in1_cs, pair_cs, sndirq_cs };
`endif
end

function [7:0] konami_player( input [6:0] joy, input start );
    konami_player = { start, joy[6:0] };
endfunction
always @(*) begin
    port_in = 16'hffff;
    if( p1p2_cs ) port_in = { konami_player(joystick2, cab_1p[1]), konami_player(joystick1, cab_1p[0]) };
    if( p3p4_cs ) port_in = { konami_player(joystick4, cab_1p[3]), konami_player(joystick3, cab_1p[2]) };

    if( in0_cs  ) port_in = { 8'hff, 2'b11, 1'b1, service, 2'b11, coin[1:0] };

    if( in1_cs  ) port_in = { 8'h00, dipsw[3:0], 1'b0, dip_test, eep_rdy, eep_do };
end

/* verilator tracing_off */

wire [15:0] din_mux =
rom_cs    ? rom_data           :
               ram_cs    ? ram_dout           :
               objsys_cs ? oram_dout          :
               vram_cs   ? vram_dout          :
               romrd_cs  ? vram_dout          :
               pal_cs    ? pal_dout           :
               objrom_cs ? objrom_dout        :

               ctrl_cs   ? 16'h0000 :

               pair_cs   ? {8'hff, pair_dout} :
               ccu_cs    ? {8'hff, ccu_dout } :
               (p1p2_cs|p3p4_cs|in0_cs|in1_cs) ? port_in : 16'hffff;

always @(posedge clk) begin
  if( (rom_cs && !rom_ok) || (ram_cs && !ram_ok) ) begin

  end else begin
    cpu_din <= din_mux;
  end
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        eep_di <= 0; eep_cs <= 0; eep_clk <= 0;
        mw_irq_ctrl <= 0;
        rmrd        <= 0;
    end else begin
        if( eepw_cs & cpu_we & ~UDSn ) begin
            eep_di      <= cpu_dout[ 8];
            eep_cs      <= cpu_dout[ 9];
            eep_clk     <= cpu_dout[10];
            mw_irq_ctrl <= cpu_dout[15:8];
        end

        rmrd <= romrd_cs;
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) sndon <= 0;
    else      sndon <= sndirq_cs & cpu_we;
end

localparam [8:0] IRQ2_LINE = 9'h127, IRQ6_LINE = 9'h0FF;

wire irq_en    = mw_irq_ctrl[6];
wire irq2_edge = vdump==IRQ2_LINE;
wire irq6_edge = (vdump==IRQ6_LINE) & obj_irqen;
wire irq2_q, irq6_q;
wire irq2_ack  = iack & (A[3:1]==3'd2);
wire irq6_ack  = iack & (A[3:1]==3'd6);

jtframe_edge #(.QSET(1)) u_irq2(
    .rst( rst ), .clk( clk ), .edgeof( irq2_edge ), .clr( ~irq_en | irq2_ack ), .q( irq2_q ));
jtframe_edge #(.QSET(1)) u_irq6(
    .rst( rst ), .clk( clk ), .edgeof( irq6_edge ), .clr( ~irq_en | irq6_ack ), .q( irq6_q ));

always @(posedge clk) begin

    IPLn <= irq6_q ? 3'b001 :
            irq2_q ? 3'b101 : 3'b111;
end

`ifndef MC_BLIT_WAIT
`define MC_BLIT_WAIT 2
`endif
localparam [1:0] BLIT_WAIT = `MC_BLIT_WAIT;

reg [1:0] blit_wcnt;
always @(posedge clk, posedge rst) begin
    if( rst )            blit_wcnt <= 2'd0;
    else if( !blit_req ) blit_wcnt <= 2'd0;
    else if( ~&blit_wcnt ) blit_wcnt <= blit_wcnt + 2'd1;
end

assign blit_ok = blit_req & ( ram_cs ? ram_ok : blit_wcnt >= BLIT_WAIT );

reg  prot_fired;
always @(posedge clk, posedge rst) begin
    if( rst ) prot_fired <= 0;
    else if( ASn      ) prot_fired <= 0;
    else if( blit_busy) prot_fired <= 1;
end
wire prot_cs_blit = prot_cs & ~prot_fired;

reg        blit_busy_l, prot_wr_seen;
reg [15:0] blit_hold;
wire       prot_wr_stb = prot_cs & ~RnW & ~ASn & ~blit_busy & ~prot_wr_seen;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        blit_fires<=0; prot_wr<=0; blit_flags<=0;
        blit_busy_l<=0; prot_wr_seen<=0; blit_hold<=0;
    end else begin
        blit_busy_l <= blit_busy;

        if( ASn ) prot_wr_seen <= 0; else if( prot_cs & ~RnW & ~blit_busy ) prot_wr_seen <= 1;

        if( ~blit_busy_l &  blit_busy & ~&blit_fires ) blit_fires <= blit_fires + 8'd1;
        if(  prot_wr_stb            & ~&prot_wr     ) prot_wr    <= prot_wr    + 8'd1;

        if( !blit_busy ) blit_hold <= 0; else if( ~&blit_hold ) blit_hold <= blit_hold + 16'd1;

        if( blit_busy               ) blit_flags[7] <= 1'b1;
        if( prot_wr_stb             ) blit_flags[6] <= 1'b1;
        if( &blit_hold              ) blit_flags[5] <= 1'b1;
        if( blit_ok & ~blit_we      ) blit_flags[4] <= 1'b1;
        if( blit_ok &  blit_we      ) blit_flags[3] <= 1'b1;

        if( blit_busy & blit_req & ~ram_cs ) blit_flags[2] <= 1'b1;
    end
end

/* verilator tracing_off */

`ifdef MC_BLIT_PRESESION8
    wire       cs_blit_w  = prot_cs;
    wire [15:0] din_blit_w = cpu_din;
`else
    wire       cs_blit_w  = prot_cs_blit;
    wire [15:0] din_blit_w = din_mux;
`endif

mtlchamp_k053990 u_prot(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( 1'b1          ),
    .cs         ( cs_blit_w     ),
    .we         ( ~RnW          ),
    .addr       ( A[4:1]        ),
    .din        ( cpu68_dout    ),
    .dsn        ( {UDSn,LDSn}   ),
    .busy       ( blit_busy     ),
    .bus_req    ( blit_req      ),
    .bus_we     ( blit_we       ),
    .bus_addr   ( blit_addr     ),
    .bus_dsn    ( blit_dsn      ),
    .bus_dout   ( blit_dout     ),
    .bus_din    ( din_blit_w    ),
    .bus_ok     ( blit_ok       )
);

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
    .oEdb       ( cpu68_dout  ),

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

reg [15:0] rd_d0, rd_d1, rd_d2, rd_d3;
reg [ 7:0] rd_a0, rd_a1, rd_a2, rd_a3;
reg [ 2:0] rd_idx;
reg [23:1] rd_last;
reg        rd_first;
wire       rd_nueva = rom_cs & rom_ok & ~rd_idx[2] & (rd_first | (A!=rd_last));

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        rd_d0<=0; rd_d1<=0; rd_d2<=0; rd_d3<=0;
        rd_a0<=0; rd_a1<=0; rd_a2<=0; rd_a3<=0;
        rd_idx<=0; rd_last<=0; rd_first<=1;
    end else if( rd_nueva ) begin
        case( rd_idx[1:0] )
            2'd0: begin rd_d0 <= rom_data; rd_a0 <= {A[7:1],1'b0}; end
            2'd1: begin rd_d1 <= rom_data; rd_a1 <= {A[7:1],1'b0}; end
            2'd2: begin rd_d2 <= rom_data; rd_a2 <= {A[7:1],1'b0}; end
            2'd3: begin rd_d3 <= rom_data; rd_a3 <= {A[7:1],1'b0}; end
        endcase
        rd_last  <= A;
        rd_first <= 0;
        rd_idx   <= rd_idx + 3'd1;
    end
end

assign st_rd =
    debug_bus[5:2]==4'h1 ? rd_d0[15:8] : debug_bus[5:2]==4'h2 ? rd_d0[7:0] :
    debug_bus[5:2]==4'h3 ? rd_d1[15:8] : debug_bus[5:2]==4'h4 ? rd_d1[7:0] :
    debug_bus[5:2]==4'h5 ? rd_d2[15:8] : debug_bus[5:2]==4'h6 ? rd_d2[7:0] :
    debug_bus[5:2]==4'h7 ? rd_d3[15:8] : debug_bus[5:2]==4'h8 ? rd_d3[7:0] :
    debug_bus[5:2]==4'h9 ? rd_a0       : debug_bus[5:2]==4'hA ? rd_a1      :
    debug_bus[5:2]==4'hB ? rd_a2       : debug_bus[5:2]==4'hC ? rd_a3      :
    debug_bus[5:2]==4'hD ? { 5'd0, rd_idx } :
    8'd0;

wire       prog_fetch = ~ASn & RnW & FC[1] & ~FC[0];
wire       data_acc   = ~ASn & ~FC[1] & FC[0];
reg [23:1] pc_last, pcf_lo, pcf_hi, daf_lo, daf_hi;
reg [23:1] pcf_lo_q, pcf_hi_q, daf_lo_q, daf_hi_q;
reg [31:0] n_ram_w, n_obj_w, n_vram_w, n_pal_w, n_pcu_w, n_treg_w, n_ack2, n_ack6;
reg [15:0] frame_id;
reg        lvbl_l, busn_l;
wire       wr_stb   = busn_l & ~BUSn & cpu_we;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        pc_last<=0; pcf_lo<=~23'd0; pcf_hi<=0; daf_lo<=~23'd0; daf_hi<=0;
        pcf_lo_q<=0; pcf_hi_q<=0; daf_lo_q<=0; daf_hi_q<=0;
        n_ram_w<=0; n_obj_w<=0; n_vram_w<=0; n_pal_w<=0; n_pcu_w<=0; n_treg_w<=0;
        n_ack2<=0; n_ack6<=0; frame_id<=0; lvbl_l<=0; busn_l<=1;
    end else begin
        lvbl_l <= LVBL;
        busn_l <= BUSn;
        if( data_acc ) begin
            if( A < daf_lo ) daf_lo <= A;
            if( A > daf_hi ) daf_hi <= A;
        end
        if( prog_fetch ) begin
            pc_last <= A;
            if( A < pcf_lo ) pcf_lo <= A;
            if( A > pcf_hi ) pcf_hi <= A;
        end
        if( wr_stb ) begin
            if( ram_cs      ) n_ram_w  <= n_ram_w +1;
            if( objsys_cs   ) n_obj_w  <= n_obj_w +1;
            if( vram_cs     ) n_vram_w <= n_vram_w+1;
            if( pal_cs      ) n_pal_w  <= n_pal_w +1;
            if( pcu_cs      ) n_pcu_w  <= n_pcu_w +1;
            if( tilereg_cs  ) n_treg_w <= n_treg_w+1;
        end
        if( irq2_ack ) n_ack2 <= n_ack2+1;
        if( irq6_ack ) n_ack6 <= n_ack6+1;
        if( lvbl_l & ~LVBL ) begin
            frame_id <= frame_id+1;
`ifdef SIMULATION
            $display("BOOT f=%0d PC=%06x bucle=[%06x-%06x] dato=[%06x-%06x] | wr ram=%0d obj=%0d vram=%0d pal=%0d k55=%0d treg=%0d | irqctl=%02x ack2=%0d ack6=%0d | eep(cs=%0d clk=%0d di=%0d do=%0d)",
                frame_id, {pc_last,1'b0}, {pcf_lo,1'b0}, {pcf_hi,1'b0}, {daf_lo,1'b0}, {daf_hi,1'b0},
                n_ram_w, n_obj_w, n_vram_w, n_pal_w, n_pcu_w, n_treg_w,
                mw_irq_ctrl, n_ack2, n_ack6, eep_cs, eep_clk, eep_di, eep_do);
`endif
            n_ram_w<=0; n_obj_w<=0; n_vram_w<=0; n_pal_w<=0; n_pcu_w<=0; n_treg_w<=0;

            pcf_lo_q <= pcf_lo; pcf_hi_q <= pcf_hi;
            daf_lo_q <= daf_lo; daf_hi_q <= daf_hi;
            pcf_lo <= ~23'd0; pcf_hi <= 0; daf_lo <= ~23'd0; daf_hi <= 0;
        end
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin hito <= 0; post_done <= 0; end
    else if( prog_fetch ) case( {A,1'b0} )
        24'h001220: hito[0] <= 1'b1;
        24'h003584: hito[1] <= 1'b1;
        24'h00401c: hito[2] <= 1'b1;
        24'h004100: hito[3] <= 1'b1;
        24'h004158: hito[4] <= 1'b1;
        24'h00442a: hito[5] <= 1'b1;
        24'h00107a: begin hito[6] <= 1'b1; post_done <= 1'b1; end
        default:;
    endcase
end

`ifdef SIMULATION

reg [6:0] hito_l;
always @(posedge clk) begin
    hito_l <= hito;
    if( hito[0] & ~hito_l[0] ) $display("BOOT-HITO f=%0d 0x001220 init de chips (K055555/K055673/K054338/K056832/K053252)",frame_id);
    if( hito[1] & ~hito_l[1] ) $display("BOOT-HITO f=%0d 0x003584 empieza el POST (D7=0)",frame_id);
    if( hito[2] & ~hito_l[2] ) $display("BOOT-HITO f=%0d 0x00401c tests de MEMORIA terminados -> comando 0xfe al Z80",frame_id);
    if( hito[3] & ~hito_l[3] ) $display("BOOT-HITO f=%0d 0x004100 SALIO del spin del sonido (b7 de soundlatch[2] bajo)",frame_id);
    if( hito[4] & ~hito_l[4] ) $display("*** BOOT FALLA: 0x004158 PANTALLA DE ERROR (D7!=0 memoria, o D6!=0 sonido) ***");
    if( hito[5] & ~hito_l[5] ) $display("BOOT-HITO f=%0d 0x00442a puerta ABIERTA: D7==0 && D6==0 -> jmp $107a",frame_id);
    if( hito[6] & ~hito_l[6] ) $display("*** POST SUPERADO f=%0d: 0x00107a EL JUEGO ARRANCA ***",frame_id);
end

reg [23:1] a_dbg;
reg        rom_cs_dbg, rom_ok_dbg;
reg [15:0] rom_data_dbg;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        a_dbg<=0; rom_cs_dbg<=0; rom_ok_dbg<=0; rom_data_dbg<=0;
    end else begin
        a_dbg        <= A;
        rom_cs_dbg   <= rom_cs;
        rom_ok_dbg   <= rom_ok;
        rom_data_dbg <= rom_data;
    end
end

reg dbg_mirror_seen;
always @(posedge clk, posedge rst) begin
    if( rst ) dbg_mirror_seen <= 0;
    else if( !dbg_mirror_seen && post_done ) begin
        dbg_mirror_seen <= 1;
        $display("[dbg_mirror seed] a=%06x cs=%b ok=%b data=%04x",
            {a_dbg,1'b0}, rom_cs_dbg, rom_ok_dbg, rom_data_dbg);
    end
end

reg [23:1] ff_hist [0:15];
reg [3:0]  ff_idx;
reg        ff_seen;
integer    ff_wait;
reg        ff_dataacc_after;
integer    ff_i;

reg        fetch_ok_d;
reg [23:1] fetch_addr_d;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        fetch_ok_d <= 0; fetch_addr_d <= 0;
    end else begin
        fetch_ok_d   <= prog_fetch && rom_cs && rom_ok;
        fetch_addr_d <= A;
    end
end
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        ff_idx <= 0; ff_seen <= 0; ff_wait <= 0; ff_dataacc_after <= 0;
    end else begin

        if( post_done && fetch_ok_d ) begin
            ff_hist[ff_idx] <= fetch_addr_d;
            ff_idx <= ff_idx + 4'd1;
        end
        if( post_done && !ff_seen && fetch_ok_d && cpu_din==16'hffff ) begin
            ff_seen <= 1;
            ff_wait <= 1;
            $display("FFPROBE: primer opcode 0xFFFF en PC=%06x frame=%0d", {fetch_addr_d,1'b0}, frame_id);
            for( ff_i=0; ff_i<16; ff_i=ff_i+1 )
                $display("FFPROBE hist[-%0d] PC=%06x", 16-ff_i, {ff_hist[(ff_idx+ff_i)&4'hF],1'b0});
        end
        if( ff_wait>0 && ff_wait<64 ) begin
            if( data_acc ) ff_dataacc_after <= 1;
            ff_wait <= ff_wait+1;
        end
        if( ff_wait==64 ) begin
            $display("FFPROBE: acceso a datos en los 64 ciclos tras el 0xFFFF? %0d", ff_dataacc_after);
            ff_wait <= 65;
        end
    end
end
`endif
`else
    initial begin
        rom_cs=0; ram_cs=0; objsys_cs=0; pcu_cs=0; objrom_cs=0; objreg_cs=0; obj46_cs=0;
        alpha_cs=0; tilereg_cs=0; tilereg_b_cs=0; ccu_cs=0; vram_cs=0; romrd_cs=0;
        pal_cs=0; rmrd=0; sndon=0;
    end
    assign
        main_addr = 0,
        ram_dsn   = 0,
        cpu_dout  = 0,
        cpu_we    = 0,
        pair_we   = 0,
        nv_addr   = 0,
        nv_din    = 0,
        nv_we     = 0,
        st_rd     = 0,
        st_dout   = 0;
`endif
endmodule
