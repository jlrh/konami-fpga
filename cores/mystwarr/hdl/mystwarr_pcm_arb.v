module mystwarr_pcm_arb(
    input               rst,
    input               clk,
    input               cen,

    input               cs1,
    input      [23:0]   addr1,
    output              ok1,

    input               cs2,
    input      [23:0]   addr2,
    output              ok2,

    output reg          pcm_cs,
    output reg [21:0]   pcm_addr,
    input               pcm_ok
);

reg        pend1, pend2;
reg [21:0] paddr1, paddr2;
reg        busy, who, last;
reg        done1, done2;

always @(posedge clk) begin
    if (rst) begin
        pend1 <= 1'b0; pend2 <= 1'b0;
        done1 <= 1'b0; done2 <= 1'b0;
        busy  <= 1'b0; who   <= 1'b0; last <= 1'b0;
        pcm_cs <= 1'b0; pcm_addr <= 22'd0;
    end else begin

        if (cs1 && !pend1 && !done1 && !(busy && !who)) begin pend1 <= 1'b1; paddr1 <= addr1[21:0]; end
        if (cs2 && !pend2 && !done2 && !(busy &&  who)) begin pend2 <= 1'b1; paddr2 <= addr2[21:0]; end

        if (pend1 && !cs1) pend1 <= 1'b0;
        if (pend2 && !cs2) pend2 <= 1'b0;

        if (cen && (done1 || done2)) begin
            done1  <= 1'b0;
            done2  <= 1'b0;
            pcm_cs <= 1'b0;
        end

        if (!busy && !done1 && !done2) begin

            if (pend1 && !(pend2 && last==1'b0)) begin
                pcm_cs <= 1'b1; pcm_addr <= paddr1; who <= 1'b0;
                busy <= 1'b1; pend1 <= 1'b0; last <= 1'b0;
            end else if (pend2) begin
                pcm_cs <= 1'b1; pcm_addr <= paddr2; who <= 1'b1;
                busy <= 1'b1; pend2 <= 1'b0; last <= 1'b1;
            end
        end else if (busy && pcm_ok) begin

            busy <= 1'b0;
            if (!who) done1 <= 1'b1; else done2 <= 1'b1;
        end
    end
end

assign ok1 = done1;
assign ok2 = done2;

endmodule
