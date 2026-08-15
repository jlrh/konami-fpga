/*  ssriders — K053244/K053245 sprite buffer DMA.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module k053244_dma(
    input             rst,
    input             clk,
    input             pxl2_cen,

    input             dma_en,
    input             dma_trig,

    input             z_rej_en,
    input      [ 6:0] z_rej,
    input             z_rej_skip0,

    input             hs,
    input             lvbl,

    output     [13:1] dma_addr,
    input      [15:0] dma_data,
    output reg        dma_bsy,

    output            dma_weh,
    output            dma_wel,
    output     [11:1] dma_wr_addr,
    output     [15:0] dma_din,

    output reg        flicker
);

localparam ST_IDLE=2'd0, ST_CLR=2'd1, ST_COPY=2'd2;

reg  [ 1:0] st;
reg  [ 9:0] clr;
reg  [ 6:0] spr;
reg  [ 2:0] wrd;
reg  [ 6:0] slot;
reg         keep;
reg         pending;

reg  [15:0] wr_data;
reg  [10:1] wr_addr;
reg         wr_en;

reg  [ 1:0] lvbl_sh;
reg         hs_l;
wire        hs_pos = hs & ~hs_l;

wire [ 6:0] hdr_pri  = dma_data[6:0];
wire        hdr_act  = dma_data[15];
wire        hdr_rej  = z_rej_en && (|spr || !z_rej_skip0) && hdr_pri==z_rej;
wire        hdr_keep = hdr_act && !hdr_rej;

wire [ 6:0] cur_slot = wrd==3'd0 ? hdr_pri  : slot;
wire        cur_keep = wrd==3'd0 ? hdr_keep : keep;

assign dma_addr    = { 3'd0, spr, wrd };

assign dma_wr_addr = { 1'b0, wr_addr };
assign dma_din     = wr_data;
assign dma_wel     = wr_en & ~wr_addr[1];
assign dma_weh     = wr_en &  wr_addr[1];

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st      <= ST_IDLE;
        clr     <= 10'd0;
        spr     <= 7'd0;
        wrd     <= 3'd0;
        slot    <= 7'd0;
        keep    <= 1'b0;
        pending <= 1'b0;
        dma_bsy <= 1'b0;
        flicker <= 1'b0;
        wr_en   <= 1'b0;
        wr_addr <= 10'd0;
        wr_data <= 16'd0;
        lvbl_sh <= 2'd0;
        hs_l    <= 1'b0;
    end else if( pxl2_cen ) begin
        hs_l  <= hs;
        wr_en <= 1'b0;

        if( hs_pos ) begin
            lvbl_sh <= { lvbl_sh[0], lvbl };
            if( dma_en && lvbl_sh==2'b10 ) pending <= 1'b1;
        end
        if( dma_trig ) pending <= 1'b1;

        case( st )
            ST_IDLE: if( pending ) begin
                pending <= 1'b0;
                st      <= ST_CLR;
                dma_bsy <= 1'b1;
                flicker <= ~flicker;
                clr     <= 10'd0;
                spr     <= 7'd0;
                wrd     <= 3'd0;
            end
            ST_CLR: begin
                wr_en   <= 1'b1;
                wr_addr <= clr;
                wr_data <= 16'd0;
                clr     <= clr + 10'd1;
                if( &clr ) st <= ST_COPY;
            end
            ST_COPY: begin
                wr_en   <= cur_keep;
                wr_addr <= { cur_slot, wrd };
                wr_data <= dma_data;
                if( wrd==3'd0 ) begin
                    slot <= hdr_pri;
                    keep <= hdr_keep;
                end
                if( wrd==3'd6 ) begin
                    wrd <= 3'd0;
                    spr <= spr + 7'd1;
                    if( &spr ) begin
                        st      <= ST_IDLE;
                        dma_bsy <= 1'b0;
                    end
                end else begin
                    wrd <= wrd + 3'd1;
                end
            end
            default: st <= ST_IDLE;
        endcase
    end
end

endmodule
