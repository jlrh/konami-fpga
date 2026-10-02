module jthotchase_68kdtack
#(parameter W=7,
            WD=6,
            N0=4
)(
    input         rst,
    input         clk,
    output   reg  cpu_cen,
    output   reg  cpu_cenb,
    input         bus_cs,
    input         bus_busy,
    input         ASn,
    input [1:0]   DSn,
    input [W-2:0] num,
    input [W-1:0] den,
    output reg    DTACKn
);
/* verilator lint_off WIDTH */

localparam CW=W+WD;

reg [CW-1:0] cencnt=0;
reg  [CW-1:0] missing;
reg  [5:0]   hc;
reg          wait1, asl, cyc_cs;
wire [W-1:0] num2 = { num, 1'b0 };
wire         over = cencnt>den-num2;
reg  [CW:0]  cencnt_nx;
reg          risefall=0;
wire         recover = ASn && asl && missing!=0 && !over;
wire         ends    = ASn && !asl;

always @(posedge clk) begin : dtack_gen
    if( rst ) begin
        DTACKn <= 1;
        wait1  <= 0;
    end else begin
        if( ASn | &DSn ) begin
            DTACKn <= 1;
            wait1  <= 1;
        end else if( !ASn ) begin
            wait1 <= 0;
            if( !wait1 ) DTACKn <= DTACKn && bus_cs && bus_busy;
        end
    end
end

always @(posedge clk) begin
    asl <= ASn;
    if( rst ) begin
        missing <= 0;
        hc      <= 0;
        cyc_cs  <= 0;
    end else begin
        if( !ASn ) begin
            if( (cpu_cen|cpu_cenb) && hc!=6'h3f ) hc <= hc+1'd1;
            if( bus_cs ) cyc_cs <= 1;
        end
        if( ends ) begin
            hc     <= 0;
            cyc_cs <= 0;
            if( cyc_cs && hc>N0 ) missing <= missing + (hc-N0);
        end else if( recover ) begin
            missing <= missing - 1'd1;
        end
    end
end

always @* begin
    cencnt_nx = over ? {1'b0,cencnt}+num2-den : { 1'b0, cencnt}+num2;
end

always @(posedge clk) begin
    cencnt  <= cencnt_nx[CW] ? {CW{1'b1}} : cencnt_nx[CW-1:0];
    if( rst ) cencnt <= 0;
    if( over || rst || recover ) begin
        cpu_cen  <=  risefall;
        cpu_cenb <= ~risefall;
        risefall <= ~risefall;
    end else begin
        cpu_cen  <= 0;
        cpu_cenb <= 0;
    end
end
/* verilator lint_on WIDTH */

endmodule
