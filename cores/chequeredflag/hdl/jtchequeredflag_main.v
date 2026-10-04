/*  This file is part of the Chequered Flag core for MiSTer.
    GPLv3. Estructura adaptada de jtajax_main.v (jotego, GPLv3). */

module jtchequeredflag_main(
    input               rst,
    input               clk,
    input               cen_ref,
    output              cpu_cen,

    output      [ 7:0]  cpu_dout,
    output              cpu_we,
    output      [15:0]  cpu_addr,

    output reg  [18:0]  rom_addr,
    input       [ 7:0]  rom_data,
    output reg          rom_cs,
    input               rom_ok,

    output      [12:0]  ram_addr,
    output              ram_we,
    input       [ 7:0]  ram_dout,

    input               irq_n,
    input               nmi_n,

    output reg          obj_cs,
    output reg          vr1_cs,
    output reg          vr2_cs,
    output reg          pal_cs,
    output reg          psac1_io,
    output reg          psac2_io,
    input       [ 7:0]  obj_dout, psac1_dout, psac2_dout, pal_dout,
    input               vid_ok,
    output reg          readroms,
    output reg  [ 7:0]  vreg,

    output reg  [ 7:0]  snd_latch, snd_latch2,
    output reg          snd_irq,

    input       [ 3:0]  cab_1p, coin,
    input               service, dip_test,
    input               brake,
    input               shift_hi,
    input       [ 7:0]  wheel,
    input       [ 7:0]  pedal,
    output reg          start_lamp,
    input       [19:0]  dipsw,
    input               dip_pause
);

wire [ 7:0] Aupper;
wire [15:0] A;
reg  [ 7:0] cpu_din, cab_dout;
reg  [ 4:0] bank;
reg         bank1000;
reg         ram_cs, rom_banked, rom_fixed, io_cs, k733_cs, adc_cs, latch_cs, latch2_cs,
            bank_cs, vreg_cs, adsel_cs;
wire [ 7:0] k733_dout;
wire        k733_busy;
wire        dtack;

assign cpu_addr = A;
assign ram_we   = ram_cs & cpu_we;

assign ram_addr = A[12:0];

assign dtack    = ( ~(rom_cs | ((vr1_cs|vr2_cs) & readroms)) | (rom_cs ? rom_ok : vid_ok) )
                & ~( k733_cs & ~cpu_we & k733_busy & (A[2:0] < 3'd6) );

always @(*) begin
    ram_cs = 0; rom_banked = 0; rom_fixed = 0; obj_cs = 0; vr1_cs = 0; vr2_cs = 0; pal_cs = 0;
    psac1_io = 0; psac2_io = 0; io_cs = 0; k733_cs = 0; adc_cs = 0; latch_cs = 0; latch2_cs = 0;
    bank_cs = 0; vreg_cs = 0; adsel_cs = 0;
    casez( A[15:12] )
        4'b0000: ram_cs = 1;
        4'b0001: if( !bank1000 ) ram_cs = 1;
                 else if( !A[11] ) vr1_cs = 1; else pal_cs = 1;
        4'b0010: if( !A[11] ) obj_cs = 1; else vr2_cs = 1;
        4'b0011: case( A[11:8] )
            4'h0: case( A[1:0] )
                    0: latch_cs  = 1;
                    1: latch2_cs = 1;
                    2: bank_cs   = 1;
                    3: vreg_cs   = 1;
                  endcase
            4'h1, 4'h2: io_cs = 1;
            4'h4: k733_cs  = A[7:5]==0;
            4'h5: psac1_io = A[7:4]==0;
            4'h6: psac2_io = A[7:4]==0;
            4'h7: case( A[1:0] )
                    0: adsel_cs = 1;
                    1: io_cs    = 1;
                    2: adc_cs   = 1;
                    default:;
                  endcase
            default:;
        endcase
        4'b01??: rom_banked = 1;
        4'b1???: rom_fixed  = 1;
        default:;
    endcase
    rom_cs = rom_banked | rom_fixed;
    rom_addr = rom_banked ? { bank, A[13:0] } : { 4'b1001, A[14:0] };
end

localparam [12:0] ADC_T = 13'd5860;
reg  [12:0] adc_cnt;
reg  [ 7:0] adc_res;
reg         adc_intr, adc_busy, adc_sel;

always @(*) begin
    case( A[11:8] )
        4'h1:    cab_dout = dipsw[7:0];
        4'h2:    case( A[1:0] )
                    0: cab_dout = { dip_test, dipsw[17:16], 1'b1, cab_1p[0], service, coin[1:0] };
                    1: cab_dout = { dipsw[19], 7'h7f };
                    3: cab_dout = dipsw[15:8];
                    default: cab_dout = 8'hff;
                 endcase
        default: cab_dout = { ~adc_intr, 3'b000, 2'b11, ~brake, ~shift_hi };
    endcase
end

always @(*) begin
    cpu_din = rom_cs   ? rom_data   :
              ram_cs   ? ram_dout   :
              pal_cs   ? pal_dout   :
              vr1_cs ? psac1_dout :
              vr2_cs ? psac2_dout :
              obj_cs   ? obj_dout   :
              k733_cs  ? k733_dout  :
              adc_cs   ? adc_res    :
              io_cs    ? cab_dout   : 8'hff;
end

always @(posedge clk) begin
    if( rst ) begin
        bank       <= 0;
        bank1000   <= 0;
        vreg       <= 0;
        readroms   <= 0;
        snd_latch  <= 0;
        snd_latch2 <= 0;
        snd_irq    <= 0;
        start_lamp <= 0;
        adc_sel    <= 0;
        adc_intr   <= 0;
        adc_busy   <= 0;
        adc_cnt    <= 0;
        adc_res    <= 0;
    end else begin
        snd_irq <= 0;
        if( cpu_we && cpu_cen ) begin
            if( latch_cs  ) snd_latch  <= cpu_dout;
            if( latch2_cs ) begin snd_latch2 <= cpu_dout; snd_irq <= 1; end
            if( bank_cs   ) begin

                if( cpu_dout[4:0] < 5'h14 ) bank <= cpu_dout[4:0];
                bank1000 <= cpu_dout[5];
            end
            if( vreg_cs   ) begin vreg <= cpu_dout; readroms <= cpu_dout[4]; end
            if( adsel_cs  ) begin adc_sel <= cpu_dout[0]; start_lamp <= cpu_dout[1]; end
        end

        if( adc_cs && cpu_cen ) begin
            adc_intr <= 0;
            if( cpu_we && !adc_busy ) begin adc_busy <= 1; adc_cnt <= ADC_T; end
        end
        if( adc_busy ) begin
            if( adc_cnt==0 ) begin
                adc_busy <= 0;
                adc_res  <= adc_sel ? wheel : pedal;
                adc_intr <= 1;
            end else adc_cnt <= adc_cnt - 1'd1;
        end
    end
end

jtchequeredflag_k051733 u_k051733(
    .clk    ( clk       ),
    .rst    ( rst       ),
    .cs     ( k733_cs   ),
    .we     ( cpu_we    ),
    .addr   ( A[4:0]    ),
    .din    ( cpu_dout  ),
    .dout   ( k733_dout ),
    .busy   ( k733_busy )
);

jtkcpu u_cpu(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cen2   ( cen_ref   ),
    .cen_out( cpu_cen   ),

    .halt   ( 1'b0      ),
    .dtack  ( dtack     ),
    .nmi_n  ( nmi_n     ),
    .irq_n  ( irq_n | ~dip_pause ),
    .firq_n ( 1'b1      ),
    .pcbad  (           ),
    .buserror(          ),

    .din    ( cpu_din   ),
    .dout   ( cpu_dout  ),
    .addr   ({Aupper, A}),
    .we     ( cpu_we    )
);

`ifdef SIMULATION

integer io_f, io_n=0, wd_n=0;
initial io_f = $fopen("cpu_io.log","w");
always @(posedge clk) if( cpu_cen && cpu_we && A[15:11]==5'b00110 ) begin
    if( A[15:8]==8'h33 ) wd_n = wd_n + 1;
    if( io_n < 400 ) begin
        $fdisplay( io_f, "%0t W %04X %02X wd=%0d", $time, A, cpu_dout, wd_n );
        $fflush( io_f );
    end
    io_n = io_n + 1;
end
`endif

endmodule
