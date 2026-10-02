module jthotchase_sound(
    input           clk,
    input           rst,
    input           cen_snd,
    input           cen_pcm,
    input           snd_rstn,
    input           snd_on,
    input   [ 7:0]  snd_latch,
    output reg      snd_ack,
    output          ack_wr,

    output  [14:0]  rom_addr,
    output reg      rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,

    output  [17:0]  pcm1a_addr, pcm1b_addr, pcm2a_addr, pcm2b_addr,
    output  [19:0]  pcm3a_addr, pcm3b_addr,
    output          pcm1a_cs, pcm1b_cs, pcm2a_cs, pcm2b_cs, pcm3a_cs, pcm3b_cs,
    input   [ 7:0]  pcm1a_data, pcm1b_data, pcm2a_data, pcm2b_data, pcm3a_data, pcm3b_data,
    input           pcm1a_ok, pcm1b_ok, pcm2a_ok, pcm2b_ok, pcm3a_ok, pcm3b_ok,

    output signed [11:0] pcm1_l, pcm1_r, pcm2_l, pcm2_r, pcm3_l, pcm3_r
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] cpu_dout, ram_dout;
wire        RnW, VMA, cpu_cen, irq_ack;
reg  [ 7:0] cpu_din;
reg         ram_cs, pcm1_cs, pcm2_cs, pcm3_cs, ctl_cs, latch_cs, ack_cs;
reg  [ 7:0] vol0, vol1, vol2, vol3, vol4, vol5;
reg         b1a, b1b, b2a, b2b;
reg  [ 2:0] b3a, b3b;
reg         irq_n, firq_n, onl;
reg  [12:0] firq_cnt;
`ifdef HC_VENENO_NORST
wire        srst = rst;
`else
wire        srst = rst | ~snd_rstn;
`endif
wire        wr   = !RnW && VMA;

assign rom_addr = A[14:0];
assign ack_wr   = ack_cs && wr && cpu_cen && !srst;

always @* begin
    rom_cs   = VMA && A[15];
    ram_cs   = VMA && A[15:11]==5'b0000_0;
    pcm1_cs  = VMA && A[15:12]==4'h1;
    pcm2_cs  = VMA && A[15:12]==4'h2;
    pcm3_cs  = VMA && A[15:12]==4'h3;
    ctl_cs   = VMA && A[15:12]==4'h4;
    latch_cs = VMA && A[15:12]==4'h6;
    ack_cs   = VMA && A[15:12]==4'h7;
end

always @* begin
    case( 1'b1 )
        rom_cs:   cpu_din = rom_data;
        ram_cs:   cpu_din = ram_dout;
        latch_cs: cpu_din = snd_latch;
        default:  cpu_din = 8'h00;
    endcase
end

always @(posedge clk) begin
    if( srst ) begin
        { vol0, vol1, vol2, vol3, vol4, vol5 } <= 0;
        { b1a, b1b, b2a, b2b } <= 0;
        b3a <= 0; b3b <= 0;
    end else if( ctl_cs && wr && cpu_cen ) begin
        case( A[2:0] )
            3'd6: begin b1a <= cpu_dout[1]; b2a <= cpu_dout[2]; b1b <= cpu_dout[3]; b2b <= cpu_dout[4]; end
            3'd7: begin b3a <= cpu_dout[2:0]; b3b <= cpu_dout[5:3]; end
            3'd0: vol0 <= cpu_dout;
            3'd1: vol1 <= cpu_dout;
            3'd2: vol2 <= cpu_dout;
            3'd3: vol3 <= cpu_dout;
            3'd4: vol4 <= cpu_dout;
            3'd5: vol5 <= cpu_dout;
        endcase
    end
end

always @(posedge clk) begin
    onl <= snd_on;
    if( rst ) begin
        snd_ack <= 0;
    end else begin
        if( onl && !snd_on ) snd_ack <= 0;
        if( ack_wr ) snd_ack <= 1;
    end
end

always @(posedge clk) begin
    if( srst ) begin
        irq_n <= 1; firq_n <= 1; firq_cnt <= 0;
    end else begin
        if( onl && !snd_on ) irq_n <= 0;
        if( cen_pcm ) begin

            if( firq_cnt == 13'd7216 ) begin firq_cnt <= 0; firq_n <= 0; end
            else firq_cnt <= firq_cnt + 1'd1;
        end

        if( irq_ack && A[3:1]==3'b011 ) firq_n <= 1;
        if( irq_ack && A[3:1]==3'b100 ) irq_n  <= 1;
    end
end

jtframe_sys6809 #(.RAM_AW(11)) u_cpu(
    .rstn       ( ~srst     ),
    .clk        ( clk       ),
    .cen        ( cen_snd   ),
    .cpu_cen    ( cpu_cen   ),
    .nIRQ       ( irq_n     ),
    .nFIRQ      ( firq_n    ),
    .nNMI       ( 1'b1      ),
    .irq_ack    ( irq_ack   ),
    .bus_busy   ( 1'b0      ),
    .A          ( A         ),
    .RnW        ( RnW       ),
    .VMA        ( VMA       ),
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    .ram_dout   ( ram_dout  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( cpu_din   )
);

wire signed [10:0] s1a, s1b, s2a, s2b, s3a, s3b;
wire [16:0] a1a, a1b, a2a, a2b, a3a, a3b;
assign pcm1a_addr = { b1a, a1a };  assign pcm1b_addr = { b1b, a1b };
assign pcm2a_addr = { b2a, a2a };  assign pcm2b_addr = { b2b, a2b };
assign pcm3a_addr = { b3a, a3a };  assign pcm3b_addr = { b3b, a3b };

jt007232 #(.INVA0(1),.NOGAIN(1)) u_pcm1(
    .rst        ( srst      ),
    .clk        ( clk       ),
    .cen        ( cen_pcm   ),
    .addr       ( A[3:0]    ),
    .dacs       ( pcm1_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( RnW       ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( a1a       ),
    .roma_dout  ( pcm1a_data ),
    .roma_cs    ( pcm1a_cs   ),
    .roma_ok    ( pcm1a_ok   ),
    .romb_addr  ( a1b       ),
    .romb_dout  ( pcm1b_data ),
    .romb_cs    ( pcm1b_cs   ),
    .romb_ok    ( pcm1b_ok   ),
    .snda       ( s1a       ),
    .sndb       ( s1b       ),
    .snd        (           ),
    .debug_bus  ( 8'd0      ),
    .st_dout    (           )
);

jt007232 #(.INVA0(1),.NOGAIN(1)) u_pcm2(
    .rst        ( srst      ),
    .clk        ( clk       ),
    .cen        ( cen_pcm   ),
    .addr       ( A[3:0]    ),
    .dacs       ( pcm2_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( RnW       ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( a2a       ),
    .roma_dout  ( pcm2a_data ),
    .roma_cs    ( pcm2a_cs   ),
    .roma_ok    ( pcm2a_ok   ),
    .romb_addr  ( a2b       ),
    .romb_dout  ( pcm2b_data ),
    .romb_cs    ( pcm2b_cs   ),
    .romb_ok    ( pcm2b_ok   ),
    .snda       ( s2a       ),
    .sndb       ( s2b       ),
    .snd        (           ),
    .debug_bus  ( 8'd0      ),
    .st_dout    (           )
);

jt007232 #(.INVA0(1),.NOGAIN(1)) u_pcm3(
    .rst        ( srst      ),
    .clk        ( clk       ),
    .cen        ( cen_pcm   ),
    .addr       ( A[3:0]    ),
    .dacs       ( pcm3_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( RnW       ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( a3a       ),
    .roma_dout  ( pcm3a_data ),
    .roma_cs    ( pcm3a_cs   ),
    .roma_ok    ( pcm3a_ok   ),
    .romb_addr  ( a3b       ),
    .romb_dout  ( pcm3b_data ),
    .romb_cs    ( pcm3b_cs   ),
    .romb_ok    ( pcm3b_ok   ),
    .snda       ( s3a       ),
    .sndb       ( s3b       ),
    .snd        (           ),
    .debug_bus  ( 8'd0      ),
    .st_dout    (           )
);

function signed [11:0] mix(input signed [10:0] a, input [3:0] va, input signed [10:0] b, input [3:0] vb);
    reg signed [15:0] t;
    begin
        t   = $signed(a[6:0])*$signed({1'b0,va}) + $signed(b[6:0])*$signed({1'b0,vb});
        mix = t[11:0];
    end
endfunction
assign pcm1_l = mix(s1a, vol0[3:0], s1b, vol1[3:0]);
assign pcm1_r = mix(s1a, vol0[7:4], s1b, vol1[7:4]);
assign pcm2_l = mix(s2a, vol2[3:0], s2b, vol3[3:0]);
assign pcm2_r = mix(s2a, vol2[7:4], s2b, vol3[7:4]);
assign pcm3_l = mix(s3a, vol4[3:0], s3b, vol5[3:0]);
assign pcm3_r = mix(s3a, vol4[7:4], s3b, vol5[7:4]);

`ifdef SIMULATION

integer w1=0, w2=0, w3=0, wc=0, sc=0, sn=0;
always @(posedge clk) begin
    if( wr && cpu_cen && !srst ) begin
        if( pcm1_cs ) w1 = w1+1;
        if( pcm2_cs ) w2 = w2+1;
        if( pcm3_cs ) w3 = w3+1;
        if( ctl_cs  ) wc = wc+1;
    end
    if( cen_pcm ) begin
        sc = sc+1;
        if( sc==3579545 ) begin
            sn = sn+1;
            $display("SNDWR s %0d pcm1 %0d pcm2 %0d pcm3 %0d ctl %0d vol %02X %02X %02X %02X %02X %02X bank %0d%0d%0d%0d %0d %0d",
                sn, w1, w2, w3, wc, vol0, vol1, vol2, vol3, vol4, vol5, b1a, b1b, b2a, b2b, b3a, b3b);
            sc=0; w1=0; w2=0; w3=0; wc=0;
        end
    end
end
`ifdef HC_SND_TRACE

always @(posedge clk) if( wr && cpu_cen && !srst && !A[15] && (sn>31 || (sn==31 && sc>=2863636)) && sn<35+1 )
    $display("W %04x %02x %0d %0d", A, cpu_dout, sn, sc);
`endif
reg ackl=0;
always @(posedge clk) begin
    ackl <= snd_ack;
`ifdef HC_SND_VERBOSE
    if( !ackl && snd_ack ) $display("SND  6809 escribe $7000 (ACK)");
`endif
end
`endif
`else

initial rom_cs = 0;
assign ack_wr = 0;
reg [20:0] ack_cnt;
reg        onl_ns, rstnl_ns;
always @(posedge clk) begin
    onl_ns <= snd_on; rstnl_ns <= snd_rstn;
    if( rst ) begin
        snd_ack <= 0; ack_cnt <= 21'd1_000_000;
    end else if( !snd_rstn ) begin
        ack_cnt <= 21'd1_000_000;
    end else begin
        if( onl_ns && !snd_on ) begin snd_ack <= 0; ack_cnt <= 21'd5_000; end
        else if( ack_cnt != 0 ) begin
            ack_cnt <= ack_cnt - 1'd1;
            if( ack_cnt == 1 ) snd_ack <= 1;
        end
    end
end
assign rom_addr = 0;
assign { pcm1a_cs, pcm1b_cs, pcm2a_cs, pcm2b_cs, pcm3a_cs, pcm3b_cs } = 0;
assign { pcm1a_addr, pcm1b_addr, pcm2a_addr, pcm2b_addr } = 0;
assign { pcm3a_addr, pcm3b_addr } = 0;
assign { pcm1_l, pcm1_r, pcm2_l, pcm2_r, pcm3_l, pcm3_r } = 0;
`endif
endmodule
