module k053246_skid #( parameter DEPTH_LN = 1 )(
    input             rst,
    input             clk,
    input             hs,

    input             dr_start,
    output            dr_busy,
    input      [15:0] code,
    input      [ 9:0] hpos,
    input      [ 3:0] ysub,
    input      [11:0] hzoom,
    input             hz_keep,
    input             hflip,
    input             vflip,
    input      [ 9:0] attr,
    input      [ 1:0] shd,

    output reg        q_start,
    input             q_busy,
    output reg [15:0] q_code,
    output reg [ 9:0] q_hpos,
    output reg [ 3:0] q_ysub,
    output reg [11:0] q_hzoom,
    output reg        q_hz_keep,
    output reg        q_hflip,
    output reg        q_vflip,
    output reg [ 9:0] q_attr,
    output reg [ 1:0] q_shd
);

localparam DEPTH = 1<<DEPTH_LN,
           TW    = 16+10+4+12+1+1+1+10+2;

reg [TW-1:0]       fifo[0:DEPTH-1];
reg [DEPTH_LN:0]   wptr, rptr;

wire [DEPTH_LN:0]  ocup  = wptr - rptr;
wire               llena = ocup >= DEPTH[DEPTH_LN:0];
wire               vacia = wptr == rptr;

assign dr_busy = llena;

wire deliver = ~vacia & ~q_busy & ~q_start;

wire [TW-1:0] tile_in  = { code, hpos, ysub, hzoom, hz_keep, hflip, vflip, attr, shd };
wire [TW-1:0] tile_out = fifo[ rptr[DEPTH_LN-1:0] ];

reg hs_l;
always @(posedge clk) hs_l <= hs;
wire hs_edge = hs & ~hs_l;

always @(posedge clk) begin
    if( rst ) begin
        wptr    <= 0;
        rptr    <= 0;
        q_start <= 0;
    end else begin
        q_start <= 0;
        if( hs_edge ) begin
            wptr    <= 0;
            rptr    <= 0;
            q_start <= 0;
        end else begin
            if( deliver ) begin
                q_start <= 1;
                { q_code, q_hpos, q_ysub, q_hzoom,
                  q_hz_keep, q_hflip, q_vflip, q_attr, q_shd } <= tile_out;
                rptr    <= rptr + 1'd1;
            end
            if( dr_start & ~llena ) begin
                fifo[ wptr[DEPTH_LN-1:0] ] <= tile_in;
                wptr <= wptr + 1'd1;
            end
        end
    end
end

endmodule
