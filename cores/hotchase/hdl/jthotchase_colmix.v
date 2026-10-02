module jthotchase_colmix(
    input             clk,
    input             pxl_cen,
    input             video_on,
    input      [ 3:0] gfx_en,

    input      [10:0] bg_pxl,
    input             bg_ok,
    input      [10:0] rd_pxl,
    input             rd_ok,
    input      [11:0] spr_pxl,
    input             spr_op,
    input             spr_sh,
    input      [10:0] fg_pxl,
    input             fg_ok,

    output reg [11:0] pal_addr,
    input      [15:0] pal_q,
    output reg [10:0] hil_addr,
    input             hil_q,

    output reg [ 7:0] red,
    output reg [ 7:0] green,
    output reg [ 7:0] blue
);

reg  [ 2:0] ph;
reg  [12:0] idx;
reg         half, blk;
reg  [ 7:0] r8, g8, b8;

function [7:0] pal5( input [4:0] c ); pal5 = { c, c[4:2] }; endfunction
function [7:0] lum( input [3:0] n, input b, input h );
    lum = h ? pal5( {1'b0, n} ) >> 1 : pal5( {n, b} );
endfunction

always @(posedge clk) begin
    if( pxl_cen ) begin
        ph <= 0;
        red <= r8; green <= g8; blue <= b8;
    end else if( ph != 3'd7 ) ph <= ph + 1'd1;
    case( ph )
        2: begin : comp
            reg [12:0] i;
            i = 13'h1000;
            if( bg_ok  && bg_pxl[3:0]!=0 && gfx_en[0] ) i = { 2'd0, bg_pxl };
            if( rd_ok  && rd_pxl[3:0]!=0 && gfx_en[1] ) i = { 2'd0, rd_pxl };
            if( gfx_en[3] ) begin
                if( spr_op ) i = { 1'b0, spr_pxl };
                else if( spr_sh && !i[12] ) i = i | 13'h800;
            end
            if( fg_ok  && fg_pxl[3:0]!=0 && gfx_en[2] ) i = { 2'd0, fg_pxl };
            if( !video_on ) i = 13'h1000;
            idx      <= i;
            hil_addr <= i[10:0];
        end
        4: begin
            blk      <= idx[12];
            half     <= idx[11] && !hil_q;
            pal_addr <= idx[11] && !hil_q ? { 1'b0, idx[10:0] } : idx[11:0];
        end
        6: begin
            if( blk ) { r8, g8, b8 } <= 0;
            else begin
                r8 <= lum( pal_q[ 3:0], pal_q[12], half );
                g8 <= lum( pal_q[ 7:4], pal_q[13], half );
                b8 <= lum( pal_q[11:8], pal_q[14], half );
            end
        end
        default:;
    endcase
end

endmodule
