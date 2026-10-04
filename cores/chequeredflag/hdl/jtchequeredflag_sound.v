/*  This file is part of the Chequered Flag core for MiSTer.
    GPLv3. Adaptado de jtajax_sound.v (jotego, GPLv3). */

module jtchequeredflag_sound(
    input           rst,
    input           clk,
    input           cen_fm,
    input           cen_fm2,

    input   [ 7:0]  snd_latch, snd_latch2,
    input           snd_irq,

    output  [14:0]  rom_addr,
    output  reg     rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,

    output  [18:0]  pcma_addr, pcmb_addr,
    input   [ 7:0]  pcma_dout, pcmb_dout,
    output          pcma_cs, pcmb_cs,
    input           pcma_ok, pcmb_ok,

    output  [18:0]  pcm2a_addr, pcm2b_addr,
    input   [ 7:0]  pcm2a_dout, pcm2b_dout,
    output          pcm2a_cs, pcm2b_cs,
    input           pcm2a_ok, pcm2b_ok,

    output signed [15:0] fm_l, fm_r,
    output signed [10:0] pcm1_l, pcm1_r, pcm2_l, pcm2_r,
    input    [ 7:0] debug_bus
);

wire        [ 7:0] cpu_dout, ram_dout, fm_dout;
wire        [15:0] A;
reg         [ 7:0] cpu_din;
wire               m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, cpu_cen, fm_irq_n;
reg                ram_cs, bank_cs, dac1_cs, dac2_cs, fm_cs, lat1_cs, lat2_cs, mem_acc;
reg         [ 7:0] pcm_bank, extvol;
reg                int_pend;
wire signed [10:0] p1a, p1b, p2a, p2b;

assign rom_addr = A[14:0];
assign pcma_addr [18:17] = pcm_bank[5:4];
assign pcmb_addr [18:17] = pcm_bank[7:6];
assign pcm2a_addr[18:17] = pcm_bank[1:0];
assign pcm2b_addr[18:17] = pcm_bank[3:2];

reg  [ 7:0] vol1, vol2;
wire signed [ 6:0] r1a = p1a[6:0], r1b = p1b[6:0], r2a = p2a[6:0], r2b = p2b[6:0];
wire signed [11:0] c1l = r1a * $signed({1'b0, vol1[3:0]})   + r1b * $signed({1'b0, extvol[3:0]});
wire signed [11:0] c1r = r1a * $signed({1'b0, vol1[7:4]})   + r1b * $signed({1'b0, extvol[7:4]});
wire signed [11:0] c2  = r2a * $signed({1'b0, vol2[7:4]})   + r2b * $signed({1'b0, vol2[3:0]});

assign pcm1_l = c1l >>> 1, pcm1_r = c1r >>> 1;
assign pcm2_l = c2  >>> 1, pcm2_r = c2  >>> 1;

always @(*) begin
    mem_acc = !mreq_n && rfsh_n;
    rom_cs  = mem_acc && !A[15];
    ram_cs  = mem_acc && A[15:12]==4'h8 && A[11]==0;
    bank_cs = mem_acc && A[15:12]==4'h9;
    dac1_cs = mem_acc && A[15:12]==4'ha && A[7:4]==0;
    dac2_cs = mem_acc && A[15:12]==4'hb && A[7:4]==0;
    fm_cs   = mem_acc && A[15:12]==4'hc;
    lat1_cs = mem_acc && A[15:12]==4'hd;
    lat2_cs = mem_acc && A[15:12]==4'he;
end

always @(*) begin
    case(1'b1)
        rom_cs:  cpu_din = rom_data;
        ram_cs:  cpu_din = ram_dout;
        lat1_cs: cpu_din = snd_latch;
        lat2_cs: cpu_din = snd_latch2;
        fm_cs:   cpu_din = fm_dout;
        default: cpu_din = 8'hff;
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        pcm_bank <= 0;
        extvol   <= 0; vol1 <= 0; vol2 <= 0;
        int_pend <= 0;
    end else begin
        if( snd_irq ) int_pend <= 1;
        if( lat2_cs && !rd_n ) int_pend <= 0;
        if( bank_cs && !wr_n ) pcm_bank <= cpu_dout;
        if( mem_acc && A[15:12]==4'ha && A[4:0]==5'h1c && !wr_n ) extvol <= cpu_dout;
        if( dac1_cs && A[3:0]==4'hc && !wr_n ) vol1 <= cpu_dout;
        if( dac2_cs && A[3:0]==4'hc && !wr_n ) vol2 <= cpu_dout;
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cpu_cen    ( cpu_cen   ),
    .int_n      ( ~int_pend ),
    .nmi_n      ( fm_irq_n  ),
    .busrq_n    ( 1'b1      ),
    .m1_n       ( m1_n      ),
    .mreq_n     ( mreq_n    ),
    .iorq_n     ( iorq_n    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .rfsh_n     ( rfsh_n    ),
    .halt_n     (           ),
    .busak_n    (           ),
    .A          ( A         ),
    .cpu_din    ( cpu_din   ),
    .cpu_dout   ( cpu_dout  ),
    .ram_dout   ( ram_dout  ),
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

jt51 u_jt51(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cen_p1     ( cen_fm2   ),
    .cs_n       ( !fm_cs    ),
    .wr_n       ( wr_n      ),
    .a0         ( A[0]      ),
    .din        ( cpu_dout  ),
    .dout       ( fm_dout   ),
    .ct1        (           ),
    .ct2        (           ),
    .irq_n      ( fm_irq_n  ),
    .sample     (           ),
    .left       (           ),
    .right      (           ),
    .xleft      ( fm_l      ),
    .xright     ( fm_r      )
);

jt007232 #(.REG12A(0),.NOGAIN(1)) u_pcm1(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .addr       ( A[3:0]    ),
    .dacs       ( dac1_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( wr_n      ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( pcma_addr[16:0] ),
    .roma_dout  ( pcma_dout ),
    .roma_cs    ( pcma_cs   ),
    .roma_ok    ( pcma_ok   ),
    .romb_addr  ( pcmb_addr[16:0] ),
    .romb_dout  ( pcmb_dout ),
    .romb_cs    ( pcmb_cs   ),
    .romb_ok    ( pcmb_ok   ),
    .snda       ( p1a       ),
    .sndb       ( p1b       ),
    .snd        (           ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);

jt007232 #(.REG12A(0),.NOGAIN(1)) u_pcm2(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .addr       ( A[3:0]    ),
    .dacs       ( dac2_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( wr_n      ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( pcm2a_addr[16:0] ),
    .roma_dout  ( pcm2a_dout ),
    .roma_cs    ( pcm2a_cs   ),
    .roma_ok    ( pcm2a_ok   ),
    .romb_addr  ( pcm2b_addr[16:0] ),
    .romb_dout  ( pcm2b_dout ),
    .romb_cs    ( pcm2b_cs   ),
    .romb_ok    ( pcm2b_ok   ),
    .snda       ( p2a       ),
    .sndb       ( p2b       ),
    .snd        (           ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);

`ifdef SIMULATION

integer snd_f, nfetch=0, nfm=0, np1=0, np2=0, nlat=0;
reg mreq_l=1, wr_l=1;
initial snd_f = $fopen("snd_io.log","w");
always @(posedge clk) begin
    mreq_l <= mreq_n; wr_l <= wr_n;
    if( rom_cs && rom_ok && !m1_n && nfetch < 8 && mreq_l==0 && cpu_cen ) begin
        $fdisplay(snd_f, "fetch %04X = %02X", A, rom_data); $fflush(snd_f); nfetch = nfetch + 1;
    end
    if( !wr_n && wr_l ) begin
        if( fm_cs ) nfm = nfm + 1;
        if( dac1_cs ) np1 = np1 + 1;
        if( dac2_cs ) np2 = np2 + 1;
        if( (nfm + np1 + np2) % 500 == 1 ) begin
            $fdisplay(snd_f, "escrituras: ym2151=%0d 007232#1=%0d 007232#2=%0d", nfm, np1, np2); $fflush(snd_f);
        end
    end
end
`endif

endmodule
