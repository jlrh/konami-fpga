module jthotchase_road #(
    parameter [8:0] HVIS0 = 9'd0
)(
    input             rst,
    input             clk,
    input      [ 8:0] hdump,
    input      [ 8:0] vrender,
    input      [ 8:0] vdump,
    input             hs,

    output reg [10:0] ram_addr,
    input      [15:0] ram_q,

    output reg [16:1] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [15:0] rom_data,

    output     [10:0] pxl,
    output            pxl_ok,
    output reg        busy_ovr
);

reg         hs_l, wpar, we;
reg  [ 2:0] st;
reg  [ 1:0] wt;
reg  [15:0] hi;
reg  [ 3:0] color;
reg  [12:0] tile;
reg  [ 9:0] u;
reg  [ 8:0] x, wx;
reg  [15:0] w;
reg  [16:1] addr_q;
reg  [10:0] wdata;
wire        start_line = hs & ~hs_l;
wire        vis_row    = vrender < 9'd224;
wire [ 2:0] p = u[2:0];
wire [ 3:0] nib = p[2] ? (p[1] ? w[11:8] : w[15:12]) : (p[1] ? w[3:0] : w[7:4]);

localparam IDLE=0, RAM=1, ROM=2, PIX=3;

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; we <= 0; hs_l <= 0; busy_ovr <= 0;
    end else begin
        hs_l   <= hs;
        we     <= 0;
        addr_q <= rom_addr;
        if( start_line ) begin
            if( st != IDLE ) busy_ovr <= 1;
            rom_cs <= 0;
            st     <= IDLE;
            if( vis_row ) begin
                wpar     <= vrender[0];
                ram_addr <= { 1'b0, vrender[8:0], 1'b0 };
                wt <= 0; st <= RAM;
            end
        end else case( st )
            RAM: begin
                wt <= wt + 1'd1;
                if( wt==1 ) begin hi <= ram_q; ram_addr[0] <= 1; end
                if( wt==3 ) begin : decode
                    reg [9:0] sc;
                    sc    = { hi[2:0], ram_q[15:10], 1'b0 };
                    color <= hi[7:4];
                    tile  <= { ram_q[8:0], 4'd0 };
                    u     <= 10'd352 + sc;
                    x     <= 0;
                    st    <= ROM;
                end
            end
            ROM: begin
                rom_addr <= { tile + {9'd0, u[9:6]}, u[5:3] };
                rom_cs   <= 1;
                if( rom_cs && rom_ok && addr_q==rom_addr ) begin
                    w <= rom_data; rom_cs <= 0; st <= PIX;
                end
            end
            PIX: begin
                we    <= 1;
                wx    <= x;
                wdata <= { 3'b111, color, nib };
                x     <= x + 1'd1;
                u     <= u + 1'd1;
                if( x == 9'd319 ) st <= IDLE;
                else if( p == 3'd7 ) st <= ROM;
            end
            default:;
        endcase
    end
end

wire [11:0] rdat;
jtframe_dual_ram #(.DW(12),.AW(10)) u_line(
    .clk0 ( clk ), .data0( {wdata[3:0]!=0, wdata} ), .addr0( {wpar, wx} ), .we0( we ), .q0(  ),
    .clk1 ( clk ), .data1( 12'd0 ), .addr1( {vdump[0], hdump - HVIS0} ), .we1( 1'b0 ), .q1( rdat )
);
assign pxl    = rdat[10:0];
assign pxl_ok = rdat[11];

endmodule
