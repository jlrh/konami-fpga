/*  This file is part of JTCORES.  GPLv3.

    jtasterix_sound — subsistema de sonido de ASTERIX (Fase 3).
    Z80 @6MHz (24/4) + YM2151 @4MHz (32/8, jt51) + K053260 @4MHz (32/8, jt053260).

    ⚠ ES BOOT-GATE (research/POST-ANALYSIS.md): el POST del 68k manda 0xfe a los puertos main->sub
    (0x380201/0x380203) + IRQ (0x380300) y ESPERA la respuesta del Z80 en el puerto sub->main
    (`btst #7,$380201`, luego bits 0 y 1). Si el Z80 no arranca y contesta -> D7!=0 -> cuelgue en 0x5030.

    Derivado de `jtriders_sound` (rama ssriders: mismo Z80+jt51+jt053260, hermano ya validado).
    DELTA de asterix (asterix.cpp:319 sound_map):
      0000-EFFF ROM | F000-F7FF RAM | F801 YM2151 status/data | FA00-FA2F K053260
      FC00 sound_arm_nmi | **FE00 YM2151 address**
    En riders el YM2151 está sólo en F8xx; asterix parte el chip en DOS ventanas: el ADDRESS en FE00
    y el DATA/STATUS en F801. Por eso `fm_cs` cubre F8xx **y** FExx, y el `a0` del jt51 sale de A[0],
    que vale 1 en F801 (data) y 0 en FE00 (address) — justo lo que necesita el chip.
*/
module jtasterix_sound(
    input                    rst,
    input                    clk,
    input                    cen_6,
    input                    cen_fm,
    input                    cen_fm2,
    input                    cen_pcm,

    input        [ 7:0]      main_dout,
    output       [ 7:0]      main_din,
    input                    main_wrn,
    input        [ 1:0]      main_addr,
    input                    snd_irq,

    output       [15:0]      rom_addr,
    output                   rom_cs,
    input        [ 7:0]      rom_data,
    input                    rom_ok,

    output       [20:0]      pcma_addr, pcmb_addr, pcmc_addr, pcmd_addr,
    output                   pcma_cs,   pcmb_cs,   pcmc_cs,   pcmd_cs,
    input        [ 7:0]      pcma_data, pcmb_data, pcmc_data, pcmd_data,
    input                    pcma_ok,   pcmb_ok,   pcmc_ok,   pcmd_ok,

    output signed [15:0]     fm_l,  fm_r,
    output signed [15:0]     pcm_l, pcm_r,

    input        [ 5:0]      snd_en,
    input        [ 7:0]      debug_bus,
    output       [ 7:0]      st_dout
);
`ifndef NOSOUND
wire [ 7:0] cpu_dout, cpu_din, ram_dout, fm_dout, k60_dout;
wire [15:0] A;
wire        m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, nmi_n, int_n,
            cpu_cen, k60_sample, tim2, upper4k, mem_acc, mem_upper,
            mem_f8, mem_fa, mem_fc, mem_fe, cen_ws, wait_cs, wait_clr, skip_cen;
reg         ram_cs, fm_cs, k60_cs, nmi_cs, rom_cs_r, cen_g;
wire signed [15:0] fm_l_raw, fm_r_raw, pcm_l_raw, pcm_r_raw;

assign rom_cs   = rom_cs_r;
assign int_n    = ~snd_irq;
assign rom_addr = A[15:0];
assign upper4k  = &A[15:12];
assign mem_acc  = !mreq_n && rfsh_n;
assign mem_upper= mem_acc && upper4k;
assign mem_f8   = mem_upper && A[11:9]==3'd4;
assign mem_fa   = mem_upper && A[11:9]==3'd5;
assign mem_fc   = mem_upper && A[11:9]==3'd6;
assign mem_fe   = mem_upper && A[11:9]==3'd7;
assign cpu_din  = rom_cs_r ? rom_data :
                  ram_cs   ? ram_dout :
                  k60_cs   ? k60_dout :
                  fm_cs    ? fm_dout  : 8'h0;
assign st_dout  = 8'd0;

always @* begin
    rom_cs_r = mem_acc   && !upper4k && !rd_n;
    ram_cs   = mem_upper && !A[11];
    fm_cs    = mem_f8 | mem_fe;
    k60_cs   = mem_fa;
    nmi_cs   = mem_fc;
end

assign wait_cs  = rom_cs_r | ram_cs;
assign wait_clr = cen_6 & skip_cen;
assign cen_ws   = cen_6 & ~skip_cen;
always @(posedge clk) cen_g <= cen_ws;

jtframe_edge u_wait(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( wait_cs   ),
    .clr    ( wait_clr  ),
    .q      ( skip_cen  )
);

reg [5:0] sh1_cnt;
always @(posedge clk, posedge rst) begin
    if( rst ) sh1_cnt <= 0;
    else if( cen_pcm ) sh1_cnt <= sh1_cnt + 1'd1;
end
wire sh1 = sh1_cnt[5:4]==2'd0;

jtframe_edge #(.QSET(0),.ATRST(0)) u_nmi(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( sh1       ),
    .clr    ( nmi_cs    ),
    .q      ( nmi_n     )
);

/* verilator tracing_off */
jtframe_sysz80 #(.RAM_AW(11), .CLR_INT(1), .RECOVERY(1)) u_cpu(
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
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs_r  ),
    .rom_ok     ( rom_ok    )
);

/* verilator tracing_off */
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
    .irq_n      (           ),
    .sample     (           ),
    .left       (           ),
    .right      (           ),
    .xleft      ( fm_l_raw  ),
    .xright     ( fm_r_raw  )
);

/* verilator tracing_on */

jt053260 u_k053260(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_pcm   ),

    .ma0        (main_addr[0]),
    .mrdnw      ( main_wrn  ),
    .mcs        ( 1'b1      ),
    .mdin       ( main_din  ),
    .mdout      ( main_dout ),

    .addr       ( A[5:0]    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .cs         ( k60_cs    ),
    .dout       ( k60_dout  ),
    .din        ( cpu_dout  ),

    .roma_addr  ( pcma_addr ), .roma_data( pcma_data ), .roma_cs( pcma_cs ),
    .romb_addr  ( pcmb_addr ), .romb_data( pcmb_data ), .romb_cs( pcmb_cs ),
    .romc_addr  ( pcmc_addr ), .romc_data( pcmc_data ), .romc_cs( pcmc_cs ),
    .romd_addr  ( pcmd_addr ), .romd_data( pcmd_data ), .romd_cs( pcmd_cs ),

    .aux_l      ( 16'd0     ),
    .aux_r      ( 16'd0     ),
    .snd_l      ( pcm_l_raw ),
    .snd_r      ( pcm_r_raw ),
    .sample     ( k60_sample),
    .tim2       ( tim2      ),
    .ch_en      ( snd_en[5:1])
);

`ifdef BOOTPROBE

reg [31:0] bootprobe_scyc;
reg        bootprobe_wseen;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bootprobe_scyc  <= 0;
        bootprobe_wseen <= 0;
    end else begin
        bootprobe_scyc <= bootprobe_scyc + 1'd1;
        if( k60_cs && !wr_n && A[5:0]==6'h2 && !bootprobe_wseen ) begin
            bootprobe_wseen <= 1;
            $display("BOOTPROBE Z80 first ps2m[0] WRITE: cyc=%0d val=%02x", bootprobe_scyc, cpu_dout);
        end
    end
end
`endif

`ifdef JTFRAME_DEBUG_SOUND_TUNE
wire [3:0] dbg_gfm  = debug_bus[3:0];
wire [3:0] dbg_gpcm = debug_bus[7:4];

wire signed [20:0] fm_l_sc  = (fm_l_raw  * $signed({1'b0,dbg_gfm }) ) >>> 3;
wire signed [20:0] fm_r_sc  = (fm_r_raw  * $signed({1'b0,dbg_gfm }) ) >>> 3;
wire signed [20:0] pcm_l_sc = (pcm_l_raw * $signed({1'b0,dbg_gpcm}) ) >>> 3;
wire signed [20:0] pcm_r_sc = (pcm_r_raw * $signed({1'b0,dbg_gpcm}) ) >>> 3;

assign fm_l  = fm_l_sc  > 21'sd32767 ? 16'sd32767 : (fm_l_sc  < -21'sd32768 ? -16'sd32768 : fm_l_sc [15:0]);
assign fm_r  = fm_r_sc  > 21'sd32767 ? 16'sd32767 : (fm_r_sc  < -21'sd32768 ? -16'sd32768 : fm_r_sc [15:0]);
assign pcm_l = pcm_l_sc > 21'sd32767 ? 16'sd32767 : (pcm_l_sc < -21'sd32768 ? -16'sd32768 : pcm_l_sc[15:0]);
assign pcm_r = pcm_r_sc > 21'sd32767 ? 16'sd32767 : (pcm_r_sc < -21'sd32768 ? -16'sd32768 : pcm_r_sc[15:0]);
`else
assign fm_l  = fm_l_raw;
assign fm_r  = fm_r_raw;
assign pcm_l = pcm_l_raw;
assign pcm_r = pcm_r_raw;
`endif

wire _unused = &{1'b0, m1_n, iorq_n, cpu_cen, tim2, debug_bus,
                 pcma_ok, pcmb_ok, pcmc_ok, pcmd_ok, main_addr[1], 1'b0};

`ifdef SIMULATION

reg  [7:0]  fm_reg=0, fm_st_max=0;
reg         fm_wr_l=0, fm_rd_l=0;
integer     n_fmw=0, n_fmr=0;
always @(posedge clk) begin
    fm_wr_l <= fm_cs & ~wr_n;
    fm_rd_l <= fm_cs & ~rd_n;
    if( (fm_cs & ~wr_n) & ~fm_wr_l ) begin
        if( !A[0] ) fm_reg <= cpu_dout;
        else begin
            n_fmw <= n_fmw+1;
            if( n_fmw<120 ) $display("FM-W reg=%02x dato=%02x", fm_reg, cpu_dout);
        end
    end
    if( (fm_cs & ~rd_n) & ~fm_rd_l ) begin
        n_fmr <= n_fmr+1;
        if( fm_dout>fm_st_max ) fm_st_max <= fm_dout;
        if( n_fmr<8 || n_fmr%200000==0 )
            $display("FM-R status=%02x (lecturas=%0d, status_max=%02x)", fm_dout, n_fmr, fm_st_max);
    end
end

reg  [7:0]  k60_keyon=0;
reg         k60_wr_l=0;
integer     n_k60w=0, n_keyon=0;
always @(posedge clk) begin
    k60_wr_l <= k60_cs & ~wr_n;
    if( (k60_cs & ~wr_n) & ~k60_wr_l ) begin
        n_k60w <= n_k60w+1;
        if( A[5:0]==6'h28 ) begin
            n_keyon  <= n_keyon+1;
            k60_keyon<= k60_keyon | cpu_dout;
            $display("K60-KEYON dato=%02x (escrituras a 0x28=%0d, acumulado=%02x)",
                     cpu_dout, n_keyon, k60_keyon|cpu_dout);
        end
        if( n_k60w<60 ) $display("K60-W reg=%02x dato=%02x", A[5:0], cpu_dout);
    end
end

reg  [ 7:0] shdw[0:2047];
reg  [15:0] last_ra;
reg  [15:0] fhist[0:7];
reg  [ 2:0] fptr;
reg         zrd_l;
reg         m1f_l;
reg         k60w_l2;
integer     n_mis, n_fetch, n_quien, kk;
wire        zwr = ram_cs & ~wr_n;
wire        zrd = ram_cs & ~rd_n;
wire        m1f = ~m1_n & ~mreq_n & ~rd_n & rfsh_n;
initial begin
    n_mis = 0; n_fetch = 0; n_quien = 0; last_ra = 0; zrd_l = 0; m1f_l = 0; k60w_l2 = 0; fptr = 0;
    for( kk=0; kk<2048; kk=kk+1 ) shdw[kk] = 8'h00;
    for( kk=0; kk<8;    kk=kk+1 ) fhist[kk] = 16'd0;
end

reg  romf_l;
integer n_romf;
initial begin n_romf = 0; romf_l = 0; end
always @(posedge clk) begin
    romf_l <= rom_cs_r & rom_ok;
    if( (rom_cs_r & rom_ok) && !romf_l && n_romf<40 ) begin
        n_romf <= n_romf+1;
        $display("Z80-ROMF[%0d] addr=%04x data=%02x", n_romf, A, rom_data);
    end
end

always @(posedge clk) begin
    zrd_l <= zrd;
    m1f_l <= m1f;
    if( m1f && !m1f_l ) begin
        n_fetch      <= n_fetch+1;
        fhist[fptr]  <= A;
        fptr         <= fptr+1'd1;
    end

    k60w_l2 <= k60_cs & ~wr_n;
    if( k60_cs && !wr_n && !k60w_l2 && A[5:0]<=6'h03 && n_quien<64 ) begin
        n_quien <= n_quien+1;
        $display("Z80-QUIEN: escribe fa%02x=%02x  fetches=%0d  ultimos PC: %04x %04x %04x %04x %04x %04x %04x %04x",
                 A[7:0], cpu_dout, n_fetch,
                 fhist[fptr-3'd1], fhist[fptr-3'd2], fhist[fptr-3'd3], fhist[fptr-3'd4],
                 fhist[fptr-3'd5], fhist[fptr-3'd6], fhist[fptr-3'd7], fhist[fptr]);
    end
    if( zwr ) shdw[A[10:0]] <= cpu_dout;
    if( zrd ) begin
        last_ra <= A;

        if( zrd_l && ram_dout !== shdw[A[10:0]] && n_mis<16 ) begin
            n_mis <= n_mis+1;
            $display("Z80-RAM MISMATCH @%04x leido=%02x esperado=%02x  t=%0t", A, ram_dout, shdw[A[10:0]], $time);
        end
    end
    if( m1f && !m1f_l ) case(A)
        16'h06f0: $display("Z80-POST: arranca autotest         t=%0t", $time);
        16'h0708: $display("Z80-POST: fin barrido checksum ROM t=%0t", $time);
        16'h0711: $display("Z80-POST: *** CHECKSUM ROM MAL *** t=%0t", $time);
        16'h0715: $display("Z80-POST: arranca TEST DE RAM      t=%0t", $time);
        16'h0729: $display("Z80-POST: TEST DE RAM ***OK***     t=%0t", $time);
        16'h072d: $display("Z80-POST: *** TEST DE RAM MAL ***  ultima dir RAM=%04x  t=%0t", last_ra, $time);
        16'h0762: $display("Z80-POST: arma NMI (escribe FC00)  t=%0t", $time);
        default:;
    endcase
end

reg m1_l=0, k60w_l=0, nmi_l=1;
wire iack_now = ~m1_n & ~iorq_n;
wire k60w_now = k60_cs & ~wr_n;
integer n_iack=0, n_nmi=0, n_hb=0;
always @(posedge clk) begin
    m1_l <= iack_now; k60w_l <= k60w_now; nmi_l <= nmi_n;
    if( iack_now && !m1_l ) begin
        n_iack <= n_iack+1;
        if( n_iack<12 ) $display("Z80: ACEPTA IRQ (#%0d) A=%04x", n_iack, A);
    end
    if( !nmi_n && nmi_l ) n_nmi <= n_nmi+1;
    if( k60w_now && !k60w_l && A[5:0]<=6'h03 )
        $display("Z80: escribe K053260 reg %02x = %02x  (regs 2/3 = respuesta al 68k)", A[5:0], cpu_dout);
    n_hb <= n_hb+1;
    if( n_hb % 4000000 == 0 )
        $display("Z80-HB: A=%04x int_n=%b nmi_n=%b iacks=%0d nmis=%0d fetches=%0d ultimoPC=%04x",
                 A, int_n, nmi_n, n_iack, n_nmi, n_fetch, fhist[fptr-3'd1]);
end
`endif

`else
assign main_din  = 8'hff;
assign rom_addr  = 16'd0;
assign rom_cs    = 1'b0;
assign pcma_addr = 21'd0; assign pcmb_addr = 21'd0;
assign pcmc_addr = 21'd0; assign pcmd_addr = 21'd0;
assign pcma_cs   = 1'b0;  assign pcmb_cs   = 1'b0;
assign pcmc_cs   = 1'b0;  assign pcmd_cs   = 1'b0;
assign fm_l      = 16'sd0; assign fm_r  = 16'sd0;
assign pcm_l     = 16'sd0; assign pcm_r = 16'sd0;
assign st_dout   = 8'd0;
`endif
endmodule
