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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module mtlchamp_obj_draw(
    input             rst,
    input             clk,

    input             draw,
    output            busy,

    input      [ 9:0] hpos,
    input      [11:0] hzoom,
    input             hz_keep,
    input      [ 9:0] attr,
    input      [ 1:0] shd,

    output reg        fetch_start,
    input      [15:0] code,
    input      [ 3:0] ysub,
    input             vflip,
    input             hflip,
    output reg [15:0] fetch_code,
    output reg [ 3:0] fetch_ysub,
    output reg        fetch_vflip,
    output reg        fetch_hflip,

    input             fetch_busy,
    input             row_ok,
    input      [79:0] row_pen,

    output     [ 9:0] buf_addr,
    output            buf_we,

    output     [20:0] buf_din
);

localparam [1:0] S_IDLE=0, S_WAIT=1, S_STRETCH=2;
localparam [11:0] HZONE = 12'h040;

reg [1:0]  st;
reg [ 9:0] hpos_r;
reg [11:0] hzoom_r, hz_cnt;
reg        hz_keep_r;
reg [ 4:0] color_r;
reg [ 7:0] pri_r;

reg        shdf_r, pf_shdf, qf_shdf;

reg [ 1:0] mix_r, pf_mix, qf_mix;
reg [79:0] row_pen_r;
reg [ 9:0] wk_addr;
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
reg        pf_hzkeep;
reg [ 4:0] pf_color;
reg [ 7:0] pf_pri;

reg        qf_valid, qf_ready;
reg [79:0] qf_row;
reg [ 9:0] qf_hpos;
reg [11:0] qf_hzoom;
reg        qf_hzkeep;
reg [ 4:0] qf_color;
reg [ 7:0] qf_pri;

wire fin_tile   = st==S_STRETCH && readon && last_pixel;
wire salta_fila = st==S_WAIT && row_ok && SKIP_EMPTY && row_pen==80'd0 && nozoom;

wire hueco      = !(pf_valid && qf_valid) && !fetch_busy && !fin_tile && !(st==S_WAIT && row_ok);

reg  draw_tomado;
wire aceptar    = draw && !draw_tomado && hueco && st!=S_IDLE;

wire emite_fetch = aceptar
                || (st==S_IDLE && draw)
                || (fin_tile && !pf_hit && !pf_valid && draw);

assign busy = (st==S_IDLE) ? fetch_busy : !hueco;

wire        pf_hit     = pf_ready || (pf_valid && row_ok);
wire [79:0] pf_row_now = pf_ready ? pf_row : row_pen;

wire        qf_toma     = qf_valid && !qf_ready && row_ok && !(pf_valid && !pf_ready);
wire        qf_ready_nx = qf_ready | qf_toma;
wire [79:0] qf_row_nx   = qf_toma ? row_pen : qf_row;

wire        consume_pf  = pf_valid && (fin_tile || salta_fila);

assign buf_we   = st == S_STRETCH;
assign buf_addr = wk_addr;
assign buf_din  = { mix_r, shdf_r, pri_r, color_r, pen_scr[wk_idx] };

wire        nozoom     = hzoom_r == HZONE || hzoom_r == 0;
wire [5:0]  hzint      = hz_cnt[11:6];
wire        readon_z   = hzint >= 1;
wire        moveon_z   = hzint <= 1;
wire        readon     = nozoom | readon_z;
wire        moveon     = nozoom | moveon_z;
wire [11:0] hz_after_rd= readon_z ? (hz_cnt - HZONE) : hz_cnt;
wire [11:0] nx_hz       = moveon_z ? (hz_after_rd + hzoom_r) : hz_after_rd;
wire        last_pixel  = wk_idx == 4'd15;

localparam SKIP_EMPTY = 1'b1;

`ifndef SYNTHESIS
integer n_rows = 0, n_empty = 0, n_nozo = 0, n_empty_nozo = 0;

integer c_idle = 0, c_wait = 0, c_str = 0, c_busy = 0, c_blk = 0;
always @(posedge clk) if( !rst ) begin
    case( st )
        S_IDLE:    c_idle <= c_idle + 1;
        S_WAIT:    c_wait <= c_wait + 1;
        S_STRETCH: c_str  <= c_str  + 1;
    endcase
    if( busy ) c_busy <= c_busy + 1;
    if( st==S_STRETCH && pf_valid ) c_blk <= c_blk + 1;
end

wire zoom1x_now = (st==S_WAIT) ? (hzoom_r==HZONE || hzoom_r==0)
                               : (pf_hzoom==HZONE || pf_hzoom==0);
always @(posedge clk) if( !rst && row_ok ) begin
    n_rows <= n_rows + 1;
    if( row_pen==80'd0 ) n_empty <= n_empty + 1;
    if( zoom1x_now ) begin
        n_nozo <= n_nozo + 1;
        if( row_pen==80'd0 ) n_empty_nozo <= n_empty_nozo + 1;
    end
end
`endif

`ifndef SYNTHESIS
integer dbg_seq = 0, dbg_wr = 0, dbg_rd = 0, dbg_ciclo = 0;
integer dbg_q [0:31];
integer id_cur = -1, id_pf = -1, id_qf = -1;
integer n_filas = 0, n_mal_wait = 0, n_mal_pf = 0, n_mal_qf = 0, n_huerfana = 0;
integer prim_ciclo = -1, prim_sitio = -1, prim_esp = -1, prim_lleg = -1;
always @(posedge clk) if( !rst ) begin
    dbg_ciclo = dbg_ciclo + 1;
    if( aceptar ) begin
        if( !pf_valid ) id_pf = dbg_seq; else id_qf = dbg_seq;
        dbg_q[dbg_wr%32] = dbg_seq; dbg_wr = dbg_wr+1; dbg_seq = dbg_seq+1;
    end
    case( st )
        S_IDLE: begin
            if( row_ok ) begin
                n_filas = n_filas+1; n_huerfana = n_huerfana+1;
                if( prim_ciclo<0 ) begin prim_ciclo=dbg_ciclo; prim_sitio=4; prim_esp=-1;
                    prim_lleg = (dbg_rd!=dbg_wr) ? dbg_q[dbg_rd%32] : -1; end
                if( dbg_rd!=dbg_wr ) dbg_rd = dbg_rd+1;
            end
            if( draw ) begin
                id_cur = dbg_seq;
                dbg_q[dbg_wr%32] = dbg_seq; dbg_wr = dbg_wr+1; dbg_seq = dbg_seq+1;
            end
        end
        S_WAIT: if( row_ok ) begin
            n_filas = n_filas+1;
            if( dbg_rd==dbg_wr ) n_huerfana = n_huerfana+1;
            else begin
                if( dbg_q[dbg_rd%32] != id_cur ) begin
                    n_mal_wait = n_mal_wait+1;
                    if( prim_ciclo<0 ) begin prim_ciclo=dbg_ciclo; prim_sitio=0;
                        prim_esp=id_cur; prim_lleg=dbg_q[dbg_rd%32]; end
                end
                dbg_rd = dbg_rd+1;
            end
            if( SKIP_EMPTY && row_pen==80'd0 && nozoom && pf_valid ) id_cur = id_pf;
        end
        S_STRETCH: begin
            if( row_ok ) begin
                n_filas = n_filas+1;
                if( dbg_rd==dbg_wr ) n_huerfana = n_huerfana+1;
                else begin
                    if( pf_valid && !pf_ready ) begin
                        if( dbg_q[dbg_rd%32] != id_pf ) begin
                            n_mal_pf = n_mal_pf+1;
                            if( prim_ciclo<0 ) begin prim_ciclo=dbg_ciclo; prim_sitio=1;
                                prim_esp=id_pf; prim_lleg=dbg_q[dbg_rd%32]; end
                        end
                    end else if( qf_valid && !qf_ready ) begin
                        if( dbg_q[dbg_rd%32] != id_qf ) begin
                            n_mal_qf = n_mal_qf+1;
                            if( prim_ciclo<0 ) begin prim_ciclo=dbg_ciclo; prim_sitio=2;
                                prim_esp=id_qf; prim_lleg=dbg_q[dbg_rd%32]; end
                        end
                    end else begin
                        n_huerfana = n_huerfana+1;
                        if( prim_ciclo<0 ) begin prim_ciclo=dbg_ciclo; prim_sitio=3;
                            prim_esp=-1; prim_lleg=dbg_q[dbg_rd%32]; end
                    end
                    dbg_rd = dbg_rd+1;
                end
            end
            if( readon && last_pixel ) begin
                if( pf_hit || pf_valid ) id_cur = id_pf;
                else if( draw ) begin
                    id_cur = dbg_seq;
                    dbg_q[dbg_wr%32] = dbg_seq; dbg_wr = dbg_wr+1; dbg_seq = dbg_seq+1;
                end
            end
        end
    endcase
    if( consume_pf ) begin id_pf = id_qf; id_qf = -1; end
end
`endif
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= S_IDLE; fetch_start <= 0; draw_tomado <= 0;
        fetch_code <= 0; fetch_ysub <= 0; fetch_vflip <= 0; fetch_hflip <= 0;
        hz_cnt <= 0; wk_addr <= 0; wk_idx <= 0;
        row_pen_r <= 0;
        pf_valid <= 0; pf_ready <= 0; pf_row <= 0;
        pf_hpos <= 0; pf_hzoom <= 0; pf_hzkeep <= 0; pf_color <= 0; pf_pri <= 0;
        qf_valid <= 0; qf_ready <= 0; qf_row <= 0;
        qf_hpos <= 0; qf_hzoom <= 0; qf_hzkeep <= 0; qf_color <= 0; qf_pri <= 0;
        shdf_r <= 0; pf_shdf <= 0; qf_shdf <= 0;
        mix_r <= 0; pf_mix <= 0; qf_mix <= 0;
    end else begin
        fetch_start <= 0;

        if( !draw ) draw_tomado <= 1'b0;

        if( emite_fetch ) begin
            fetch_start <= 1'b1;
            fetch_code  <= code;
            fetch_ysub  <= ysub;
            fetch_vflip <= vflip;
            fetch_hflip <= hflip;
            draw_tomado <= 1'b1;
        end

        if( aceptar ) begin
            if( !pf_valid ) begin
                pf_hpos   <= hpos;
                pf_hzoom  <= hzoom;
                pf_hzkeep <= hz_keep;
                pf_color  <= attr[4:0];
                pf_pri    <= { attr[7:5], 5'b0 };
                pf_shdf   <= attr==10'h11f;
                pf_mix    <= (attr==10'h11f) ? 2'd0 : attr[9:8];
                pf_valid  <= 1'b1;
                pf_ready  <= 1'b0;
            end else begin
                qf_hpos   <= hpos;
                qf_hzoom  <= hzoom;
                qf_hzkeep <= hz_keep;
                qf_color  <= attr[4:0];
                qf_pri    <= { attr[7:5], 5'b0 };
                qf_shdf   <= attr==10'h11f;
                qf_mix    <= (attr==10'h11f) ? 2'd0 : attr[9:8];
                qf_valid  <= 1'b1;
                qf_ready  <= 1'b0;
            end
        end

        case( st )
            S_IDLE: if( draw ) begin
                hpos_r      <= hpos;
                hzoom_r     <= hzoom;
                hz_keep_r   <= hz_keep;
                color_r     <= attr[4:0];
                pri_r       <= { attr[7:5], 5'b0 };
                shdf_r      <= attr==10'h11f;
                mix_r       <= (attr==10'h11f) ? 2'd0 : attr[9:8];
                st          <= S_WAIT;
            end
            S_WAIT: if( row_ok ) begin

                if( SKIP_EMPTY && row_pen==80'd0 && nozoom ) begin
                    wk_addr <= (hz_keep_r ? wk_addr : hpos_r) + 10'd16;
                    hz_cnt  <= HZONE + (HZONE>>1);

                    if( pf_valid ) begin
                        hpos_r    <= pf_hpos;
                        hzoom_r   <= pf_hzoom;
                        hz_keep_r <= pf_hzkeep;
                        color_r   <= pf_color;
                        pri_r     <= pf_pri;
                        shdf_r    <= pf_shdf;
                        mix_r     <= pf_mix;
                        st        <= S_WAIT;
                    end else st <= S_IDLE;
                end else begin
                    row_pen_r <= row_pen;
                    wk_idx    <= 4'd0;
                    if( !hz_keep_r ) begin
                        hz_cnt  <= HZONE>>1;
                        wk_addr <= hpos_r;
                    end
                    st <= S_STRETCH;
                end
            end
            S_STRETCH: begin
                hz_cnt   <= nx_hz;
                if( moveon ) wk_addr <= wk_addr + 10'd1;

                if( pf_valid && !pf_ready && row_ok ) begin
                    pf_row   <= row_pen;
                    pf_ready <= 1'b1;
                end else if( qf_valid && !qf_ready && row_ok ) begin
                    qf_row   <= row_pen;
                    qf_ready <= 1'b1;
                end

                if( readon ) begin
                    if( last_pixel ) begin

                        if( pf_hit ) begin
                            hpos_r    <= pf_hpos;
                            hzoom_r   <= pf_hzoom;
                            hz_keep_r <= pf_hzkeep;
                            color_r   <= pf_color;
                            pri_r     <= pf_pri;
                            shdf_r    <= pf_shdf;
                            mix_r     <= pf_mix;
                            row_pen_r <= pf_row_now;
                            wk_idx    <= 4'd0;

                            if( !pf_hzkeep ) begin
                                hz_cnt  <= HZONE>>1;
                                wk_addr <= pf_hpos;
                            end
                        end else if( pf_valid ) begin

                            hpos_r    <= pf_hpos;
                            hzoom_r   <= pf_hzoom;
                            hz_keep_r <= pf_hzkeep;
                            color_r   <= pf_color;
                            pri_r     <= pf_pri;
                            shdf_r    <= pf_shdf;
                            mix_r     <= pf_mix;
                            st        <= S_WAIT;

                        end else if( draw ) begin
                            hpos_r      <= hpos;
                            hzoom_r     <= hzoom;
                            hz_keep_r   <= hz_keep;
                            color_r     <= attr[4:0];
                            pri_r       <= { attr[7:5], 5'b0 };
                            shdf_r      <= attr==10'h11f;
                            mix_r       <= (attr==10'h11f) ? 2'd0 : attr[9:8];
                            st          <= S_WAIT;
                        end else st <= S_IDLE;
                    end else wk_idx <= wk_idx + 4'd1;
                end
            end
            default: st <= S_IDLE;
        endcase

        if( consume_pf ) begin
            pf_hpos   <= qf_hpos;
            pf_hzoom  <= qf_hzoom;
            pf_hzkeep <= qf_hzkeep;
            pf_color  <= qf_color;
            pf_pri    <= qf_pri;
            pf_shdf   <= qf_shdf;
            pf_mix    <= qf_mix;
            pf_valid  <= qf_valid;
            pf_ready  <= qf_ready_nx;
            pf_row    <= qf_row_nx;
            qf_valid  <= 1'b0;
            qf_ready  <= 1'b0;
        end
    end
end

endmodule
