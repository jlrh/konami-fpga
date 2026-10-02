/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.  */
module mystwarr_obj_draw(
    input             rst,
    input             clk,

    input             draw,
    output            busy,

    input      [ 9:0] hpos,
    input      [11:0] hzoom,

    input             zfill,
    input             hz_keep,
    input      [ 9:0] attr,
    input      [ 1:0] shd,

    output reg        fetch_start,
    input             row_ok,
    input      [79:0] row_pen,

    output     [ 9:0] buf_addr,
    output            buf_we,
    output     [17:0] buf_din,

    output     [ 1:0] buf_shd_din,
    output            buf_shd_we
);

localparam [1:0] S_IDLE=0, S_WAIT=1, S_STRETCH=2;
localparam [11:0] HZONE = 12'h040;
localparam [ 9:0] HVIS  = 10'd288;
localparam [ 9:0] HTOT  = 10'd384;

localparam [ 9:0] FILL_N = HVIS + 10'd1;

reg [1:0]  st;
reg [ 9:0] hpos_r;
reg [11:0] hzoom_r, hz_cnt;
reg        hz_keep_r, zfill_r;
reg [ 4:0] color_r;
reg [ 7:0] pri_r;
reg [ 1:0] shd_r;
reg [79:0] row_pen_r;
reg [ 9:0] wk_addr;
reg [ 9:0] fill_cnt;
reg [ 3:0] wk_idx;

wire [4:0] pen_scr [0:15];
genvar gi;
generate
    for( gi=0; gi<16; gi=gi+1 ) begin : G_PEN
        assign pen_scr[gi] = row_pen_r[gi*5+:5];
    end
endgenerate

reg        pf_valid;
reg        pf_ready;
reg [79:0] pf_row;
reg [ 9:0] pf_hpos;
reg [11:0] pf_hzoom;
reg        pf_hzkeep, pf_zfill;
reg [ 4:0] pf_color;
reg [ 7:0] pf_pri;
reg [ 1:0] pf_shd;

assign busy = (st==S_WAIT) || (st==S_STRETCH && pf_valid);

wire        pf_hit     = pf_ready || (pf_valid && row_ok);
wire [79:0] pf_row_now = pf_ready ? pf_row : row_pen;

wire [4:0] pen_now  = pen_scr[wk_idx];
wire       es_shd   = shd_r != 2'd0 && pen_now == 5'd31;

wire [9:0] fill_addr = fill_cnt==0 ? HTOT-10'd1 : fill_cnt-10'd1;

assign buf_we      = (st == S_STRETCH) && !es_shd;
assign buf_addr    = zfill_r ? fill_addr : wk_addr;
assign buf_din     = { pri_r, color_r, pen_now };
assign buf_shd_we  = (st == S_STRETCH) &&  es_shd;
assign buf_shd_din = shd_r;

wire [5:0]  hzint      = hz_cnt[11:6];
wire        readon     = hzint >= 1;
wire        moveon     = hzint <= 1;
wire [11:0] hz_after_rd= readon ? (hz_cnt - HZONE) : hz_cnt;
wire [11:0] nx_hz       = moveon ? (hz_after_rd + hzoom_r) : hz_after_rd;
wire        last_pixel  = wk_idx == 4'd15;

wire        tile_end    = zfill_r ? (fill_cnt >= FILL_N-10'd1) : (readon && last_pixel);

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= S_IDLE; fetch_start <= 0;
        hz_cnt <= 0; wk_addr <= 0; wk_idx <= 0;
        row_pen_r <= 0;
        pf_valid <= 0; pf_ready <= 0; pf_row <= 0;
        pf_hpos <= 0; pf_hzoom <= 0; pf_hzkeep <= 0; pf_color <= 0; pf_pri <= 0;
        shd_r <= 0; pf_shd <= 0;
        zfill_r <= 0; pf_zfill <= 0; fill_cnt <= 0;
    end else begin
        fetch_start <= 0;
        case( st )
            S_IDLE: if( draw ) begin
                hpos_r      <= hpos;
                hzoom_r     <= hzoom;
                hz_keep_r   <= hz_keep;
                zfill_r     <= zfill;
                color_r     <= attr[4:0];
                pri_r       <= { attr[7:5], 5'b0 };
                shd_r       <= shd;
                fetch_start <= 1'b1;
                st          <= S_WAIT;
            end
            S_WAIT: if( row_ok ) begin
                row_pen_r <= row_pen;
                wk_idx    <= 4'd0;
                fill_cnt  <= 0;
                if( !hz_keep_r ) begin
                    hz_cnt  <= HZONE>>1;
                    wk_addr <= hpos_r;
                end
                st <= S_STRETCH;
            end
            S_STRETCH: begin
                if( !zfill_r ) hz_cnt <= nx_hz;
                if( moveon ) wk_addr <= wk_addr + 10'd1;
                if( zfill_r ) fill_cnt <= fill_cnt + 10'd1;

                if( draw && !pf_valid && !tile_end ) begin
                    pf_hpos     <= hpos;
                    pf_hzoom    <= hzoom;
                    pf_hzkeep   <= hz_keep;
                    pf_zfill    <= zfill;
                    pf_color    <= attr[4:0];
                    pf_pri      <= { attr[7:5], 5'b0 };
                    pf_shd      <= shd;
                    pf_valid    <= 1'b1;
                    pf_ready    <= 1'b0;
                    fetch_start <= 1'b1;
                end

                if( pf_valid && !pf_ready && row_ok ) begin
                    pf_row   <= row_pen;
                    pf_ready <= 1'b1;
                end

                if( tile_end ) begin

                        if( pf_hit ) begin
                            hpos_r    <= pf_hpos;
                            hzoom_r   <= pf_hzoom;
                            hz_keep_r <= pf_hzkeep;
                            zfill_r   <= pf_zfill;
                            color_r   <= pf_color;
                            pri_r     <= pf_pri;
                            shd_r     <= pf_shd;
                            row_pen_r <= pf_row_now;
                            wk_idx    <= 4'd0;
                            fill_cnt  <= 0;
                            pf_valid  <= 1'b0;
                            pf_ready  <= 1'b0;
                            if( !pf_hzkeep ) begin
                                hz_cnt  <= HZONE>>1;
                                wk_addr <= pf_hpos;
                            end
                        end else if( pf_valid ) begin
                            hpos_r    <= pf_hpos;
                            hzoom_r   <= pf_hzoom;
                            hz_keep_r <= pf_hzkeep;
                            zfill_r   <= pf_zfill;
                            color_r   <= pf_color;
                            pri_r     <= pf_pri;
                            shd_r     <= pf_shd;
                            pf_valid  <= 1'b0;
                            pf_ready  <= 1'b0;
                            st        <= S_WAIT;
                        end else if( draw ) begin
                            hpos_r      <= hpos;
                            hzoom_r     <= hzoom;
                            hz_keep_r   <= hz_keep;
                            zfill_r     <= zfill;
                            color_r     <= attr[4:0];
                            pri_r       <= { attr[7:5], 5'b0 };
                            shd_r       <= shd;
                            fetch_start <= 1'b1;
                            st          <= S_WAIT;
                        end else st <= S_IDLE;
                end else if( readon && !zfill_r ) wk_idx <= wk_idx + 4'd1;
            end
            default: st <= S_IDLE;
        endcase
    end
end

endmodule
