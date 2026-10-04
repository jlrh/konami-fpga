module konamigt_colmix(
    input            clk,
    input      [4:0] in_red, in_green, in_blue,
    output reg [7:0] out_red, out_green, out_blue
);
function [7:0] lut( input [4:0] v );
    case( v )
        5'd0: lut = 8'h00;
        5'd1: lut = 8'h01;
        5'd2: lut = 8'h02;
        5'd3: lut = 8'h04;
        5'd4: lut = 8'h05;
        5'd5: lut = 8'h06;
        5'd6: lut = 8'h08;
        5'd7: lut = 8'h09;
        5'd8: lut = 8'h0b;
        5'd9: lut = 8'h0d;
        5'd10: lut = 8'h0f;
        5'd11: lut = 8'h12;
        5'd12: lut = 8'h14;
        5'd13: lut = 8'h16;
        5'd14: lut = 8'h19;
        5'd15: lut = 8'h1c;
        5'd16: lut = 8'h21;
        5'd17: lut = 8'h24;
        5'd18: lut = 8'h29;
        5'd19: lut = 8'h2e;
        5'd20: lut = 8'h33;
        5'd21: lut = 8'h39;
        5'd22: lut = 8'h40;
        5'd23: lut = 8'h49;
        5'd24: lut = 8'h50;
        5'd25: lut = 8'h5b;
        5'd26: lut = 8'h68;
        5'd27: lut = 8'h78;
        5'd28: lut = 8'h8e;
        5'd29: lut = 8'ha8;
        5'd30: lut = 8'hcc;
        5'd31: lut = 8'hff;
    endcase
endfunction
always @(posedge clk) begin
    out_red   <= lut(in_red);
    out_green <= lut(in_green);
    out_blue  <= lut(in_blue);
end
endmodule
