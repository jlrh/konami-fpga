module mystwarr_sound(
    input               rst,
    input               clk,
    input               cen_8,
    input               cen_pcm,

    input      [ 4:1]   main_addr,
    input      [ 7:0]   main_dout,
    input               pair_we,
    output     [ 7:0]   pair_dout,
    input               sndon,

    output     [16:0]   rom_addr,
    output reg          rom_cs,
    input      [ 7:0]   rom_data,
    input               rom_ok,

    output     [21:0]   pcm_addr,
    output              pcm_cs,
    input      [ 7:0]   pcm_data,
    input               pcm_ok,

    output signed [15:0] pcm1_l, pcm1_r,
    output signed [15:0] pcm2_l, pcm2_r,

    input      [ 7:0]   debug_bus,
    output     [ 7:0]   st_dout
);

wire [ 7:0] cpu_dout, cpu_din, ram_dout, k39a_dout, k39b_dout, latch_dout, k39a_ram_dout, k39b_ram_dout;
wire [15:0] A;
wire        m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, nmi_n, int_n, latch_we;
wire        cpu_cen;
reg         ram_cs, k39a_cs, k39b_cs, k21_cs, ctrl_we;
wire        mem_acc = !mreq_n && rfsh_n;
reg  [16:0] rom_hi;

reg  [4:0]  sound_ctrl;

always @(*) begin
    rom_cs   = mem_acc && !rd_n && (!A[15] || (A[15]&~A[14]));
    ram_cs   = mem_acc && A[15:13]==3'b110;
    k39a_cs  = mem_acc && A[15:10]==6'b111000;
    k39b_cs  = mem_acc && A[15:10]==6'b111001;
    k21_cs   = mem_acc && A[15:2]==14'b11_1100_0000_0000;
    ctrl_we  = mem_acc && !wr_n && A==16'hF800;

    rom_hi   = A[15] ? {sound_ctrl[2:0], A[13:0]} : {2'd0, A[14:0]};
end
assign rom_addr = rom_hi[16:0];

wire k39a_reg = k39a_cs && (A[9:0] < 10'h230);
wire k39b_reg = k39b_cs && (A[9:0] < 10'h230);
wire k39a_ram = k39a_cs && !k39a_reg;
wire k39b_ram = k39b_cs && !k39b_reg;

`ifdef SIMULATION
integer ffetch;
integer fetch_n = 0;
initial ffetch = $fopen("z80_fetch_trace.txt", "w");
always @(posedge clk) begin
    if (rom_ok && fetch_n < 64) begin
        $fwrite(ffetch, "%02d rom_addr=%05x data=%02x\n", fetch_n, rom_addr, rom_data);
        fetch_n = fetch_n + 1;
    end
end

integer fk39a, fk39b;
integer k39a_n = 0, k39b_n = 0;
initial fk39a = $fopen("k39a_reg_trace.txt", "w");
initial fk39b = $fopen("k39b_reg_trace.txt", "w");
always @(posedge clk) begin
    if (k39a_reg && ~wr_n && k39a_n < 64) begin
        $fwrite(fk39a, "%02d addr=%03x data=%02x\n", k39a_n, A[9:0], cpu_dout);
        k39a_n = k39a_n + 1;
    end
    if (k39b_reg && ~wr_n && k39b_n < 64) begin
        $fwrite(fk39b, "%02d addr=%03x data=%02x\n", k39b_n, A[9:0], cpu_dout);
        k39b_n = k39b_n + 1;
    end
end
`endif

assign latch_we = k21_cs && !wr_n;
assign cpu_din  = rom_cs  ? rom_data      :
                  ram_cs  ? ram_dout      :
                  k39a_reg? k39a_dout     :
                  k39b_reg? k39b_dout     :
                  k39a_ram? k39a_ram_dout :
                  k39b_ram? k39b_ram_dout :
                  k21_cs  ? latch_dout    : 8'hff;

always @(posedge clk, posedge rst) begin
    if (rst) sound_ctrl <= 5'd0;
    else if (ctrl_we) sound_ctrl <= cpu_dout[4:0];
end

/* verilator tracing_off */
jtframe_sysz80 #(.RAM_AW(`SND_RAMW), .CLR_INT(1)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_8     ),
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
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

/* verilator tracing_off */
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

    .snd_on     ( sndon     ),
    .siorq_n    ( iorq_n    ),
    .int_n      ( int_n     )
);

/* verilator tracing_off */
jtframe_ram #(.AW(9)) u_ram_k39a(
    .clk        ( clk           ),
    .cen        ( 1'b1          ),
    .data       ( cpu_dout      ),
    .addr       ( A[8:0]        ),
    .we         ( k39a_ram & !wr_n ),
    .q          ( k39a_ram_dout )
);
jtframe_ram #(.AW(9)) u_ram_k39b(
    .clk        ( clk           ),
    .cen        ( 1'b1          ),
    .data       ( cpu_dout      ),
    .addr       ( A[8:0]        ),
    .we         ( k39b_ram & !wr_n ),
    .q          ( k39b_ram_dout )
);

wire nmi_toggle1;
wire [7:0] k39a_st, k39b_st;
wire [23:0] pcm1_addr24, pcm2_addr24;
wire        pcm1_cs, pcm2_cs, pcm1_ok, pcm2_ok;

/* verilator tracing_off */

k054539 #(.VOLSHIFT(1), .EFXGAIN(48)) u_k054539_1(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen_pcm       ),
    .timeout    (               ),
    .nmi_toggle ( nmi_toggle1   ),
    .addr       ( A[9:0]        ),
    .we         ( ~wr_n         ),
    .rd         ( ~rd_n         ),
    .cs         ( k39a_reg      ),
    .din        ( cpu_dout      ),
    .dout       ( k39a_dout     ),
    .rom_cs     ( pcm1_cs       ),
    .rom_addr   ( pcm1_addr24   ),
    .rom_data   ( pcm_data      ),
    .rom_ok     ( pcm1_ok       ),
    .left       ( pcm1_l        ),
    .right      ( pcm1_r        ),
    .debug_bus  ( debug_bus     ),
    .st_dout    ( k39a_st       )
);

/* verilator tracing_off */
k054539 #(.VOLSHIFT(1)) u_k054539_2(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen_pcm       ),
    .timeout    (               ),
    .nmi_toggle (               ),
    .addr       ( A[9:0]        ),
    .we         ( ~wr_n         ),
    .rd         ( ~rd_n         ),
    .cs         ( k39b_reg      ),
    .din        ( cpu_dout      ),
    .dout       ( k39b_dout     ),
    .rom_cs     ( pcm2_cs       ),
    .rom_addr   ( pcm2_addr24   ),
    .rom_data   ( pcm_data      ),
    .rom_ok     ( pcm2_ok       ),
    .left       ( pcm2_l        ),
    .right      ( pcm2_r        ),
    .debug_bus  ( debug_bus     ),
    .st_dout    ( k39b_st       )
);

/* verilator tracing_off */
mystwarr_pcm_arb u_pcm_arb(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen_pcm       ),
    .cs1        ( pcm1_cs       ),
    .addr1      ( pcm1_addr24   ),
    .ok1        ( pcm1_ok       ),
    .cs2        ( pcm2_cs       ),
    .addr2      ( pcm2_addr24   ),
    .ok2        ( pcm2_ok       ),
    .pcm_cs     ( pcm_cs        ),
    .pcm_addr   ( pcm_addr      ),
    .pcm_ok     ( pcm_ok        )
);

reg  nmi_ff, nmi_tgl_l;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        nmi_ff <= 1'b0; nmi_tgl_l <= 1'b0;
    end else begin
        nmi_tgl_l <= nmi_toggle1;
        if( ctrl_we && !cpu_dout[4] )                     nmi_ff <= 1'b0;
        else if( nmi_toggle1 && !nmi_tgl_l && sound_ctrl[4] ) nmi_ff <= 1'b1;
    end
end
wire nmi_gate = nmi_ff;
assign nmi_n  = ~nmi_gate;

reg [7:0] z80_pch;
always @(posedge clk, posedge rst) begin
    if( rst ) z80_pch <= 0;
    else if( !m1_n && mem_acc ) z80_pch <= A[15:8];
end

reg [15:0] nmi_cnt, latch_cnt;
reg        nmi_nl;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        nmi_cnt <= 0; latch_cnt <= 0; nmi_nl <= 1'b1;
    end else begin
        nmi_nl <= nmi_n;
        if( nmi_nl && !nmi_n ) nmi_cnt <= nmi_cnt + 16'd1;
        if( pair_we           ) latch_cnt <= latch_cnt + 16'd1;
    end
end

reg [15:0] nmilost_cnt;
reg        nmi_gate_l, nmi_pend;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        nmilost_cnt <= 0; nmi_gate_l <= 1'b0; nmi_pend <= 1'b0;
    end else if( cen_8 ) begin
        nmi_gate_l <= nmi_gate;
        if( nmi_pend && !cpu_cen && !(&nmilost_cnt) ) nmilost_cnt <= nmilost_cnt + 16'd1;
        nmi_pend   <= nmi_gate & ~nmi_gate_l;
    end
end

reg [15:0] cen8_win, stall_win, stall_pm;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        cen8_win <= 0; stall_win <= 0; stall_pm <= 0;
    end else if( cen_8 ) begin
        if( &cen8_win ) begin
            stall_pm  <= stall_win + (cpu_cen ? 16'd0 : 16'd1);
            stall_win <= 0;
            cen8_win  <= 0;
        end else begin
            cen8_win <= cen8_win + 16'd1;
            if( !cpu_cen ) stall_win <= stall_win + 16'd1;
        end
    end
end

reg  [15:0] keyon1_cnt, keyoff1_cnt, keyon2_cnt, keyoff2_cnt;
reg         k39a_wr_l, k39b_wr_l;
wire        k39a_wr = k39a_reg & ~wr_n;
wire        k39b_wr = k39b_reg & ~wr_n;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        keyon1_cnt <= 0; keyoff1_cnt <= 0; keyon2_cnt <= 0; keyoff2_cnt <= 0;
        k39a_wr_l  <= 0; k39b_wr_l   <= 0;
    end else begin
        k39a_wr_l <= k39a_wr;
        k39b_wr_l <= k39b_wr;
        if( k39a_wr && !k39a_wr_l ) begin
            if( A[9:0]==10'h214 ) keyon1_cnt  <= keyon1_cnt  + 16'd1;
            if( A[9:0]==10'h215 ) keyoff1_cnt <= keyoff1_cnt + 16'd1;
        end
        if( k39b_wr && !k39b_wr_l ) begin
            if( A[9:0]==10'h214 ) keyon2_cnt  <= keyon2_cnt  + 16'd1;
            if( A[9:0]==10'h215 ) keyoff2_cnt <= keyoff2_cnt + 16'd1;
        end
    end
end

reg [15:0] st_lat;
reg [ 7:0] dbus_l;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st_lat <= 16'd0; dbus_l <= 8'd0;
    end else begin
        dbus_l <= debug_bus;
        if( debug_bus != dbus_l ) case( debug_bus )
            8'hB0: st_lat <= nmi_cnt;
            8'hB2: st_lat <= latch_cnt;
            8'hB4: st_lat <= keyon1_cnt;
            8'hB6: st_lat <= keyoff1_cnt;
            8'hB8: st_lat <= keyon2_cnt;
            8'hBA: st_lat <= keyoff2_cnt;
            8'hBC: st_lat <= stall_pm;
            default: ;
        endcase
    end
end

wire [7:0] st_bx = debug_bus[3:0]==4'h0 ? st_lat     [15:8] :
                  debug_bus[3:0]==4'h1 ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'h2 ? st_lat     [15:8] :
                  debug_bus[3:0]==4'h3 ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'h4 ? st_lat     [15:8] :
                  debug_bus[3:0]==4'h5 ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'h6 ? st_lat     [15:8] :
                  debug_bus[3:0]==4'h7 ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'h8 ? st_lat     [15:8] :
                  debug_bus[3:0]==4'h9 ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'hA ? st_lat     [15:8] :
                  debug_bus[3:0]==4'hB ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'hC ? st_lat     [15:8] :
                  debug_bus[3:0]==4'hD ? st_lat     [ 7:0] :
                  debug_bus[3:0]==4'hE ? nmilost_cnt[15:8] : 8'd0;

assign st_dout = (debug_bus[5] &&  debug_bus[4]) ? st_bx :
                  debug_bus[5]                   ? { sound_ctrl[4:0], rom_hi[16:14] } :
                  debug_bus[4]                   ? (debug_bus[3] ? k39b_st : k39a_st) :
                                                   z80_pch;

endmodule
