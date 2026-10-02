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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module mtlchamp_obj64arb #(parameter
    SDRAMW = 22
)(
    input                   rst,
    input                   clk,

    input  [SDRAMW-1:0]     slot0_addr,
    output [31:0]           slot0_dout,
    input                   slot0_cs,
    output                  slot0_ok,

    input  [SDRAMW-1:0]     slot1_addr,
    output [31:0]           slot1_dout,
    input                   slot1_cs,
    output                  slot1_ok,

    input  [SDRAMW-1:0]     slot2_addr,
    output [31:0]           slot2_dout,
    input                   slot2_cs,
    output                  slot2_ok,

    input  [SDRAMW-1:0]     slot3_addr,
    output [31:0]           slot3_dout,
    input                   slot3_cs,
    output                  slot3_ok,

    input                   sdram_ack,
    output                  sdram_rd,
    output [SDRAMW-1:0]     sdram_addr,
    input                   data_dst,
    input                   data_rdy,
    input      [15:0]       data_read
);

wire [SDRAMW-1:0] rd_addr0, rd_addr1;
wire              rd_req0,  rd_req1;

reg  [1:0] sel;
reg  [1:0] wc;
reg        cap;
reg        turno;
reg        ack_visto;

wire ultimo = cap && wc==2'd3;
wire libre  = sel==2'b00 || ultimo;

wire pide0 = rd_req0 & ~sel[0];
wire pide1 = rd_req1 & ~sel[1];
wire toma1 = turno ? pide1 : (pide0 ? 1'b0 : pide1);
wire toma0 = turno ? (pide1 ? 1'b0 : pide0) : pide0;

assign sdram_rd   = sel!=2'b00 && !ack_visto;
assign sdram_addr = sel[1] ? rd_addr1 : rd_addr0;

always @(posedge clk) begin
    if( rst ) begin
        sel <= 2'b00; wc <= 0; cap <= 0; turno <= 0; ack_visto <= 0;
    end else begin
        if( sdram_ack && sel!=2'b00 ) ack_visto <= 1'b1;

        if( data_dst ) begin
            cap <= 1'b1;
            wc  <= 2'd1;
        end else if( cap ) begin
            wc <= wc + 2'd1;
            if( wc==2'd3 ) cap <= 1'b0;
        end

        if( libre ) begin
            if( toma0 ) begin
                sel <= 2'b01; turno <= 1'b1; ack_visto <= 1'b0;
            end else if( toma1 ) begin
                sel <= 2'b10; turno <= 1'b0; ack_visto <= 1'b0;
            end else begin
                sel <= 2'b00; ack_visto <= 1'b0;
            end
        end
    end
end

mtlchamp_obj64 #( .SDRAMW(SDRAMW) ) u_l0(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .slot0_addr ( slot0_addr    ), .slot0_dout( slot0_dout ),
    .slot0_cs   ( slot0_cs      ), .slot0_ok  ( slot0_ok   ),
    .slot1_addr ( slot1_addr    ), .slot1_dout( slot1_dout ),
    .slot1_cs   ( slot1_cs      ), .slot1_ok  ( slot1_ok   ),
    .sdram_ack  ( sdram_ack & sel[0] ),
    .sdram_rd   ( rd_req0       ),
    .sdram_addr ( rd_addr0      ),
    .data_dst   ( data_dst & sel[0] ),
    .data_rdy   ( data_rdy      ),
    .data_read  ( data_read     )
);

mtlchamp_obj64 #( .SDRAMW(SDRAMW) ) u_l1(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .slot0_addr ( slot2_addr    ), .slot0_dout( slot2_dout ),
    .slot0_cs   ( slot2_cs      ), .slot0_ok  ( slot2_ok   ),
    .slot1_addr ( slot3_addr    ), .slot1_dout( slot3_dout ),
    .slot1_cs   ( slot3_cs      ), .slot1_ok  ( slot3_ok   ),
    .sdram_ack  ( sdram_ack & sel[1] ),
    .sdram_rd   ( rd_req1       ),
    .sdram_addr ( rd_addr1      ),
    .data_dst   ( data_dst & sel[1] ),
    .data_rdy   ( data_rdy      ),
    .data_read  ( data_read     )
);

endmodule
