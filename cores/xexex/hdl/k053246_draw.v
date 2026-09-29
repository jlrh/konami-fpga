/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 18-12-2022 */

module k053246_draw#( parameter
    AW       =  9,
    CW       = 12,
    PW       =  8,
    ZW       =  6,
    ZI       =  ZW-1,
    ZENLARGE =  0,
    SWAPH    =  0,
    KEEP_OLD =  0,

    SKIPOFF  =  1,
    XVIS_HI  = 768,
    XVIS_LO  = 992
)(
    input               rst,
    input               clk,

    input               draw,
    output reg          busy,
    input    [CW-1:0]   code,
    input    [AW-1:0]   xpos,
    input      [ 3:0]   ysub,
    input      [ 1:0]   trunc,

    input    [ZW-1:0]   hzoom,
    input               hz_keep,

    input               hflip,
    input               vflip,
    input      [PW-5:0] pal,

    output     [CW+6:2] rom_addr,
    output reg          rom_cs,
    input               rom_ok,
    input      [31:0]   rom_data,

    output reg [AW-1:0] buf_addr,
    output              buf_we,
    output     [PW-1:0] buf_din
);

localparam [ZW-1:0] HZONE = { {ZW-1{1'b0}},1'b1} << ZI;

reg      [31:0] pxl_data;
reg             rom_lsb;
reg      [ 3:0] cnt;
wire     [ 3:0] ysubf, pxl;
reg    [ZW-1:0] hz_cnt, nx_hz;
wire  [ZW-1:ZI] hzint;
reg             cen=0, moveon, readon, no_zoom;

wire skip_tile = (SKIPOFF!=0) && (xpos >= XVIS_HI) && (xpos < XVIS_LO);

assign ysubf   = ysub^{4{vflip}};
assign buf_din = { pal, pxl };
assign pxl     = hflip ?
    { pxl_data[31], pxl_data[23], pxl_data[15], pxl_data[ 7] } :
    { pxl_data[24], pxl_data[16], pxl_data[ 8], pxl_data[ 0] };

assign rom_addr = { code, rom_lsb^SWAPH[0], ysubf[3:0] };
assign buf_we   = busy & ~cnt[3];
assign hzint    = hz_cnt[ZW-1:ZI];

always @* begin
    if( ZENLARGE==1 ) begin
        readon = hzint >= 1;
        moveon = hzint <= 1;
        nx_hz = readon ? hz_cnt - HZONE : hz_cnt;
        if( moveon  ) nx_hz = nx_hz + hzoom;
        if( no_zoom ) {moveon, readon} = 2'b11;
    end else begin
        readon = 1;
        { moveon, nx_hz } = {1'b1, hz_cnt}-{1'b0,hzoom};
    end
end

always @(posedge clk) cen <= ~cen;

always @(posedge clk) begin
    if( rst ) begin
        rom_cs   <= 0;
        buf_addr <= 0;
        pxl_data <= 0;
        busy     <= 0;
        cnt      <= 0;
        hz_cnt   <= 0;
        no_zoom  <= 0;
    end else begin
        if( !busy ) begin
            if( draw && !skip_tile ) begin
                rom_lsb <= hflip;
                rom_cs  <= 1;
                busy    <= 1;
                cnt     <= 8;
                no_zoom <= hzoom == HZONE || hzoom == 0;
                if( !hz_keep ) begin
                    hz_cnt   <= HZONE >> 1;
                    buf_addr <= xpos;
                end
            end
        end else if(KEEP_OLD==0 || cen || cnt[3] ) begin

            if( rom_ok && rom_cs && cnt[3]) begin
                pxl_data <= rom_data;
                cnt[3]   <= 0;
                if( rom_lsb^hflip ) begin
                    rom_cs <= 0;
                end else begin
                    rom_cs <= 1;
                end
            end
            if( !cnt[3] ) begin
                hz_cnt   <= nx_hz;
                if( readon ) begin
                    cnt      <= cnt+1'd1;
                    pxl_data <= hflip ? pxl_data << 1 : pxl_data >> 1;
                end
                if( moveon ) buf_addr <= buf_addr+1'd1;
                rom_lsb  <= ~hflip;
                if( cnt[2:0]==7 && !rom_cs && readon ) busy <= 0;
                if( cnt[2:0]==7 && trunc==2'b10      ) busy <= 0;
                if( cnt[1:0]==3 && trunc==2'b11      ) busy <= 0;
            end
        end
    end
end

endmodule