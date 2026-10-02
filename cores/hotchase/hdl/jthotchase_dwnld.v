module jthotchase_dwnld(
    input      [21:0] prog_addr,
    input      [ 1:0] prog_ba,
    input      [ 7:0] prog_data,
    output reg [21:0] post_addr,
    output reg [ 7:0] post_data
);

wire        spr = prog_ba==2'd2 && prog_addr < 22'h180000;
wire [ 3:0] hi  = prog_data[7:4]==4'hf ? 4'h0 : prog_data[7:4];
wire [ 3:0] lo  = prog_data[3:0]==4'hf ? 4'h0 : prog_data[3:0];

always @* begin
    post_addr = spr ? { 1'b0, prog_addr[20:19], prog_addr[17:0], prog_addr[18] } : prog_addr;
    post_data = spr ? { hi, lo } : prog_data;
end

endmodule
