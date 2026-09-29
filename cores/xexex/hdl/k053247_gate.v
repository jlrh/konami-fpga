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

module k053247_gate #( parameter
    AW    =  9,
    CW    = 12,
    PW    =  8,
    ZW    =  6,
    ZI    = ZW-1,
    ZENLARGE= 0,
    SWAPH =  0,
    HJUMP =  0,

    HFIX  =  1,
    LATCH =  0,
    FLIP_OFFSET=0,
    KEEP_OLD   =0,
    BUFDLY     =0,
    ALPHAW     =4,
    ALPHA      =0,
    SHADOW     =0,
    SW         =1,
    SHADOW_PEN = ALPHA,

    PACKED     =0

)(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               hs,
    input               flip,
    input    [AW-1:0]   hdump,

    input               draw,
    output              busy,
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
    output              rom_cs,
    input               rom_ok,
    input      [31:0]   rom_data,

    output     [PW-1:0] buf_pred,
    input      [PW-1:0] buf_din,

    output     [PW-1:0] pxl
);

reg  [AW-1:0] aeff, hdf, hdfix;
wire [AW-1:0] adly;

reg  [CW-1:0] dr_code;
reg  [AW-1:0] dr_xpos;
reg    [ 3:0] dr_ysub;
reg           dr_hflip, dr_vflip, dr_draw;
reg  [PW-5:0] dr_pal;

reg  [ZW-1:0] dr_hzoom;
reg           dr_hz_keep;

wire [AW-1:0] buf_addr;
wire          buf_we, we_dly;

wire [AW-1:0] buf_addr2;
wire          buf_we2;
wire [PW-1:0] buf_din2;

wire [AW-1:0] buf_addr3, buf_addr4;
wire          buf_we3,   buf_we4;
wire [PW-1:0] buf_din3,  buf_din4;
wire   [31:0] rom_sorted;

wire          pre_bsy;

assign rom_sorted = PACKED==0 ? rom_data :
{rom_data[31], rom_data[27], rom_data[23], rom_data[19], rom_data[15], rom_data[11], rom_data[7], rom_data[3],
 rom_data[30], rom_data[26], rom_data[22], rom_data[18], rom_data[14], rom_data[10], rom_data[6], rom_data[2],
 rom_data[29], rom_data[25], rom_data[21], rom_data[17], rom_data[13], rom_data[ 9], rom_data[5], rom_data[1],
 rom_data[28], rom_data[24], rom_data[20], rom_data[16], rom_data[12], rom_data[ 8], rom_data[4], rom_data[0] };

generate
    if( LATCH ) begin
        always @(posedge clk) begin
            dr_draw <= draw;
            if( !pre_bsy ) begin
                dr_code    <= code;
                dr_xpos    <= xpos;
                dr_ysub    <= ysub;
                dr_hflip   <= hflip;
                dr_vflip   <= vflip;
                dr_pal     <= pal;
                dr_hzoom   <= hzoom;
                dr_hz_keep <= hz_keep;
            end
        end
        assign busy = pre_bsy | dr_draw;
    end else begin
        always @* begin
            dr_draw    = draw;
            dr_code    = code;
            dr_xpos    = xpos;
            dr_ysub    = ysub;
            dr_hflip   = hflip;
            dr_vflip   = vflip;
            dr_pal     = pal;
            dr_hzoom   = hzoom;
            dr_hz_keep = hz_keep;
        end
        assign busy = pre_bsy;
    end
endgenerate

always @* begin
    aeff = 0;
    hdf  = 0;
    case( HJUMP )
        1: begin
            aeff[8:0] = { buf_addr[8], buf_addr[8] ^ buf_addr[7], buf_addr[6:0] };
            hdf  = hdump ^ { {AW-8{1'b0}}, flip&~hdump[8], {7{flip}} };
        end
        2: begin
            aeff[8:0] = { buf_addr[8],~buf_addr[8] | buf_addr[7], buf_addr[6:0] };
            hdf  = hdump ^ { {AW-8{1'b0}}, flip&hdump[8], {7{flip}} };
        end
        default: begin
            aeff = buf_addr;
            hdf  = flip ? ~hdfix+FLIP_OFFSET[8:0] : hdfix;
        end
    endcase
end

generate
    if(HJUMP==0 && HFIX==1) begin

        always @(posedge clk) begin
            if( rst ) begin
                hdfix <= 0;
            end else if(pxl_cen) begin
                hdfix <= ( hdump > hdfix || hs ) ? hdump+9'd1 : hdfix+9'd1;
            end
        end
    end else begin
        always @* hdfix=hdump;
    end
endgenerate

`ifdef VERILATOR

integer  rdcol=0;
reg      rdseen_c [0:511];
integer  ri;
initial for(ri=0;ri<512;ri=ri+1) rdseen_c[ri]=0;
reg hs_pl=0;
always @(posedge clk) begin
    hs_pl <= hs;
    if( hs ) rdcol <= 0;
    else if( pxl_cen ) begin
        if( rdcol<512 && !rdseen_c[rdcol] ) begin
            rdseen_c[rdcol] <= 1'b1;
            $display("RDMAP col=%0d hdf=%0d", rdcol, hdf);
        end
        rdcol <= rdcol + 1;
    end
end
`endif

generate
    if(BUFDLY==0) begin
        assign adly   = aeff,
               we_dly = buf_we;
    end else begin
        jtframe_sh #(.L(BUFDLY),.W(1+AW)) u_sh(
            .clk    ( clk           ),
            .clk_en ( 1'b1          ),
            .din    ( {aeff,buf_we} ),
            .drop   ( {adly,we_dly} )
        );
    end
endgenerate

k053247_draw #(
    .AW      ( AW       ),
    .CW      ( CW       ),
    .PW      ( PW       ),
    .ZW      ( ZW       ),
    .ZI      ( ZI       ),
    .ZENLARGE( ZENLARGE ),
    .SWAPH   ( SWAPH    ),
    .KEEP_OLD( KEEP_OLD )
)u_draw(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .draw       ( dr_draw   ),
    .busy       ( pre_bsy   ),
    .code       ( dr_code   ),
    .xpos       ( dr_xpos   ),
    .ysub       ( dr_ysub   ),
    .trunc      ( trunc     ),
    .hz_keep    ( dr_hz_keep),
    .hzoom      ( dr_hzoom  ),
    .hflip      ( dr_hflip  ),
    .vflip      ( dr_vflip  ),
    .pal        ( dr_pal    ),
    .rom_addr   ( rom_addr  ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    .rom_data   ( rom_sorted),

    .buf_addr   ( buf_addr  ),
    .buf_we     ( buf_we    ),
    .buf_din    ( buf_pred  ),
    .buf_addr2  ( buf_addr2 ),
    .buf_we2    ( buf_we2   ),
    .buf_din2   ( buf_din2  ),
    .buf_addr3  ( buf_addr3 ),
    .buf_we3    ( buf_we3   ),
    .buf_din3   ( buf_din3  ),
    .buf_addr4  ( buf_addr4 ),
    .buf_we4    ( buf_we4   ),
    .buf_din4   ( buf_din4  )
);

k053247_buffer #(
    .AW         ( AW          ),
    .DW         ( PW          ),
    .ALPHAW     ( ALPHAW      ),
    .ALPHA      ( ALPHA       ),
    .SW         ( SW          ),
    .SHADOW     ( SHADOW      ),
    .SHADOW_PEN ( SHADOW_PEN  ),
    .KEEP_OLD   ( KEEP_OLD    )
) u_linebuf(
    .clk        ( clk       ),
    .flip       ( 1'b0      ),
    .LHBL       ( ~hs       ),

    .we         ( we_dly    ),
    .wr_data    ( buf_din   ),
    .wr_addr    ( adly      ),

    .we2        ( buf_we2   ),
    .wr_data2   ( buf_din2  ),
    .wr_addr2   ( buf_addr2 ),
    .we3        ( buf_we3   ),
    .wr_data3   ( buf_din3  ),
    .wr_addr3   ( buf_addr3 ),
    .we4        ( buf_we4   ),
    .wr_data4   ( buf_din4  ),
    .wr_addr4   ( buf_addr4 ),

    .rd         ( pxl_cen   ),
    .rd_addr    ( hdf       ),
    .rd_data    ( pxl       )
);

endmodule