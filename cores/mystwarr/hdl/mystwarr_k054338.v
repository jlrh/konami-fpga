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

module mystwarr_k054338(
    input             rst,
    input             clk,

    input             alpha_cs,
    input      [ 4:1] cpu_addr,
    input      [15:0] cpu_dout,
    input             cpu_we,

    output     [23:0] bg_bgr,

    output     [ 8:0] shd1_r, shd1_g, shd1_b,
    output     [ 8:0] shd2_r, shd2_g, shd2_b,
    output     [ 8:0] shd3_r, shd3_g, shd3_b,

    output     [ 7:0] alpha_lv1, alpha_lv2, alpha_lv3,
    output            add1, add2, add3,
    output            ctl_kill, ctl_mixpri, ctl_shdpri, ctl_brtpri, ctl_wailsl, ctl_clipsl,

    output     [ 7:0] bri_lv1, bri_lv2, bri_lv3
);

reg [15:0] k38 [0:15];

always @(posedge clk, posedge rst) begin: k38_rst
    integer ai;
    if( rst ) for( ai=0; ai<16; ai=ai+1 ) k38[ai] <= 16'd0;
    else if( alpha_cs & cpu_we ) k38[cpu_addr] <= cpu_dout;
end

assign bg_bgr = { k38[1][7:0], k38[1][15:8], k38[0][7:0] };

assign shd1_r = k38[ 2][8:0]; assign shd1_g = k38[ 3][8:0]; assign shd1_b = k38[ 4][8:0];
assign shd2_r = k38[ 5][8:0]; assign shd2_g = k38[ 6][8:0]; assign shd2_b = k38[ 7][8:0];
assign shd3_r = k38[ 8][8:0]; assign shd3_g = k38[ 9][8:0]; assign shd3_b = k38[10][8:0];

function [7:0] expand_lv( input [4:0] raw );
    reg [4:0] inv;
    begin
        inv = 5'h1f - raw;
        expand_lv = { inv, inv[4:2] };
    end
endfunction

assign alpha_lv1 = expand_lv( k38[13][ 4: 0] );
assign alpha_lv2 = expand_lv( k38[14][12: 8] );
assign alpha_lv3 = expand_lv( k38[14][ 4: 0] );
assign add1      = k38[13][ 5];
assign add2      = k38[14][13];
assign add3      = k38[14][ 5];

assign bri_lv1 = k38[11][ 7:0];
assign bri_lv2 = k38[12][15:8];
assign bri_lv3 = k38[12][ 7:0];

assign ctl_kill   = k38[15][0];
assign ctl_mixpri = k38[15][1];
assign ctl_shdpri = k38[15][2];
assign ctl_brtpri = k38[15][3];
assign ctl_wailsl = k38[15][4];
assign ctl_clipsl = k38[15][5];

endmodule
