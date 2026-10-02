module jthotchase_blitter #(parameter [15:0] COLOR_OFFS = 16'h0)(
    input             rst,
    input             clk,

    input             cs,
    input      [ 1:0] we,
    input      [ 4:1] addr,
    input      [15:0] din,

    input             cpu_BGACKn,
    output reg        blit_req,
    output            dma_on,
    output reg [23:1] dma_addr,
    output reg        dma_as,
    output reg        dma_rnw,
    output reg [15:0] dma_dout,
    input      [15:0] bus_din,
    input             bus_ok
);

reg  [15:0] r0, r2, r3, r4, r5, r6, r7, r8;
reg         trig_l;
wire        trig = cs && we[1] && addr==4'd8;

reg  [ 4:0] st, ret;
reg  [ 2:0] wcnt;
reg  [ 7:0] ecnt;
reg  [ 8:0] wleft;
reg  [23:0] src, lst, dst, ip, dp, ptr;
reg  [15:0] rdat;

assign dma_on = blit_req && !cpu_BGACKn;

localparam IDLE=0, WAITBUS=1, START=2,
           CPY=3, CPY_W=4,
           ENT=5, ENT_OFF=6, ENT_CPY=7, ENT_CPYW=8, ENT_COL=9, ENT_NEXT=10,
           ENDMARK=11, DONE=12,
           RD=16, RD_WAIT=17, WR=18, WR_END=19;

always @(posedge clk) begin
    if( rst ) begin
        { r0, r2, r3, r4, r5, r6, r7, r8 } <= 0;
    end else if( cs ) begin
        case( addr )
            0: begin if(we[1]) r0[15:8]<=din[15:8]; if(we[0]) r0[7:0]<=din[7:0]; end
            2: begin if(we[1]) r2[15:8]<=din[15:8]; if(we[0]) r2[7:0]<=din[7:0]; end
            3: begin if(we[1]) r3[15:8]<=din[15:8]; if(we[0]) r3[7:0]<=din[7:0]; end
            4: begin if(we[1]) r4[15:8]<=din[15:8]; if(we[0]) r4[7:0]<=din[7:0]; end
            5: begin if(we[1]) r5[15:8]<=din[15:8]; if(we[0]) r5[7:0]<=din[7:0]; end
            6: begin if(we[1]) r6[15:8]<=din[15:8]; if(we[0]) r6[7:0]<=din[7:0]; end
            7: begin if(we[1]) r7[15:8]<=din[15:8]; if(we[0]) r7[7:0]<=din[7:0]; end
            8: begin if(we[1]) r8[15:8]<=din[15:8]; if(we[0]) r8[7:0]<=din[7:0]; end
            default:;
        endcase
    end
end

always @(posedge clk) begin
    trig_l <= trig;
    if( rst ) begin
        st <= IDLE; blit_req <= 0; dma_as <= 0; dma_rnw <= 1;
    end else case( st )
        IDLE: if( trig && !trig_l ) begin blit_req <= 1; st <= WAITBUS; end
        WAITBUS: if( !cpu_BGACKn ) st <= START;
        START: begin
            src   <= {r2[7:0],r3} & ~24'd1;
            lst   <= {r4[7:0],r5} & ~24'd1;
            dst   <= {r6[7:0],r7} & ~24'd1;
            ecnt  <= r0[7:0];
            wleft <= {1'b0, r8[7:0]};
            st    <= r0[15:8]==8'd2 ? ENT : CPY;
        end

        CPY: if( wleft==0 ) st <= DONE; else begin ptr <= src; ret <= CPY_W; st <= RD; end
        CPY_W: begin
            ptr <= dst; dma_dout <= rdat; src <= src + 24'd2; dst <= dst + 24'd2;
            wleft <= wleft - 1'd1; ret <= CPY; st <= WR;
        end

        ENT: if( ecnt==0 ) st <= ENDMARK; else begin ptr <= lst + 24'd2; ret <= ENT_OFF; st <= RD; end
        ENT_OFF: begin
            ip    <= src + {8'd0, rdat};
            dp    <= dst;
            wleft <= {1'b0, r8[7:0]};
            st    <= ENT_CPY;
        end
        ENT_CPY: if( wleft==0 ) begin
                ptr <= lst; ret <= ENT_COL; st <= RD;
            end else begin
                ptr <= ip; ret <= ENT_CPYW; st <= RD;
            end
        ENT_CPYW: begin
            ptr <= dp; dma_dout <= rdat; ip <= ip + 24'd2; dp <= dp + 24'd2;
            wleft <= wleft - 1'd1; ret <= ENT_CPY; st <= WR;
        end
        ENT_COL: begin
            ptr <= dst + 24'd14; dma_dout <= rdat + COLOR_OFFS; ret <= ENT_NEXT; st <= WR;
        end
        ENT_NEXT: begin
            dst <= dst + 24'd16; lst <= lst + 24'd4; ecnt <= ecnt - 1'd1; st <= ENT;
        end
        ENDMARK: begin ptr <= dst; dma_dout <= 16'hffff; ret <= DONE; st <= WR; end
        DONE: begin blit_req <= 0; dma_as <= 0; st <= IDLE; end

        RD: begin
            dma_addr <= ptr[23:1]; dma_rnw <= 1; dma_as <= 1; wcnt <= 0; st <= RD_WAIT;
        end
        RD_WAIT: begin
            if( wcnt!=3'd7 ) wcnt <= wcnt + 1'd1;
            if( wcnt>=3'd4 && bus_ok ) begin rdat <= bus_din; dma_as <= 0; st <= ret; end
        end
        WR: begin
            dma_addr <= ptr[23:1]; dma_rnw <= 0; dma_as <= 1; st <= WR_END;
        end
        WR_END: begin dma_as <= 0; dma_rnw <= 1; st <= ret; end
        default: st <= IDLE;
    endcase
end

endmodule
