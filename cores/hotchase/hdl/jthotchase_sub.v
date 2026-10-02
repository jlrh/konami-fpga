module jthotchase_sub(
    input                rst,
    input                clk,
    input                sub_rstn,
    input                sub_int,

    output        [16:1] rom_addr,
    output reg           rom_cs,
    input         [15:0] rom_data,
    input                rom_ok,

    output        [13:1] bus_addr,
    output        [15:0] bus_dout,
    output        [ 1:0] road_we, sh_we,
    input         [15:0] road_dout, sh_dout,
    input                dip_pause
);

wire [23:1] A;
wire        cpu_cen, cpu_cenb, UDSn, LDSn, RnW, ASn, DTACKn;
wire [ 2:0] FC;
reg  [15:0] cpu_din;
reg         road_cs, sh_cs, ps3_cs, ps3r_cs, irq, intl;
wire        crst = rst | ~sub_rstn;
wire        iack = !ASn && FC==3'd7;

assign rom_addr = A[16:1];
assign bus_addr = A[13:1];

always @* begin
    rom_cs  = !ASn && A[23:17]==7'h00;
    road_cs = !ASn && A[23:12]==12'h020;
    sh_cs   = !ASn && A[23:14]==10'h010;
    ps3_cs  = !ASn && A[23:12]==12'h060;
    ps3r_cs = !ASn && A[23:5] ==19'h03080;
end

wire [1:0] we = ~{UDSn,LDSn} & {2{~RnW & ~ASn}};
assign road_we = we & {2{road_cs}};
assign sh_we   = we & {2{sh_cs}};

wire [15:0] ps3_dout, ps3r_dout;
jtframe_ram16 #(.AW(11)) u_ps3(
    .clk    ( clk       ),
    .data   ( bus_dout  ),
    .addr   ( A[11:1]   ),
    .we     ( we & {2{ps3_cs}} ),
    .q      ( ps3_dout  )
);
jtframe_ram16 #(.AW(4)) u_ps3r(
    .clk    ( clk       ),
    .data   ( bus_dout  ),
    .addr   ( A[4:1]    ),
    .we     ( we & {2{ps3r_cs}} ),
    .q      ( ps3r_dout )
);

always @(posedge clk) begin
    cpu_din <= rom_cs  ? rom_data  :
               road_cs ? road_dout :
               sh_cs   ? sh_dout   :
               ps3_cs  ? ps3_dout  :
               ps3r_cs ? ps3r_dout : 16'h0;
end

always @(posedge clk) begin
    intl <= sub_int;
    if( crst ) irq <= 0;
    else begin
        if( intl && !sub_int ) irq <= 1;
        if( iack ) irq <= 0;
    end
end

jtframe_68kdtack_cen #(.W(8),.RECOVERY(1)) u_dtack(
    .rst        ( crst      ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( rom_cs    ),
    .bus_busy   ( rom_cs & ~rom_ok ),
    .bus_legit  ( 1'b0      ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    .num        ( 7'd47     ),
    .den        ( 8'd231    ),
    .DTACKn     ( DTACKn    ),
    .wait2      ( 1'b0      ),
    .wait3      ( 1'b0      ),
    .fave       (           ),
    .fworst     (           )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( crst        ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),
    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( bus_dout    ),
    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( ~iack       ),
    .FC         ( FC          ),
    .BERRn      ( 1'b1        ),
    .HALTn      ( dip_pause   ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),
    .DTACKn     ( DTACKn      ),
    .IPLn       ( irq ? 3'b011 : 3'b111 )
);

`ifdef SIMULATION

reg [23:0] lastpc=0; reg vbl=0, vbll=0; integer sfr=0;
always @(posedge clk) if( !ASn && FC[1:0]==2'b10 ) lastpc <= {A,1'b0};
reg [15:0] last4=16'hffff;
always @(posedge clk) if( !ASn && !RnW && {A,1'b0}==24'h040004 && bus_dout!=last4 ) begin
    last4 <= bus_dout; $display("SUB  040004 <- %04X", bus_dout); end

integer pf_cen=0, pf_wcen=0, pf_del=0, pf_rec=0, pf_bus=0, pf_rom=0, pf_clk=0, pf_n=0; reg pf_asl=1;
always @(posedge clk) begin
    pf_asl <= ASn;
    pf_clk = pf_clk+1;
    if( cpu_cen ) pf_cen = pf_cen+1;
    if( cpu_cen && !ASn && DTACKn ) pf_wcen = pf_wcen+1;
    if( u_dtack.delayed && (cpu_cen|cpu_cenb) ) pf_del = pf_del+1;
    if( u_dtack.recover ) pf_rec = pf_rec+1;
    if( pf_asl && !ASn ) begin pf_bus = pf_bus+1; if( rom_cs ) pf_rom = pf_rom+1; end
    if( pf_clk==819200 ) begin
        pf_n = pf_n+1;
        $display("SUBPERF win %0d rst %0d cen %0d wcen %0d del %0d rec %0d bus %0d rom %0d",
            pf_n, crst, pf_cen, pf_wcen, pf_del, pf_rec, pf_bus, pf_rom);
        pf_cen=0; pf_wcen=0; pf_del=0; pf_rec=0; pf_bus=0; pf_rom=0; pf_clk=0;
    end
end
`endif

endmodule
