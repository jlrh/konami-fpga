/*  ssriders — mezcla de prioridades K053251 + paleta xBGR_555.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module ssriders_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,

    input             lhbl,
    input             lvbl,

    input             pcu_cs,
    input             alpha_cs,
    input             pal_cs,
    input             cpu_we,
    input      [15:0] cpu_dout,
    input      [ 7:0] cpu_d8,
    input      [ 1:0] cpu_dsn,
    input      [12:1] cpu_addr,
    output     [15:0] cpu_din,

    input      [ 7:0] lyrf_pxl,
    input      [ 7:0] lyra_pxl,
    input      [ 7:0] lyrb_pxl,
    input      [ 8:0] lyro_pxl,
    input      [ 4:0] lyro_pri,

    input      [ 1:0] shadow,
    input      [ 2:0] dim,
    input             dimmod,
    input             dimpol,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    input      [15:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,
    output     [ 7:0] dump_mmr,

    input      [ 7:0] debug_bus
);

wire _unused = &{1'b0, alpha_cs, cpu_d8, dimmod, 1'b0};

reg  [ 5:0] k251_r5, k251_r9, k251_r10;
reg  [ 7:0] dimpal;
wire [ 2:0] cb_obj  = { k251_r9[3:2], 1'b0 };
wire [ 2:0] cb_lyrb = k251_r10[2:0];
wire [ 2:0] cb_lyra = k251_r10[5:3];
wire        dim_en  = k251_r5 != 6'h3e;
wire        dim_obj = dim_en & ~k251_r5[4];

wire [15:0] pal_q, pal_rd;
reg  [23:0] bgr;
reg  [ 7:0] r8, g8, b8;
wire [ 7:0] pr8, pg8, pb8;
wire [10:0] pal_addr;

wire        shad, pcu_we;

wire [ 5:0] pri1s;
wire [ 8:0] ci0, ci1, ci2;
wire [ 7:0] ci3, ci4;
wire [ 1:0] shd_out, shd_in;

function [7:0] pal5(input [4:0] v); pal5 = {v,v[4:2]}; endfunction
assign pr8 = pal5( pal_rd[ 4: 0] );
assign pg8 = pal5( pal_rd[ 9: 5] );
assign pb8 = pal5( pal_rd[14:10] );

wire [10:0] cpu_cidx = cpu_addr[11:1];
wire [ 1:0] we_pal   = {2{pal_cs & cpu_we}} & ~cpu_dsn;
assign pcu_we    = pcu_cs & ~cpu_dsn[0] & cpu_we;
assign cpu_din   = pal_q;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        k251_r5 <= 0; k251_r9 <= 0; k251_r10 <= 0;
    end else if( pcu_we ) begin
        case( cpu_addr[4:1] )
            4'd5:  k251_r5  <= cpu_dout[5:0];
            4'd9:  k251_r9  <= cpu_dout[5:0];
            4'd10: k251_r10 <= cpu_dout[5:0];
            default:;
        endcase
    end
end

always @* begin
    dimpal = 0;
    if( dim_en  ) dimpal[cb_lyra]      = 1;
    if( dim_obj ) begin
        dimpal[cb_obj]         = 1;
        dimpal[cb_obj | 3'd1]  = 1;
        dimpal[cb_lyrb]        = 1;
    end
end

wire        pal_dump_sel = ioctl_ram & (ioctl_addr[15:12]==4'h8);
wire [ 7:0] pal_dump_q;
wire        k251_dump_sel = ioctl_ram & (ioctl_addr[15:4]==12'h901) & (ioctl_addr[3:0]<4'd13);
assign ioctl_din = pal_dump_sel  ? pal_dump_q :
                    k251_dump_sel ? dump_mmr   : 8'd0;

assign {blue,green,red} = (lvbl & lhbl & ~ioctl_ram) ? bgr : 24'd0;

assign pri1s = {lyro_pri,1'b0};
assign ci0   = 9'd0;
assign ci1   = lyro_pxl;
assign ci2   = {1'b0, lyrf_pxl};
assign ci3   = lyrb_pxl;
assign ci4   = lyra_pxl;
assign shd_in= shadow;

jtcolmix_053251 u_k251(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

    .cs         ( pcu_we    ),
    .addr       (cpu_addr[4:1]),
    .din        (cpu_dout[5:0]),

    .sel        ( 1'b0      ),
    .pri0       ( 6'h3f     ),
    .pri1       ( pri1s     ),
    .pri2       ( 6'h3f     ),

    .ci0        ( ci0       ),
    .ci1        ( ci1       ),
    .ci2        ( ci2       ),
    .ci3        ( ci3       ),
    .ci4        ( ci4       ),

    .shd_in     ( shd_in    ),
    .shd_out    ( shd_out   ),

    .ioctl_addr ( ioctl_ram ? ioctl_addr[3:0] : debug_bus[3:0] ),
    .ioctl_din  ( dump_mmr  ),

    .cout       ( pal_addr  ),
    .brit       (           ),
    .col_n      (           )
);

assign shad = shd_out[0];

jtframe_dual_nvram16 #(.AW(11),.SIMFILE("pal.bin"),.ENDIAN(1)) u_pal(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_cidx ), .we0( we_pal ), .q0( pal_q  ),
    .clk1( clk ), .addr1a( pal_addr ), .q1a( pal_rd ),
    .data1( 8'd0 ), .addr1b( ioctl_addr[11:0] ), .we1b( 1'b0 ), .sel_b( pal_dump_sel ), .q1b( pal_dump_q )
);

`ifdef SIMULATION
integer pal_dbg_cyc=0;
always @(posedge clk) pal_dbg_cyc <= pal_dbg_cyc + 1;
always @(posedge clk) begin
    if( pal_dbg_cyc==32'd5_000_000 ) begin
        $writememh("pal_lo_ckpt1.hex", u_pal.u_lo.u_dual.u_ram.mem);
        $writememh("pal_hi_ckpt1.hex", u_pal.u_hi.u_dual.u_ram.mem);
        $display("DUMP-CKPT1 (pal, ~MAME frame 30): volcado en pal_dbg_cyc=%0d", pal_dbg_cyc);
    end
    if( pal_dbg_cyc==32'd127_300_000 ) begin
        $writememh("pal_lo_ckpt2.hex", u_pal.u_lo.u_dual.u_ram.mem);
        $writememh("pal_hi_ckpt2.hex", u_pal.u_hi.u_dual.u_ram.mem);
        $display("DUMP-CKPT2 (pal, ~MAME frame 120): volcado en pal_dbg_cyc=%0d", pal_dbg_cyc);
    end

    if( pal_dbg_cyc==32'd160_000_000 ) begin
        $writememh("pal_lo_ckpt2b.hex", u_pal.u_lo.u_dual.u_ram.mem);
        $writememh("pal_hi_ckpt2b.hex", u_pal.u_hi.u_dual.u_ram.mem);
        $display("DUMP-CKPT2b (pal, ~frame 145): volcado en pal_dbg_cyc=%0d", pal_dbg_cyc);
    end
    if( pal_dbg_cyc==32'd200_000_000 ) begin
        $writememh("pal_lo_ckpt2c.hex", u_pal.u_lo.u_dual.u_ram.mem);
        $writememh("pal_hi_ckpt2c.hex", u_pal.u_hi.u_dual.u_ram.mem);
        $display("DUMP-CKPT2c (pal, ~frame 174): volcado en pal_dbg_cyc=%0d", pal_dbg_cyc);
    end
    if( pal_dbg_cyc==32'd250_000_000 ) begin
        $writememh("pal_lo_ckpt3.hex", u_pal.u_lo.u_dual.u_ram.mem);
        $writememh("pal_hi_ckpt3.hex", u_pal.u_hi.u_dual.u_ram.mem);
        $display("DUMP-CKPT3 (pal, ~frame 210): volcado en pal_dbg_cyc=%0d", pal_dbg_cyc);
    end
end
`endif

`ifdef SIMULATION
integer frame_cnt_s81=0;
reg     lvbl_l_s81=1;
task s81_dump_pal( input integer fnum );
    reg [8*20-1:0] fn_lo, fn_hi, fn_k251;
    begin
        $sformat(fn_lo,  "pal_lo_s81f%0d.hex",  fnum);
        $sformat(fn_hi,  "pal_hi_s81f%0d.hex",  fnum);
        $sformat(fn_k251,"k053251_s81f%0d.hex", fnum);
        $writememh(fn_lo,   u_pal.u_lo.u_dual.u_ram.mem);
        $writememh(fn_hi,   u_pal.u_hi.u_dual.u_ram.mem);
        $writememh(fn_k251, u_k251.mmr);
        $display("DUMP-S81F%0d (pal+k053251, frame local exacto %0d) k251={%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x}",
                  fnum, fnum, u_k251.mmr[0],u_k251.mmr[1],u_k251.mmr[2],u_k251.mmr[3],u_k251.mmr[4],
                  u_k251.mmr[5],u_k251.mmr[6],u_k251.mmr[7],u_k251.mmr[8],u_k251.mmr[9],u_k251.mmr[10],
                  u_k251.mmr[11],u_k251.mmr[12]);
    end
endtask
always @(posedge clk) begin
    lvbl_l_s81 <= lvbl;
    if( lvbl_l_s81 && !lvbl ) begin
        frame_cnt_s81 <= frame_cnt_s81 + 1;

        if( frame_cnt_s81+1==10 ) s81_dump_pal(10);
        if( frame_cnt_s81+1==15 ) s81_dump_pal(15);
        if( frame_cnt_s81+1==20 ) s81_dump_pal(20);
        if( frame_cnt_s81+1==440 ) s81_dump_pal(440);
        if( frame_cnt_s81+1==448 ) s81_dump_pal(448);
        if( frame_cnt_s81+1==450 ) s81_dump_pal(450);
        if( frame_cnt_s81+1==452 ) s81_dump_pal(452);
        if( frame_cnt_s81+1==460 ) s81_dump_pal(460);
        if( frame_cnt_s81+1==470 ) s81_dump_pal(470);
        if( frame_cnt_s81+1==480 ) s81_dump_pal(480);
        if( frame_cnt_s81+1==490 ) s81_dump_pal(490);
        if( frame_cnt_s81+1==500 ) s81_dump_pal(500);
        if( frame_cnt_s81+1==510 ) s81_dump_pal(510);
        if( frame_cnt_s81+1==520 ) s81_dump_pal(520);
        if( frame_cnt_s81+1==530 ) s81_dump_pal(530);
        if( frame_cnt_s81+1==550 ) s81_dump_pal(550);
        if( frame_cnt_s81+1==600 ) s81_dump_pal(600);
    end
end
`endif

`ifdef SIMULATION
integer n_palw=0;
reg     palw_hit_l=0;
always @(posedge clk) begin
    palw_hit_l <= |we_pal;
    if( |we_pal && !palw_hit_l && n_palw<200000 ) begin
        n_palw <= n_palw+1;
        $display("PAL-W[%0d]: cidx=%03x data=%04x dsn=%b cyc=%0d", n_palw, cpu_cidx, cpu_dout, cpu_dsn, pal_dbg_cyc);
    end
end
`endif

localparam [15:0] G_ONE = 16'd16384, G_SHD = 16'd9830, G_HIL = 16'd27307;

wire [15:0] shd_gain = ~shad ? G_ONE : dimpol ? G_SHD : G_HIL;
wire [ 3:0] dimfac   = { ~dimpol, dim };
wire [14:0] dim_gain = 15'd16384 - {11'd0,dimfac}*15'd819;
wire [30:0] gain_mul = {15'd0,shd_gain} * {16'd0,dim_gain};
wire [15:0] pxl_gain = dimpal[pal_addr[10:8]] ? gain_mul[29:14] : shd_gain;

function [7:0] gmul(input [7:0] c, input [15:0] g);
    reg [23:0] m;
    begin
        m    = {16'd0, c} * {8'd0, g};
        gmul = |m[23:22] ? 8'd255 : m[21:14];
    end
endfunction

reg [15:0] gain_l;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        { r8, g8, b8 } <= 0;
        gain_l <= G_ONE;
        bgr <= 0;
    end else begin
        { r8, g8, b8 } <= { pr8, pg8, pb8 };
        gain_l         <= pxl_gain;
        if( pxl_cen )
            bgr <= { gmul(b8,gain_l), gmul(g8,gain_l), gmul(r8,gain_l) };
    end
end

endmodule
