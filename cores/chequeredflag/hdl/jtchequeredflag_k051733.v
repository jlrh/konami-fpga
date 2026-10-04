/*  This file is part of the Chequered Flag core for MiSTer. GPLv3. */

module jtchequeredflag_k051733(
    input              clk,
    input              rst,
    input              cs,
    input              we,
    input      [4:0]   addr,
    input      [7:0]   din,
    output reg [7:0]   dout,
    output             busy
);

reg  [ 7:0] mem [0:31];
reg  [12:0] lfsr;
wire signed [15:0] op1 = { mem[0], mem[1] }, op2 = { mem[2], mem[3] };
wire        [15:0] op3 = { mem[4], mem[5] }, rad = { mem[6], mem[7] };
wire        [15:0] y1  = { mem[8], mem[9] }, x1 = { mem[10], mem[11] },
                   y2  = { mem[12], mem[13] }, x2 = { mem[14], mem[15] };

reg        we_l, rd_l;
reg  [4:0] addr_l;
wire       rd  = cs & ~we;
wire       wstb = cs & we & (~we_l | addr != addr_l);
wire       rstb = rd & (~rd_l | addr != addr_l);
wire       fb  = lfsr[1] ^ lfsr[8] ^ lfsr[12];

reg  [15:0] dq, dr, da, db;
reg  [ 4:0] dstep;
reg         dneg_q, dneg_r, dbusy, dzero;
reg  [15:0] quo, rem;
wire [16:0] dtry = { dr[14:0], da[15] } - { 1'b0, db };

reg  [31:0] sx;
reg  [15:0] sres;
reg  [33:0] srem;
reg  [ 4:0] sstep;
reg         sbusy;
reg  [15:0] sqr;
wire [33:0] strial = { srem[31:0], sx[31:30] } - { 16'd0, sres, 2'b01 };

reg start;
assign busy = start | dbusy | sbusy | wstb;
reg [7:0] lfsr_hold;

always @(posedge clk) begin
    if( rst ) begin
        lfsr <= 13'h0ff; we_l <= 0; rd_l <= 0; addr_l <= 0; start <= 0;
        dbusy <= 0; sbusy <= 0; quo <= 0; rem <= 0; sqr <= 0;
    end else begin
        we_l <= cs & we; rd_l <= rd; addr_l <= addr;
        start <= 0;
        if( wstb ) begin
            mem[addr] <= din;
            lfsr  <= { lfsr[11:0], fb };
            start <= 1;
        end else if( rstb ) begin
            lfsr_hold <= lfsr[7:0];
            lfsr  <= { lfsr[11:0], fb };
        end

        if( start ) begin
            dzero  <= op2 == 0;
            dneg_q <= op1[15] ^ op2[15];
            dneg_r <= op1[15];
            da     <= op1[15] ? -op1 : op1;
            db     <= op2[15] ? -op2 : op2;
            dr     <= 0; dq <= 0; dstep <= 16; dbusy <= 1;
        end else if( dbusy ) begin
            if( dstep != 0 ) begin
                if( !dtry[16] ) begin dr <= dtry[15:0]; dq <= { dq[14:0], 1'b1 }; end
                else            begin dr <= { dr[14:0], da[15] }; dq <= { dq[14:0], 1'b0 }; end
                da    <= { da[14:0], 1'b0 };
                dstep <= dstep - 1'd1;
            end else begin
                dbusy <= 0;
                if( dzero ) begin quo <= 0; rem <= op1; end
                else begin
                    quo <= dneg_q ? -dq : dq;
                    rem <= dneg_r ? -dr : dr;
                end
            end
        end

        if( start ) begin
            sx <= { op3, 16'd0 }; sres <= 0; srem <= 0; sstep <= 16; sbusy <= 1;
        end else if( sbusy ) begin
            if( sstep != 0 ) begin
                if( !strial[33] ) begin srem <= strial; sres <= { sres[14:0], 1'b1 }; end
                else              begin srem <= { srem[31:0], sx[31:30] }; sres <= { sres[14:0], 1'b0 }; end
                sx    <= { sx[29:0], 2'b0 };
                sstep <= sstep - 1'd1;
            end else begin
                sbusy <= 0;
                sqr   <= { sres[15:1], 1'b0 };
            end
        end
    end
end

wire signed [17:0] dx = $signed({2'b0, x2}) - $signed({2'b0, x1});
wire signed [17:0] dy = $signed({2'b0, y2}) - $signed({2'b0, y1});
wire        [17:0] adx = dx[17] ? -dx : dx, ady = dy[17] ? -dy : dy;
reg  [7:0] coll;
always @(*) begin
    if( adx > {2'b0,rad} || ady > {2'b0,rad} ) coll = 8'hff;
    else if( dy <= 0 ) begin
        if( dx <= 0 ) coll = (dy >= dx)  ? 8'h00 : 8'h06;
        else          coll = (dy >= -dx) ? 8'h04 : 8'h07;
    end else begin
        if( dx <= 0 ) coll = (dy > -dx)  ? 8'h02 : 8'h01;
        else          coll = (dy >  dx)  ? 8'h03 : 8'h05;
    end
end

always @(posedge clk) begin
    case( addr[2:0] )
        0: dout <= quo[15:8];
        1: dout <= quo[ 7:0];
        2: dout <= rem[15:8];
        3: dout <= rem[ 7:0];
        4: dout <= sqr[15:8];
        5: dout <= sqr[ 7:0];
        6: dout <= rstb ? lfsr[7:0] : lfsr_hold;
        7: dout <= coll;
    endcase
end

endmodule
