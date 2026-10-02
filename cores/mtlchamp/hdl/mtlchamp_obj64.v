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

module mtlchamp_obj64 #(parameter
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

    input                   sdram_ack,
    output reg              sdram_rd,
    output reg [SDRAMW-1:0] sdram_addr,
    input                   data_dst,
    input                   data_rdy,
    input      [15:0]       data_read
);

localparam [1:0] S_IDLE=2'd0, S_ACK=2'd1, S_DATA=2'd2;

reg  [        1:0] st;
reg  [       63:0] line;
reg  [SDRAMW-3:0]  tag, tag_pend;
reg                good, cap_run;
reg  [        1:0] wc;

wire [SDRAMW-3:0]  tag0 = slot0_addr[SDRAMW-1:2];
wire [SDRAMW-3:0]  tag1 = slot1_addr[SDRAMW-1:2];
wire               hit0 = good && tag==tag0;
wire               hit1 = good && tag==tag1;

assign slot0_ok   = slot0_cs & hit0;
assign slot1_ok   = slot1_cs & hit1;
assign slot0_dout = slot0_addr[1] ? line[63:32] : line[31:0];
assign slot1_dout = slot1_addr[1] ? line[63:32] : line[31:0];

wire miss0 = slot0_cs & ~hit0;
wire miss1 = slot1_cs & ~hit1;

wire capturing = data_dst | cap_run;

always @(posedge clk) begin
    if( rst ) begin
        st<=S_IDLE; sdram_rd<=0; sdram_addr<=0;
        good<=0; cap_run<=0; wc<=0; line<=0; tag<=0; tag_pend<=0;
    end else begin
        if( sdram_ack ) sdram_rd <= 0;
        case( st )
            S_IDLE: if( miss0 | miss1 ) begin
                        tag_pend   <= miss0 ? tag0 : tag1;
                        sdram_addr <= { miss0 ? tag0 : tag1, 2'b00 };
                        sdram_rd   <= 1'b1;

                        good       <= 1'b0;
                        st         <= S_ACK;
                    end
            S_ACK:  if( sdram_ack ) st <= S_DATA;
            S_DATA: if( cap_run && wc==2'd3 ) st <= S_IDLE;
            default: st <= S_IDLE;
        endcase

        if( capturing ) line <= { data_read, line[63:16] };
        if( data_dst ) begin
            cap_run <= 1'b1;
            wc      <= 2'd1;
            tag     <= tag_pend;
        end else if( cap_run ) begin
            wc <= wc + 2'd1;
            if( wc==2'd3 ) begin cap_run <= 1'b0; good <= 1'b1; end
        end
    end
end

`ifdef SIMULATION
reg avisado = 1'b0;
always @(posedge clk) begin
    if( !rst && slot0_cs && slot1_cs && tag0!==tag1 && !avisado ) begin
        avisado <= 1'b1;
        $display("⛔ %m: los dos puertos piden LINEAS DISTINTAS (tag0=%h tag1=%h). Un solo registro",
                 tag0, tag1);
        $display("   de linea NO basta: el fetch se colgara esperando todo_ok. Ver la cabecera.");
    end
end
`endif

wire _unused = &{1'b0, data_rdy, slot0_addr[0], slot1_addr[0], 1'b0};

endmodule
