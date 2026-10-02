module jthotchase_main(
    input                rst,
    input                clk,
    input                LVBL,
    input         [ 8:0] vdump,

    output        [17:1] rom_addr,
    output               rom_cs,
    input         [15:0] rom_data,
    input                rom_ok,

    output        [13:1] bus_addr,
    output        [15:0] bus_dout,
    output        [ 1:0] pal_we, spr_we, sh_we,
    output               psac1_we, psac2_we,
    output               psac1_rwe, psac2_rwe,
    input         [15:0] pal_dout, spr_dout, sh_dout,
    input         [ 7:0] psac1_dout, psac2_dout,

    output reg           sub_rstn,
    output reg           sub_int,
    output reg    [ 7:0] snd_latch,
    output reg           snd_on,
    output reg           snd_rstn,
    input                snd_ack,
    output reg           video_on,
    output reg           start_lamp,

    input         [ 1:0] coin,
    input                service,
    input                start1,
    input                shift,
    input                brake,
    input                dip_test,
    input         [ 7:0] accel,
    input         [ 7:0] steer,
    input         [ 6:0] opt_cnt,
    input         [15:0] dipsw,
    input                dip_pause,
    output        [ 7:0] st_dout
);

wire [23:1] A;
wire [15:0] cpu_dout;
wire        cpu_cen, cpu_cenb, UDSn, LDSn, RnW, ASn, BGn, DTACKn;
wire [ 2:0] FC;
reg  [ 2:0] IPLn;
reg  [15:0] bus_din;
wire        cpu_BRn, cpu_BGACKn;

wire        dma_on, dma_as, dma_rnw, blit_trig;
wire [23:1] dma_addr;
wire [15:0] dma_dout;
reg         bus_ok;

wire [23:1] BA   = dma_on ? dma_addr : A;
wire        bas  = dma_on ? dma_as   : ~ASn;
wire        brnw = dma_on ? dma_rnw  : RnW;
wire [ 1:0] bdsn = dma_on ? 2'b00    : {UDSn, LDSn};
assign bus_dout  = dma_on ? dma_dout : cpu_dout;
assign bus_addr  = BA[13:1];
assign rom_addr  = BA[17:1];

reg rom_cs_r, wram0_cs, wram1_cs, blit_cs, ps1_cs, ps1r_cs, ps2_cs, ps2r_cs, pal_cs, sh_cs, spr_cs, io_cs;
always @* begin
    { rom_cs_r, wram0_cs, wram1_cs, blit_cs, ps1_cs, ps1r_cs, ps2_cs, ps2r_cs, pal_cs, sh_cs, spr_cs, io_cs } = 0;
    if( bas ) begin
        rom_cs_r = BA[23:18] == 6'h00;
        wram0_cs = BA[23:13] == 11'h020;
        wram1_cs = BA[23:14] == 10'h018;
        blit_cs  = BA[23:5]  == 19'h04000;
        ps1_cs   = BA[23:12] == 12'h100;
        ps1r_cs  = BA[23:5]  == 19'h08080;
        ps2_cs   = BA[23:12] == 12'h102;
        ps2r_cs  = BA[23:5]  == 19'h08180;
        pal_cs   = BA[23:13] == 11'h088;
        sh_cs    = BA[23:14] == 10'h048;
        spr_cs   = BA[23:12] == 12'h130;
        io_cs    = BA[23:12] == 12'h140;
    end
end
assign rom_cs = rom_cs_r;

wire [1:0] bwe = ~bdsn & {2{~brnw & bas}};
wire [1:0] wram0_we = bwe & {2{wram0_cs}};
wire [1:0] wram1_we = bwe & {2{wram1_cs}};
assign pal_we    = bwe & {2{pal_cs}};
assign spr_we    = bwe & {2{spr_cs}};
assign sh_we     = bwe & {2{sh_cs }};
assign psac1_we  = bwe[0] & ps1_cs;
assign psac2_we  = bwe[0] & ps2_cs;
assign psac1_rwe = bwe[0] & ps1r_cs;
assign psac2_rwe = bwe[0] & ps2r_cs;

wire [15:0] wram0_dout, wram1_dout;
jtframe_ram16 #(.AW(12)) u_wram0(
    .clk    ( clk           ),
    .data   ( bus_dout      ),
    .addr   ( BA[12:1]      ),
    .we     ( wram0_we      ),
    .q      ( wram0_dout    )
);
jtframe_ram16 #(.AW(13)) u_wram1(
    .clk    ( clk           ),
    .data   ( bus_dout      ),
    .addr   ( BA[13:1]      ),
    .we     ( wram1_we      ),
    .q      ( wram1_dout    )
);

reg  [ 7:0] sel_ip, adc_dout;
reg  [12:0] adc_cnt;
reg         adc_intr_n, io_wrl, io_rdl;
wire        io_wr = io_cs && !brnw && bas && !bdsn[0];
wire        io_rd = io_cs &&  brnw && bas;
wire [ 7:0] adc_in = sel_ip[6:5]==2'd0 ? accel : sel_ip[6:5]==2'd2 ? steer : 8'd0;

always @(posedge clk) begin
    io_wrl <= io_wr;
    io_rdl <= io_rd;
    if( rst ) begin
        adc_intr_n <= 1; adc_cnt <= 0; adc_dout <= 0;
    end else begin
        if( adc_cnt != 0 ) begin
            adc_cnt <= adc_cnt - 1'd1;
            if( adc_cnt==1 ) begin adc_intr_n <= 0; adc_dout <= adc_in; end
        end
        if( io_wr && !io_wrl && BA[5:1]==5'h10 ) begin
            adc_cnt    <= 13'd5600;
            adc_intr_n <= 1;
        end
        if( io_rd && !io_rdl && BA[5:1]==5'h10 ) adc_intr_n <= 1;
    end
end

always @(posedge clk) begin
    if( rst ) begin
        snd_latch <= 0; sel_ip <= 0; start_lamp <= 0;
        { video_on, snd_rstn, snd_on, sub_rstn, sub_int } <= 0;
    end else if( io_wr ) begin
        case( BA[5:1] )
            5'h0: snd_latch <= bus_dout[7:0];
            5'h1: begin sel_ip <= bus_dout[7:0]; start_lamp <= bus_dout[2]; end
            5'h2: { video_on, snd_rstn, snd_on, sub_rstn, sub_int } <=
                  { bus_dout[6], bus_dout[3], bus_dout[2], bus_dout[1], bus_dout[0] };
            default:;
        endcase
    end
end

reg [7:0] io_dout;
always @* begin
    case( BA[5:1] )

        5'h08: io_dout = ~{ 1'b0, brake, shift, start1, service, dip_test, coin };
        5'h09: io_dout = { 3'b111, snd_ack, adc_intr_n, 3'b111 };

        5'h0a: io_dout = dipsw[15:8];
        5'h0b: io_dout = dipsw[ 7:0];
        5'h10: io_dout = adc_dout;
        5'h11: io_dout = { 1'b0, opt_cnt };
        default: io_dout = 8'h00;
    endcase
end

always @(posedge clk) begin
    bus_din <= rom_cs_r ? rom_data   :
               wram0_cs ? wram0_dout :
               wram1_cs ? wram1_dout :
               ps1_cs   ? { 8'hff, psac1_dout } :
               ps2_cs   ? { 8'hff, psac2_dout } :
               pal_cs   ? pal_dout   :
               sh_cs    ? sh_dout    :
               spr_cs   ? spr_dout   :
               io_cs    ? { 8'h00, io_dout } : 16'h0;
    bus_ok <= !rom_cs_r || rom_ok;
end

jthotchase_blitter u_blitter(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cs         ( blit_cs && !dma_on ),
    .we         ( bwe           ),
    .addr       ( BA[4:1]       ),
    .din        ( bus_dout      ),
    .cpu_BGACKn ( cpu_BGACKn    ),
    .blit_req   ( blit_trig     ),
    .dma_on     ( dma_on        ),
    .dma_addr   ( dma_addr      ),
    .dma_as     ( dma_as        ),
    .dma_rnw    ( dma_rnw       ),
    .dma_dout   ( dma_dout      ),
    .bus_din    ( bus_din       ),
    .bus_ok     ( bus_ok        )
);

jtframe_68kdma u_dma(
    .clk        ( clk           ),
    .rst        ( rst           ),
    .cen        ( cpu_cen       ),
    .cpu_BRn    ( cpu_BRn       ),
    .cpu_BGACKn ( cpu_BGACKn    ),
    .cpu_BGn    ( BGn           ),
    .cpu_ASn    ( ASn           ),
    .cpu_DTACKn ( DTACKn        ),
    .dev_br     ( blit_trig     )
);

reg  irq4;
reg  [8:0] vdl;
wire iack = !ASn && FC==3'd7;
always @(posedge clk) begin
    vdl <= vdump;
    if( rst ) begin
        irq4 <= 0;
    end else begin
        if( vdump != vdl && vdump==9'd224 ) irq4 <= 1;
        if( iack && A[3:1]==3'd4 ) irq4 <= 0;
    end
    IPLn <= irq4 ? ~3'd4 : 3'b111;
end

jthotchase_68kdtack #(.W(8),.N0(5)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( rom_cs_r & ~dma_on ),
    .bus_busy   ( rom_cs_r & ~rom_ok & ~dma_on ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    .num        ( 7'd47     ),
    .den        ( 8'd231    ),
    .DTACKn     ( DTACKn    )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),
    .eab        ( A           ),
    .iEdb       ( bus_din     ),
    .oEdb       ( cpu_dout    ),
    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( ~iack       ),
    .FC         ( FC          ),
    .BERRn      ( 1'b1        ),
    .HALTn      ( dip_pause   ),
    .BRn        ( cpu_BRn     ),
    .BGACKn     ( cpu_BGACKn  ),
    .BGn        ( BGn         ),
    .DTACKn     ( DTACKn      ),
    .IPLn       ( IPLn        )
);

`ifdef SIMULATION

reg [63:0] tclk=0; always @(posedge clk) tclk <= tclk+1;
reg [7:0] last5=8'hff; reg [15:0] laststep=16'hffff; integer frames=0; reg LVBLx=0; reg ackl=0;
always @(posedge clk) begin
    LVBLx <= LVBL;
    ackl  <= snd_ack;
    if( LVBLx && !LVBL ) frames <= frames+1;
    if( !ASn && !RnW && !LDSn && {A,1'b0}==24'h140004 && cpu_dout[7:0]!=last5 ) begin
        last5 <= cpu_dout[7:0]; $display("MAIN 140005 <- %02X (frame %0d)", cpu_dout[7:0], frames); end
    if( !ASn && !RnW && {A,1'b0}==24'h120000 && cpu_dout!=laststep && !dma_on ) begin
        laststep <= cpu_dout; $display("POST paso $120000 <- %04X (frame %0d) clk %0d", cpu_dout, frames, tclk); end
    if( snd_ack != ackl ) $display("IN1.b4 (ACK 6809) = %0d (frame %0d)", snd_ack, frames);
end

reg [23:0] lastpc=0; integer ascnt=0; reg hungrep=0;
always @(posedge clk) begin
    if( !ASn && FC[1:0]==2'b10 ) lastpc <= {A,1'b0};
    if( LVBLx && !LVBL && frames>=140 && frames<1200 )
        $display("MAIN PC %06X frame %0d dma=%0d BGACKn=%0d IPLn=%0d", lastpc, frames, dma_on, cpu_BGACKn, IPLn);
    if( !ASn && DTACKn ) ascnt = ascnt+1; else ascnt = 0;
    if( ascnt==1000 && !hungrep ) begin hungrep <= 1;
        $display("MAIN BUS COLGADO: A=%06X RnW=%0d FC=%0d frame %0d", {A,1'b0}, RnW, FC, frames); end
end

integer pf_cen=0, pf_wcen=0, pf_wrom=0, pf_del=0, pf_rec=0, pf_bus=0, pf_rom=0, pf_dma=0, pf_clk=0; reg pf_asl=1;
always @(posedge clk) begin
    pf_asl <= ASn;
    pf_clk = pf_clk+1;
    if( cpu_cen ) pf_cen = pf_cen+1;
    if( cpu_cen && !ASn && DTACKn ) begin pf_wcen = pf_wcen+1; if( rom_cs_r ) pf_wrom = pf_wrom+1; end
    if( u_dtack.recover ) pf_rec = pf_rec+1;
    if( pf_asl && !ASn ) begin pf_bus = pf_bus+1; if( rom_cs_r ) pf_rom = pf_rom+1; end
    if( !cpu_BGACKn ) pf_dma = pf_dma+1;
    if( LVBLx && !LVBL ) begin
        $display("MAINPERF frame %0d clk %0d cen %0d wcen %0d wrom %0d del %0d rec %0d bus %0d rom %0d dmaclk %0d",
            frames, pf_clk, pf_cen, pf_wcen, pf_wrom, u_dtack.missing, pf_rec, pf_bus, pf_rom, pf_dma);
        pf_cen=0; pf_wcen=0; pf_wrom=0; pf_del=0; pf_rec=0; pf_bus=0; pf_rom=0; pf_dma=0; pf_clk=0;
    end
end

integer bc_hc=0, bc_i; reg bc_rom=0; integer hrom[0:63], hram[0:63];
initial for( bc_i=0; bc_i<64; bc_i=bc_i+1 ) begin hrom[bc_i]=0; hram[bc_i]=0; end
always @(posedge clk) begin
    if( !ASn ) begin
        if( cpu_cen|cpu_cenb ) bc_hc = bc_hc+1;
        if( rom_cs_r ) bc_rom <= 1;
    end
    if( !pf_asl && ASn ) begin
        if( frames>=20 && frames<22 ) begin
            if( bc_rom ) hrom[bc_hc>63?63:bc_hc] = hrom[bc_hc>63?63:bc_hc]+1;
            else         hram[bc_hc>63?63:bc_hc] = hram[bc_hc>63?63:bc_hc]+1;
        end
        bc_hc = 0; bc_rom <= 0;
    end
    if( LVBLx && !LVBL && frames==22 ) begin
        for( bc_i=0; bc_i<64; bc_i=bc_i+1 )
            if( hrom[bc_i]!=0 || hram[bc_i]!=0 ) $display("BCHIST hc %0d rom %0d noROM %0d", bc_i, hrom[bc_i], hram[bc_i]);
    end
end
`endif

assign st_dout = { dma_on, 1'b0, irq4, video_on, snd_rstn, snd_on, sub_rstn, sub_int };

endmodule
