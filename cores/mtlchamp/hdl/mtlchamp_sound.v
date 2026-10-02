module mtlchamp_sound(
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

    output signed [15:0] pcm_l, pcm_r,

    input      [ 7:0]   debug_bus,
    output     [ 7:0]   st_dout
);

wire [ 7:0] cpu_dout, cpu_din, ram_dout, k39a_dout, latch_dout, k39a_ram_dout, k39b_ram_dout;
wire [15:0] A;
wire        m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, nmi_n, int_n, latch_we;
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
wire k39a_ram = k39a_cs && !k39a_reg;

wire k39b_ram = k39b_cs && (A[9:0] >= 10'h230);

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

integer fk39a;
integer k39a_n = 0;
initial fk39a = $fopen("k39a_reg_trace.txt", "w");
always @(posedge clk) begin
    if (k39a_reg && ~wr_n && k39a_n < 64) begin
        $fwrite(fk39a, "%02d addr=%03x data=%02x\n", k39a_n, {A[9],A[7:0]}, cpu_dout);
        k39a_n = k39a_n + 1;
    end
end
`endif

assign latch_we = k21_cs && !wr_n;
assign cpu_din  = rom_cs  ? rom_data      :
                  ram_cs  ? ram_dout      :
                  k39a_reg? k39a_dout     :
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
    .cpu_cen    (           ),
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
wire [7:0] k39a_st;
wire [23:0] pcm_addr24;

/* verilator tracing_off */
k054539 #(.VOLSHIFT(1)) u_k054539_1(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen_pcm       ),
    .timeout    (               ),
    .nmi_toggle ( nmi_toggle1   ),
    .addr       ( {A[9],A[7:0]} ),
    .we         ( ~wr_n         ),
    .rd         ( ~rd_n         ),
    .cs         ( k39a_reg      ),
    .din        ( cpu_dout      ),
    .dout       ( k39a_dout     ),
    .rom_cs     ( pcm_cs        ),
    .rom_addr   ( pcm_addr24    ),
    .rom_data   ( pcm_data      ),
    .rom_ok     ( pcm_ok        ),
    .left       ( pcm_l         ),
    .right      ( pcm_r         ),
    .debug_bus  ( debug_bus     ),
    .st_dout    ( k39a_st       )
);

assign pcm_addr = pcm_addr24[21:0];

wire nmi_gate = nmi_toggle1 & sound_ctrl[4];
/* verilator tracing_off */
jtframe_edge_pulse #(.INVERT(1)) u_nmi_pulse(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen_8         ),
    .sigin      ( nmi_gate      ),
    .pulse      ( nmi_n         )
);

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

assign st_dout = (debug_bus[5] &&  debug_bus[4]) ? (debug_bus[0] ? latch_cnt[15:8] : nmi_cnt[15:8]) :
                  debug_bus[5]                   ? { sound_ctrl[4:0], rom_hi[16:14] } :
                  debug_bus[4]                   ? k39a_st :
                                                   z80_pch;

endmodule
