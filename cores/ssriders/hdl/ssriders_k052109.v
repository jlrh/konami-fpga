/*  ssriders — K052109 (tilemaps) + K051962 (pixel mux).
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module ssriders_k052109 #(

    parameter [8:0] HB_OFFSET=0,
                    HB_EXTRAL=0,
                    HB_EXTRAR=0
)(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,
    output      [8:0] hdump,
    output      [8:0] vdump,
    output      [8:0] vrender,
    output      [8:0] vrender1,

    input             tile_cs,
    input      [12:0] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,
    output     [15:0] cpu_din,

    output            irqn,
    output            rst8,
    input             rmrd,
    output            flip,

    output     [19:2] lyrf_addr,
    output     [19:2] lyra_addr,
    output     [19:2] lyrb_addr,
    output            lyrf_cs,
    output            lyra_cs,
    output            lyrb_cs,
    input      [31:0] lyrf_data,
    input      [31:0] lyra_data,
    input      [31:0] lyrb_data,
    input             lyrf_ok,
    input             lyra_ok,
    input             lyrb_ok,

    output     [ 7:0] lyrf_pxl,
    output     [ 7:0] lyra_pxl,
    output     [ 7:0] lyrb_pxl,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,

    input             ioctl_ram,
    input      [15:0] ioctl_addr,
    output     [ 7:0] ioctl_din
);

`ifndef SSR_TSDLY
 `define SSR_TSDLY 18
`endif
localparam TSDLY = `SSR_TSDLY;
wire [8:0] hdump_i, vdump_i, vrender_i, vrender1_i;
wire       hs_i, vs_i, lhbl_i, lvbl_i;
reg  [8:0] hdump_sr[0:TSDLY-1], vdump_sr[0:TSDLY-1], vrender_sr[0:TSDLY-1], vrender1_sr[0:TSDLY-1];
reg  [TSDLY-1:0] hs_sr, vs_sr, lhbl_sr, lvbl_sr;
integer di;

always @(posedge clk) begin
    if( pxl_cen ) begin
        hs_sr <= { hs_sr[TSDLY-2:0], hs_i }; vs_sr <= { vs_sr[TSDLY-2:0], vs_i };
        lhbl_sr <= { lhbl_sr[TSDLY-2:0], lhbl_i }; lvbl_sr <= { lvbl_sr[TSDLY-2:0], lvbl_i };
        hdump_sr[0]<=hdump_i; vdump_sr[0]<=vdump_i; vrender_sr[0]<=vrender_i; vrender1_sr[0]<=vrender1_i;
        for( di=1; di<TSDLY; di=di+1 ) begin
            hdump_sr[di]<=hdump_sr[di-1]; vdump_sr[di]<=vdump_sr[di-1];
            vrender_sr[di]<=vrender_sr[di-1]; vrender1_sr[di]<=vrender1_sr[di-1];
        end
    end
end
assign hs    = hs_sr[TSDLY-1];
assign vs    = vs_sr[TSDLY-1];
assign lhbl  = lhbl_sr[TSDLY-1];
assign lvbl  = lvbl_sr[TSDLY-1];
assign hdump    = hdump_sr[TSDLY-1];
assign vdump    = vdump_sr[TSDLY-1];
assign vrender  = vrender_sr[TSDLY-1];
assign vrender1 = vrender1_sr[TSDLY-1];

`ifndef SSR_VDLY
 `define SSR_VDLY 8
`endif
localparam VDLY = `SSR_VDLY;

wire [8:0] vdump_s = VDLY==0 ? vdump_i : vdump_sr[VDLY>0 ? VDLY-1 : 0];

`ifndef SSR_VNEXT
 `define SSR_VNEXT 404
`endif
jtframe_vtimer #(
    .HCNT_START ( 9'h020    ),
    .HCNT_END   ( 9'h19F    ),
    .HB_START   ( 9'h029+HB_OFFSET-HB_EXTRAR ),
    .HB_END     ( 9'h069+HB_OFFSET+HB_EXTRAL ),
    .HS_START   ( 9'h194    ),
    .HS_END     ( 9'h02F    ),
    .H_VNEXT    ( 9'd`SSR_VNEXT ),
    .HINIT      ( 9'd`SSR_VNEXT ),
    .V_START    ( 9'h0F8    ),
    .VB_START   ( 9'h1EF    ),
    .VB_END     ( 9'h10F    ),
    .VS_START   ( 9'h1FF    ),
    .VS_END     ( 9'h0FF    ),
    .VCNT_END   ( 9'h1FF    )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump_i   ),
    .vrender    ( vrender_i ),
    .vrender1   ( vrender1_i),
    .H          ( hdump_i   ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( lhbl_i    ),
    .LVBL       ( lvbl_i    ),
    .HS         ( hs_i      ),
    .VS         ( vs_i      )
);

wire [15:0] chip_addr = { 2'b00, cpu_dsn[1], cpu_addr[12:0] };
wire [ 7:0] chip_dout = cpu_dsn[1] ? cpu_dout[7:0] : cpu_dout[15:8];
wire        chip_we   = tile_cs & cpu_we;
wire        chip_cs   = tile_cs;
wire [ 7:0] chip_din;
assign      cpu_din   = cpu_dsn[1] ? {8'h0, chip_din} : {chip_din, 8'h0};

localparam [2:0] REG_CFG=0, REG_SCR=1, REG_INT=2, REG_BANK0=3, REG_RMRD=4, REG_FLIP=5, REG_BANK1=6;
reg [7:0] mmr[0:6];
wire [7:0] bank0 = mmr[REG_BANK0];
wire [7:0] bank1 = mmr[REG_BANK1];
wire [7:0] cfg    = mmr[REG_CFG];
wire [7:0] int_en = mmr[REG_INT];
assign flip        = mmr[REG_FLIP][0];
wire hflip_en      = mmr[REG_FLIP][1];
wire vflip_en      = mmr[REG_FLIP][2];
wire cscra_en, rscra_en, cscrb_en, rscrb_en;
wire [1:0] fine_row;
assign { cscrb_en, rscrb_en, fine_row[1], cscra_en, rscra_en, fine_row[0] } = mmr[REG_SCR][5:0];

wire [2:0] reg_addr  = chip_addr[9:7];

wire       reg_we    = ram_cs[0] & chip_we & &chip_addr[12:10];

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        mmr[0]<=0; mmr[1]<=0; mmr[2]<=0; mmr[3]<=0; mmr[4]<=0; mmr[5]<=0; mmr[6]<=0;
    end else if( reg_we ) begin
        mmr[reg_addr] <= chip_dout;
    end
end

wire [1:0] ram_cs = { chip_addr[13], ~chip_addr[13] } & {2{chip_cs}};
wire [7:0] ram0_dout, ram1_dout;

assign chip_din = ram_cs[0] ? ram0_cpu_dout : ram1_cpu_dout;

reg  [8:0] hposa, hposb, heff_a, heff_b, vdumpf, hdumpf;
reg  [7:0] vposa, vposb;
reg  [10:0] map_a, map_b, vc;
reg  [1:0] col_aux, col_sel;
reg  [1:0] cab;
reg  [2:0] vsub_a, vsub_b, vmux, hsub_a, hsub_b;
reg        ca, cb, rd_rowscr, vflip;
wire [12:0] vaddr_scan;

reg  [12:0] vaddr, vaddr_nx;

wire        rd_vpos = hdump_i[8:3]==6'hC;
wire        rd_hpos = vdump_s[7:0]==0;
wire        scrlyr_sel = hdump_i[1];

always @* begin
    hdumpf = rd_rowscr || !flip ? hdump_i : ~hdump_i+9'd1;
    if( hdumpf < 9'h030 ) hdumpf = hdumpf+9'h180;
    if( hdumpf > 9'h1af ) hdumpf = hdumpf-9'h180;
    heff_a = hposa - 9'd6;
    heff_b = hposb - 9'd6;
    { ca, hsub_a } = { 1'b0, hdumpf[2:0] } + {1'd0,heff_a[2:0]};
    { cb, hsub_b } = { 1'b0, hdumpf[2:0] } + {1'd0,heff_b[2:0]};
    map_a[5:0] = hdumpf[8:3] + heff_a[8:3] + {5'd0,ca};
    map_b[5:0] = hdumpf[8:3] + heff_b[8:3] + {5'd0,cb};
    { map_a[10:6], vsub_a } = vdumpf[7:0] + vposa;
    { map_b[10:6], vsub_b } = vdumpf[7:0] + vposb;
    if( rd_rowscr ) begin
        vaddr_nx = { 4'b110_1, vdumpf[7:3], vdump_s[2:0] & {3{fine_row[scrlyr_sel]}}, hdump_i[0] };
    end else begin case( hdump_i[1:0] )
            0: vaddr_nx = { 7'b110_0000, hdump_i[8:3] };
            1: vaddr_nx = { 2'b01, map_a };
            2: vaddr_nx = { 2'b10, map_b };
            3: vaddr_nx = { 2'b00, vdumpf[7:3], hdumpf[8:3] };
        endcase
    end
end

always @* begin
    col_sel = scan_dout[11:10];
    case(col_sel)
        0: { cab, col_aux } = bank0[3:0];
        1: { cab, col_aux } = bank0[7:4];
        2: { cab, col_aux } = bank1[3:0];
        3: { cab, col_aux } = bank1[7:4];
    endcase
    case( hdump_i[1:0] )
        1: vmux = vsub_a;
        2: vmux = vsub_b;
        default: vmux = vdump_s[2:0];
    endcase
    vflip = scan_dout[9] & vflip_en;
    vc    = rmrd ? {2'b0,chip_addr[12:2]} : { scan_dout[7:0], vmux^{3{vflip}} };
end

wire [15:0] scan_dout = { ram0_dout, ram1_dout };
assign vaddr_scan = vaddr;

reg [7:0] code_f, code_a, code_b, colr_f, colr_a, colr_b;

reg [1:0] cab_f, cab_a, cab_b, caux_f, caux_a, caux_b;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        rd_rowscr<=0; vaddr<=0; vposa<=0; vposb<=0; vdumpf<=0;
        code_f<=0; code_a<=0; code_b<=0; colr_f<=0; colr_a<=0; colr_b<=0;
        cab_f<=0; cab_a<=0; cab_b<=0; caux_f<=0; caux_a<=0; caux_b<=0;
    end else begin
        vaddr     <= vaddr_nx;
        rd_rowscr <= hdump_i<9'h4f && hdump_i>9'h27;
        vdumpf    <= rd_rowscr ? vdump_s : vdump_s^{9{flip}};
        if( pxl_cen ) begin
            if( !rd_rowscr ) case( hdump_i[1:0] )
                0: begin
                    if( rd_vpos || cscra_en ) vposa <= scan_dout[15:8];
                    if( rd_vpos || cscrb_en ) vposb <= scan_dout[7:0];
                end
                1: begin colr_a<=scan_dout[15:8]; code_a<=scan_dout[7:0]; cab_a<=cab; caux_a<=col_aux; end
                2: begin colr_b<=scan_dout[15:8]; code_b<=scan_dout[7:0]; cab_b<=cab; caux_b<=col_aux; end
                3: begin colr_f<=scan_dout[15:8]; code_f<=scan_dout[7:0]; cab_f<=cab; caux_f<=col_aux; end
            endcase else case( hdump_i[1:0] )
                0: if( rd_hpos || rscra_en ) hposa[7:0] <= scan_dout[15:8];
                1: if( rd_hpos || rscra_en ) hposa[8]   <= scan_dout[8];
                2: if( rd_hpos || rscrb_en ) hposb[7:0] <= scan_dout[7:0];
                3: if( rd_hpos || rscrb_en ) hposb[8]   <= scan_dout[0];
            endcase
        end
    end
end

function [19:0] tile_addr( input [7:0] code, input [7:0] colr, input [1:0] cab, input [1:0] col_aux, input [2:0] row );
    tile_addr = { cab, col_aux, colr[4], colr[1:0], code, row, 2'b00 };
endfunction

wire [19:0] addr_f = tile_addr( code_f, colr_f, cab_f, caux_f, vdump_s[2:0]^{3{flip}} );
wire [19:0] addr_a = tile_addr( code_a, colr_a, cab_a, caux_a, vsub_a );
wire [19:0] addr_b = tile_addr( code_b, colr_b, cab_b, caux_b, vsub_b );

assign lyrf_addr = addr_f[19:2];
assign lyra_addr = addr_a[19:2];
assign lyrb_addr = addr_b[19:2];
assign lyrf_cs   = gfx_en[0];
assign lyra_cs   = gfx_en[1] & ~rmrd;
assign lyrb_cs   = gfx_en[2];

`ifdef SIMULATION
integer s82_ftrace_n=0;
wire s82_code_hit = code_f==8'h22 || code_f==8'h1f || code_f==8'h1d || code_f==8'h11 ||
                    code_f==8'h13 || code_f==8'h18 || code_f==8'h15 || code_f==8'h1b;
reg  s82_code_hit_l=0;
always @(posedge clk) begin
    s82_code_hit_l <= s82_code_hit;
    if( s82_code_hit && !s82_code_hit_l && frame_cnt_s81>=8 && frame_cnt_s81<=20 && s82_ftrace_n<400 ) begin
        s82_ftrace_n <= s82_ftrace_n+1;
        $display("S82-FTRACE[%0d] frame=%0d hdump_i=%0d vdump_i=%0d code_f=%02x row=%0d addr_f=%05x lyrf_addr=%05x",
                  s82_ftrace_n, frame_cnt_s81, hdump_i, vdump_i, code_f, vdump_i[2:0]^{3{flip}}, addr_f, lyrf_addr);
    end
end
`endif

`ifdef SIMULATION
reg  [17:0] s82_lyrf_addr_l=0;
reg  [7:0]  s82_okwait_f=0;
reg  [7:0]  s82_okwait_max=0;
integer     s82_oklat_n=0;
always @(posedge clk) begin
    s82_lyrf_addr_l <= lyrf_addr;
    if( lyrf_addr != s82_lyrf_addr_l ) s82_okwait_f <= 8'd0;
    else if( !lyrf_ok ) s82_okwait_f <= s82_okwait_f + 8'd1;
    if( lyrf_ok && s82_okwait_f > s82_okwait_max ) s82_okwait_max <= s82_okwait_f;
    if( lyrf_ok && s82_code_hit_l && frame_cnt_s81>=8 && frame_cnt_s81<=20 && s82_oklat_n<400 ) begin
        s82_oklat_n <= s82_oklat_n+1;
        $display("S82-OKLAT[%0d] frame=%0d hdump_i=%0d lyrf_addr=%05x wait=%0d max_so_far=%0d",
                  s82_oklat_n, frame_cnt_s81, hdump_i, lyrf_addr, s82_okwait_f, s82_okwait_max);
    end
end

integer s82_pend_n=0;
always @(posedge clk) if( pxl_cen && hdump_i[2:0]==0 && !lyrf_ok && frame_cnt_s81>=8 && frame_cnt_s81<=20 && s82_pend_n<50 ) begin
    s82_pend_n <= s82_pend_n+1;
    $display("S82-PEND[%0d] frame=%0d hdump_i=%0d lyrf_addr=%05x lyrf_ok=%b code_f=%02x",
              s82_pend_n, frame_cnt_s81, hdump_i, lyrf_addr, lyrf_ok, code_f);
end
`endif

wire vram0_dump_sel = ioctl_ram & (ioctl_addr[15:13]==3'b010);
wire vram1_dump_sel = ioctl_ram & (ioctl_addr[15:13]==3'b011);
wire [7:0] vram0_dump_q, vram1_dump_q;

wire [7:0] ram0_cpu_dout, ram1_cpu_dout;
jtframe_dual_nvram #(.AW(13),.SIMFILE("k052109_0.bin")) u_ram0(
    .clk0   ( clk               ),
    .data0  ( chip_dout         ),
    .addr0  ( chip_addr[12:0]   ),
    .we0    ( ram_cs[0] & chip_we & ~reg_we ),
    .q0     ( ram0_cpu_dout     ),
    .clk1   ( clk               ),
    .addr1a ( vaddr_scan        ),
    .addr1b ( ioctl_addr[12:0]  ),
    .sel_b  ( vram0_dump_sel    ),
    .data1  ( 8'd0              ),
    .we_b   ( 1'b0              ),
    .q1     ( ram0_dout         )
);
assign vram0_dump_q = ram0_dout;

jtframe_dual_nvram #(.AW(13),.SIMFILE("k052109_1.bin")) u_ram1(
    .clk0   ( clk               ),
    .data0  ( chip_dout         ),
    .addr0  ( chip_addr[12:0]   ),
    .we0    ( ram_cs[1] & chip_we & ~reg_we ),
    .q0     ( ram1_cpu_dout     ),
    .clk1   ( clk               ),
    .addr1a ( vaddr_scan        ),
    .addr1b ( ioctl_addr[12:0]  ),
    .sel_b  ( vram1_dump_sel    ),
    .data1  ( 8'd0              ),
    .we_b   ( 1'b0              ),
    .q1     ( ram1_dout         )
);
assign vram1_dump_q = ram1_dout;

wire mmr_dump_sel = ioctl_ram & (ioctl_addr[15:4]==12'h900) & (ioctl_addr[3:0]<4'd7);
wire [7:0] mmr_dump_q = mmr[ioctl_addr[2:0]];

assign ioctl_din = vram0_dump_sel ? vram0_dump_q :
                    vram1_dump_sel ? vram1_dump_q :
                    mmr_dump_sel   ? mmr_dump_q   : 8'd0;

`ifdef SIMULATION
integer vram_dbg_cyc=0;
always @(posedge clk) vram_dbg_cyc <= vram_dbg_cyc + 1;
always @(posedge clk) begin
    if( vram_dbg_cyc==32'd5_000_000 ) begin
        $writememh("vram0_ckpt1.hex", u_ram0.u_dual.u_ram.mem);
        $writememh("vram1_ckpt1.hex", u_ram1.u_dual.u_ram.mem);
        $display("DUMP-CKPT1 (vram, ~MAME frame 30): volcado en vram_dbg_cyc=%0d", vram_dbg_cyc);
    end
    if( vram_dbg_cyc==32'd127_300_000 ) begin
        $writememh("vram0_ckpt2.hex", u_ram0.u_dual.u_ram.mem);
        $writememh("vram1_ckpt2.hex", u_ram1.u_dual.u_ram.mem);
        $display("DUMP-CKPT2 (vram, ~MAME frame 120): volcado en vram_dbg_cyc=%0d", vram_dbg_cyc);
    end
end
`endif

`ifdef SIMULATION
integer frame_cnt_s81=0;
reg     lvbl_l_s81=1;

integer fi_s81;
task s81_dump_ckpt( input integer fnum );
    reg [8*20-1:0] fn_v0, fn_v1, fn_mmr;
    begin
        $sformat(fn_v0,  "vram0_s81f%0d.hex", fnum);
        $sformat(fn_v1,  "vram1_s81f%0d.hex", fnum);
        $sformat(fn_mmr, "mmr_s81f%0d.hex",   fnum);
        $writememh(fn_v0, u_ram0.u_dual.u_ram.mem);
        $writememh(fn_v1, u_ram1.u_dual.u_ram.mem);
        $writememh(fn_mmr, mmr);
        $display("DUMP-S81F%0d (vram+mmr, frame local exacto %0d) mmr={cfg=%02x,scr=%02x,int=%02x,bank0=%02x,rmrd=%02x,flip=%02x,bank1=%02x}",
                  fnum, fnum, mmr[0], mmr[1], mmr[2], mmr[3], mmr[4], mmr[5], mmr[6]);
    end
endtask
always @(posedge clk) begin
    lvbl_l_s81 <= lvbl_i;
    if( lvbl_l_s81 && !lvbl_i ) begin
        frame_cnt_s81 <= frame_cnt_s81 + 1;

        if( frame_cnt_s81+1==10 ) s81_dump_ckpt(10);
        if( frame_cnt_s81+1==15 ) s81_dump_ckpt(15);
        if( frame_cnt_s81+1==20 ) s81_dump_ckpt(20);
        if( frame_cnt_s81+1==440 ) s81_dump_ckpt(440);
        if( frame_cnt_s81+1==448 ) s81_dump_ckpt(448);
        if( frame_cnt_s81+1==450 ) s81_dump_ckpt(450);
        if( frame_cnt_s81+1==452 ) s81_dump_ckpt(452);
        if( frame_cnt_s81+1==460 ) s81_dump_ckpt(460);
        if( frame_cnt_s81+1==470 ) s81_dump_ckpt(470);
        if( frame_cnt_s81+1==480 ) s81_dump_ckpt(480);
        if( frame_cnt_s81+1==490 ) s81_dump_ckpt(490);
        if( frame_cnt_s81+1==500 ) s81_dump_ckpt(500);
        if( frame_cnt_s81+1==510 ) s81_dump_ckpt(510);
        if( frame_cnt_s81+1==520 ) s81_dump_ckpt(520);
        if( frame_cnt_s81+1==530 ) s81_dump_ckpt(530);
        if( frame_cnt_s81+1==550 ) s81_dump_ckpt(550);
        if( frame_cnt_s81+1==600 ) s81_dump_ckpt(600);
    end
end
`endif

jtframe_edge #(.QSET(0)) u_irq(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof (~lvbl_i    ),
    .clr    (~int_en[2] ),
    .q      ( irqn      )
);

reg [2:0] rst_cnt;
reg       rst8_r, v4_l2;
assign    rst8 = rst8_r;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        v4_l2 <= 0; rst_cnt <= 0; rst8_r <= 1;
    end else if( pxl_cen ) begin
        v4_l2 <= vdump_i[2];
        if( vdump_i=='hf8 && rst8_r && v4_l2 ) { rst8_r, rst_cnt } <= { rst8_r, rst_cnt } + 1'd1;
    end
end

reg [31:0] pxlf_data, pxla_data, pxlb_data;
reg [7:0]  colf_l, cola_l, colb_l;
reg        hflipa, hflipb;

function [3:0] flip4( input hf, input [31:0] data );
    flip4 = hf ? {data[24],data[16],data[8],data[0]} : {data[31],data[23],data[15],data[7]};
endfunction
function [31:0] shift32( input hf, input [31:0] data );
    shift32 = hf ? data >> 1 : data << 1;
endfunction

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        pxla_data<=0; pxlb_data<=0; pxlf_data<=0;
        cola_l<=0; colb_l<=0; colf_l<=0; hflipa<=0; hflipb<=0;
    end else if( pxl_cen ) begin
        if( hsub_a==0 ) begin pxla_data<=lyra_data; cola_l<=colr_a; hflipa<=(hflip_en&colr_a[0])^flip; end
        else pxla_data <= shift32(hflipa, pxla_data);
        if( hsub_b==0 ) begin pxlb_data<=lyrb_data; colb_l<=colr_b; hflipb<=(hflip_en&colr_b[0])^flip; end
        else pxlb_data <= shift32(hflipb, pxlb_data);
        if( hdump_i[2:0]==0 ) begin pxlf_data<=lyrf_data; colf_l<=colr_f; end
        else pxlf_data <= shift32(flip, pxlf_data);
    end
end

assign lyrf_pxl = gfx_en[0] ? { 1'b0, colf_l[7:5], flip4(  flip, pxlf_data) } : 8'd0;
assign lyra_pxl = gfx_en[1] ? { 1'b0, cola_l[7:5], flip4(hflipa, pxla_data) } : 8'd0;
assign lyrb_pxl = gfx_en[2] ? { 1'b0, colb_l[7:5], flip4(hflipb, pxlb_data) } : 8'd0;

`ifndef SIMULATION
wire _unused = &{1'b0, lyra_ok, lyrb_ok, debug_bus, vaddr_scan[10], 1'b0};
`endif

`ifdef SIMULATION
integer s85_frame=0;
reg     s85_lvbl_l=1'b1;

integer s85_hist[0:7];
integer s85_i;
reg     s85_lhbl_l=1'b1;
initial for(s85_i=0;s85_i<8;s85_i=s85_i+1) s85_hist[s85_i]=0;
always @(posedge clk) begin
    s85_lhbl_l <= lhbl;
    if( s85_lhbl_l && !lhbl ) s85_hist[heff_a[2:0]] <= s85_hist[heff_a[2:0]] + 1;
    s85_lvbl_l <= lvbl;
    if( s85_lvbl_l && !lvbl ) begin
        s85_frame <= s85_frame + 1;
        $display("S85-HSUB frame=%0d hposa=%03x hposb=%03x heff_a[2:0]=%0d | ROWSCR a=%b b=%b COLSCR a=%b b=%b fine_row=%b",
                 s85_frame, hposa, hposb, heff_a[2:0], rscra_en, rscrb_en, cscra_en, cscrb_en, fine_row);
        $display("S85-HIST frame=%0d filas por heff_a[2:0]: 0:%0d 1:%0d 2:%0d 3:%0d 4:%0d 5:%0d 6:%0d 7:%0d",
                 s85_frame, s85_hist[0],s85_hist[1],s85_hist[2],s85_hist[3],
                 s85_hist[4],s85_hist[5],s85_hist[6],s85_hist[7]);
        for(s85_i=0;s85_i<8;s85_i=s85_i+1) s85_hist[s85_i]<=0;
    end
end

always @(posedge clk) if( pxl_cen && s85_frame==2
                          && vdump_i>=9'd334 && vdump_i<=9'd336
                          && (hdump_i>=9'd400 || hdump_i<=9'd36) )
    $display("S85-TAIL v=%0d h=%0d hsub_a=%0d vdumpf=%0d vsub_a=%0d map_a=%0d lyra_addr=%05x lyra_pxl=%02x lhbl_ret=%b",
             vdump_i, hdump_i, hsub_a, vdumpf, vsub_a, map_a, lyra_addr, lyra_pxl, lhbl);

reg [8:0] s86_vdumpf_l=0, s86_vdump_l=0;
always @(posedge clk) if( pxl_cen && s85_frame==2 && vdump_i>=9'd334 && vdump_i<=9'd335 ) begin
    s86_vdumpf_l <= vdumpf;
    s86_vdump_l  <= vdump_i;
    if( vdump_i != s86_vdump_l )
        $display("S86-VNEXT  CAMBIO vdump_i en h=%0d : %0d -> %0d", hdump_i, s86_vdump_l, vdump_i);
    if( vdumpf != s86_vdumpf_l )
        $display("S86-VNEXT  CAMBIO vdumpf  en h=%0d : %0d -> %0d", hdump_i, s86_vdumpf_l, vdumpf);
    if( hsub_a==0 && hdump_i>=9'd380 )
        $display("S86-VNEXT  LATCH pxla en h=%0d : vdump_i=%0d vdumpf=%0d vsub_a=%0d map_a=%0d lyra_addr=%05x",
                 hdump_i, vdump_i, vdumpf, vsub_a, map_a, lyra_addr);
end
`endif

endmodule
