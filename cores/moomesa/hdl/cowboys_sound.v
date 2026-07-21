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

module cowboys_sound(
    input           rst,
    input           clk,
    input           cen_8,
    input           cen_4,
    input           cen_2,
    input           cen_pcm,

    input           pair_we,
    // communication with main CPU
    input   [ 7:0]  main_dout,  // bus access for Punk Shot
    output  [ 7:0]  main_din,
    output  [ 7:0]  pair_dout,
    input   [ 4:1]  main_addr,
    input           main_rnw,

    input           snd_irq,
    // ROM
    output  [16:0]  rom_addr,
    output  reg     rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,
    // ADPCM ROM
    output   [20:0] pcm_addr,
    input    [ 7:0] pcm_dout,
    output          pcm_cs,
    input           pcm_ok,
    // Sound output — CANALES SEPARADOS hacia el rcmix de jtframe (mem.yaml: fm + pcm).
    // Antes salia un solo `k539_l/r` con FM+PCM ya sumados dentro del k054539 (railaba el clip16).
    // Ahora cada uno va por su canal -> jtframe mezcla en precision ancha, sin comprometer headroom.
    output     signed [15:0] fm_l,  fm_r,   // YM2151 (jt51), trim vivo debug_bus[3:0]
    output     signed [15:0] pcm_l, pcm_r,  // K054539 PCM puro, trim vivo debug_bus[7:4] (en el modulo)
    // Debug
    input    [ 7:0] debug_bus,
    output   [ 7:0] st_dout
);

assign main_din = 0;

`ifndef NOSOUND
wire        [ 7:0]  cpu_dout, cpu_din,  ram_dout, fm_dout,
                    k39_dout, latch_dout;
wire        [ 3:0]  rom_hi;
reg         [ 3:0]  bank;
wire        [15:0]  A;
wire                m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, nmi_n,
                    cpu_cen, cen_g, fm_intn, latch_we, cen_fm, cen_fm2,
                    latch_intn, int_n, nmi_trig, nmi_clr;
reg                 ram_cs, fm_cs,  k39_cs, mem_acc,
                    nmi_clrr, bank_we, k21_cs;
wire  signed [15:0] fmx_l, fmx_r;   // salida cruda del jt51 (antes de trim)

// trim de FM en vivo: (FM*fg)>>3, con clamp. fg de debug_bus[3:0], default 8 = UNIDAD.
// El balance base FM/PCM lo fija el rcmix (mem.yaml); esto es solo el ajuste fino en vivo.
wire [4:0] fm_g = (debug_bus[3:0]==4'd0) ? 5'd8 : {1'b0, debug_bus[3:0]};
function signed [15:0] fmtrim(input signed [15:0] s, input [4:0] g);
    reg signed [23:0] p;
    begin
        p = (s*$signed({1'b0,g})) >>> 3;
        fmtrim = (p >  24'sd32767) ? 16'sd32767 :
                 (p < -24'sd32768) ? -16'sd32768 : p[15:0];
    end
endfunction
assign fm_l = fmtrim(fmx_l, fm_g);
assign fm_r = fmtrim(fmx_r, fm_g);

assign int_n    = latch_intn;
assign nmi_trig = fm_intn;
assign nmi_clr  = nmi_clrr;
assign latch_we = k21_cs && !wr_n;
assign rom_hi   = A[15]? bank : {3'd0, A[14]};
assign rom_addr = {rom_hi[2:0], A[13:0]};
assign cpu_din  = rom_cs ? rom_data   :
                  ram_cs ? ram_dout   :
                  k39_cs ? k39_dout   :
                  k21_cs ? latch_dout :
                  fm_cs  ? fm_dout    : 8'hff;
assign cen_fm   = cen_4;
assign cen_fm2  = cen_2;
assign cen_g    = (ram_cs | rom_cs) ? cen_4 : cen_8; // wait state for RAM/ROM access
// this is not 100% accurate, but quite close. It does not seem to have much of
// an effect anyway.

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bank <= 0;
    end else begin
        if( bank_we ) { nmi_clrr, bank } <= cpu_dout[4:0];
    end
end

always @(*) begin
    mem_acc = !mreq_n && rfsh_n;
    rom_cs  = mem_acc && ((!A[15] && A[14]) || !A[14]) && !rd_n;
    ram_cs  = mem_acc && A[15:13]==3'b110;
    fm_cs   = mem_acc && A[15:12]==4'he &&  A[11];
    k39_cs  = mem_acc && A[15:12]==4'he && !A[11];
    k21_cs  = mem_acc && A[15:12]==4'hf && !A[11];
    bank_we = mem_acc && A[15:12]==4'hf &&  A[11] && !A[10];
end

// ---------------------------------------------------------------------------
// SONDA (solo sim): captura las escrituras/lecturas del Z80 al k054539 para
// compararlas con la traza REAL de MAME (debug/k539_trace.txt). Confirma si el
// Z80 del core programa el chip IGUAL que MAME (bug interno) o DISTINTO (bug
// aguas arriba). reg = A-0xe000 (0x000-0x22f), formato identico al tap de MAME.
// Inocua para sintesis (bajo `ifdef SIMULATION`).
// ---------------------------------------------------------------------------
`ifdef SIMULATION
integer fk39_w, fk39_r, flatch;
reg     k39w_d, k39r_d, k21r_d;
initial begin
    fk39_w = $fopen("k539_core_writes.txt","w");
    fk39_r = $fopen("k539_core_reads.txt","w");
    flatch = $fopen("snd_latch_reads.txt","w");
    k39w_d = 0; k39r_d = 0; k21r_d = 0;
end
always @(posedge clk) begin
    k39w_d <= k39_cs && !wr_n;
    k39r_d <= k39_cs && !rd_n;
    k21r_d <= k21_cs && !rd_n;
    if( (k39_cs && !wr_n) && !k39w_d )  // flanco: 1 log por ciclo de bus
        $fwrite(fk39_w, "%03x %02x\n", A[10:0] & 11'h3ff, cpu_dout);
    if( (k39_cs && !rd_n) && !k39r_d )
        $fwrite(fk39_r, "%03x\n", A[10:0] & 11'h3ff);
    // lecturas del latch de comandos (68k->Z80): A[1:0] + dato leido + estado IRQ
    if( (k21_cs && !rd_n) && !k21r_d )
        $fwrite(flatch, "addr=%01x din=%02x intn=%b\n", A[1:0], latch_dout, int_n);
end
`endif

jtframe_edge #(.QSET(0)) u_edge (
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( nmi_trig  ),
    .clr    ( nmi_clr   ),
    .q      ( nmi_n     )
);
/* verilator tracing_off */
jtframe_sysz80 #(`ifdef SND_RAMW .RAM_AW(`SND_RAMW), `endif .CLR_INT(1)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_g     ),
    .cpu_cen    ( cpu_cen   ),
    .int_n      ( int_n     ),
    .nmi_n      ( nmi_n     ),
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
    // ROM access
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);
/* verilator tracing_off */
jt51 u_jt51(
    .rst        ( rst       ), // reset
    .clk        ( clk       ), // main clock
    .cen        ( cen_fm    ),
    .cen_p1     ( cen_fm2   ),
    .cs_n       ( !fm_cs    ), // chip select
    .wr_n       ( wr_n      ), // write
    .a0         ( A[0]      ),
    .din        ( cpu_dout  ), // data in
    .dout       ( fm_dout   ), // data out
    .ct1        (           ),
    .ct2        (           ),
    .irq_n      ( fm_intn   ),
    // Low resolution output (same as real chip)
    .sample     (           ), // marks new output sample
    .left       (           ),
    .right      (           ),
    // Full resolution output
    .xleft      ( fmx_l     ),
    .xright     ( fmx_r     )
);

/* verilator tracing_on */
wire [2:0] nc;

k054539 #(.VOLSHIFT(1)) u_k054539(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_pcm   ),
    .timeout    (           ),
    // CPU interface
    .addr       ({A[9],A[7:0]}),
    .we         ( ~wr_n     ),
    .rd         ( ~rd_n     ),
    .cs         ( k39_cs    ),
    .din        ( cpu_dout  ),
    .dout       ( k39_dout  ),
    // ROM
    .rom_cs     ( pcm_cs    ),
    .rom_addr   ({nc,pcm_addr}),
    .rom_data   ( pcm_dout  ),
    .rom_ok     ( pcm_ok    ),
    // Sound output (PCM puro — la FM va por su propio canal, ya no entra aqui)
    .left       ( pcm_l     ),
    .right      ( pcm_r     ),
    // debug
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_dout   )
);

jt054321 u_54321(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .maddr      ( main_addr ),
    .mdout      ( main_dout ),
    .mdin       ( pair_dout ),
    .mwe        ( pair_we   ),

    .saddr      ( A[1:0]    ),
    .sdout      ( cpu_dout  ),
    .sdin       ( latch_dout),
    .swe        ( latch_we  ),

    // Z80 bus control
    .snd_on     ( snd_irq   ),
    .siorq_n    ( iorq_n    ),
    .int_n      ( latch_intn)
);
`else
assign  main_din = 0;
assign  pcm_addr = 0;
assign  pcm_cs   = 0;
assign  rom_addr = 0;
assign  st_dout  = 0;
initial rom_cs   = 0;
assign  { pair_dout, fm_l, fm_r, pcm_l, pcm_r } = 0;
`endif
endmodule
