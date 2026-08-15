/*  ssriders — K053244 register bank.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module k053244_mmr(
    input             rst,
    input             clk,

    input             cs,
    input             cpu_we,
    input      [ 3:0] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,

    output     [ 7:0] cfg,
    output     [ 9:0] xoffset,
    output     [ 9:0] yoffset,
    output     [22:1] rmrd_addr,

    input      [ 7:0] st_addr,
    output reg [ 7:0] st_dout
);

localparam XOFF_HI=4'd0, XOFF_LO=4'd1, YOFF_HI=4'd2, YOFF_LO=4'd3,
           CFG    =4'd5, ROM_HI =4'd8, ROM_LO =4'd9, ROM_BK=4'd11;

reg [7:0] regs[0:15];
integer   i;

assign cfg     = regs[CFG];
assign xoffset = { regs[XOFF_HI][1:0], regs[XOFF_LO] };
assign yoffset = { regs[YOFF_HI][1:0], regs[YOFF_LO] };

assign rmrd_addr = { 3'd0, regs[ROM_BK][2:0], regs[ROM_HI], regs[ROM_LO] };

`ifdef SIMULATION

reg [7:0] mmr_init[0:7];
integer   f, fcnt=0;

initial begin
    f = $fopen("obj_mmr.bin","rb");
    if( f!=0 ) begin
        fcnt = $fread(mmr_init,f);
        $fclose(f);
        mmr_init[CFG][4] = 1;
        $display("k053244_mmr: %1d bytes de obj_mmr.bin, xoffset=%X yoffset=%X cfg=%X", fcnt,
            { mmr_init[XOFF_HI][1:0], mmr_init[XOFF_LO] },
            { mmr_init[YOFF_HI][1:0], mmr_init[YOFF_LO] }, mmr_init[CFG] );
    end
end
`endif

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        for( i=0; i<16; i=i+1 ) regs[i] <= 8'd0;
`ifdef SIMULATION
        if( fcnt!=0 ) for( i=0; i<8; i=i+1 ) regs[i] <= mmr_init[i];
`endif
    end else if( cs && cpu_we ) begin
        regs[cpu_addr] <= cpu_dout[7:0];
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) st_dout <= 8'd0;
    else case( st_addr[2:0] )
        3'd0: st_dout <= xoffset[7:0];
        3'd1: st_dout <= { 6'd0, xoffset[9:8] };
        3'd2: st_dout <= yoffset[7:0];
        3'd3: st_dout <= { 6'd0, yoffset[9:8] };
        3'd5: st_dout <= cfg;
        default: st_dout <= 8'd0;
    endcase
end

endmodule
