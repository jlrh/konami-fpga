/*

FPGA compatible core of arcade hardware by LMN-san, OScherler, Raki.

This core is available for hardware compatible with MiSTer.
Other FPGA systems may be supported by the time you read this.
This work is not mantained by the MiSTer project. Please contact the
core authors for issues and updates.

(c) LMN-san, OScherler, Raki 2020–2023.

Support the authors:

       Raki: https://www.patreon.com/ikamusume
    LMN-san: https://ko-fi.com/lmnsan
  OScherler: https://ko-fi.com/oscherler

The authors do not endorse or participate in illegal distribution
of copyrighted material. This work can be used with legally
obtained ROM dumps of games or with homebrew software for
the arcade platform.

This file license is GNU GPLv3.
You can read the whole license file at http://www.gnu.org/licenses/

*/

//================================================================================
//  K005295 SPRITE ENGINE
//
//  December 03, 2021. Copyright © 2021-2022 Raki @ bubsys85.net
//================================================================================

`default_nettype none

module K005295
#(parameter               __ENABLE_DOUBLE_HEIGHT_MODE = 1'b0)
(

    input   wire            i_EMU_MCLK,
    input   wire            i_EMU_CLK6MPCEN_n,

    input   wire            i_DMA_n,
    input   wire            i_VBLANKH_n,
    input   wire            i_VBLANK_n,
    input   wire            i_HBLANK_n,
    input   wire            i_ABS_4H,
    input   wire            i_ABS_2H,
    input   wire            i_ABS_1H,
    input   wire            i_CHAMPX,
    input   wire            i_OBJWR,

    input   wire            i_FLIP,

    input   wire    [7:0]   i_OBJDATA,
    output  wire    [2:0]   o_ORA,

    output  wire            o_CAS,

`ifdef GX400_UNFOLD_DRAM_ADDR
    output  wire   [15:0]   o_FA,
    output  wire   [15:0]   o_FB,
`else
    output  wire    [7:0]   o_FA,
    output  wire    [7:0]   o_FB,
`endif

    output  reg             o_XA7,
    output  reg             o_XB7,

    input   wire            i_OBJHL,
    output  reg             o_CHAOV,
    output  wire            o_ORINC,

    output  reg             o_WRTIME2,
    output  wire            o_COLORLATCH_n,
    output  wire            o_XPOS_D0,
    output  reg             o_PIXELLATCH_WAIT_n,
    output  wire            o_LATCH_A_D2,
    output  wire    [2:0]   o_PIXELSEL,

`ifdef GX400_UNFOLD_DRAM_ADDR
    output  wire   [13:0]   o_OCA
`else
    output  wire    [7:0]   o_OCA
`endif
);

reg             hsize_parity = 1'b0;
reg             pixellatch_wait_n;

wire            pixel3_n = ~(i_ABS_1H & i_ABS_2H);

reg             DMA_4H_CLKD_n = 1'b1;
wire            new_vblank_n = DMA_4H_CLKD_n | i_VBLANKH_n;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if({i_ABS_4H, i_ABS_2H, i_ABS_1H} == 3'd3)
        begin
            DMA_4H_CLKD_n <= i_DMA_n;
        end
    end
end

wire            LATCH_A_en_n;
wire            LATCH_B_en_n;
wire            LATCH_C_en_n;
wire            LATCH_D_en_n;
wire            LATCH_E_en_n;
wire            LATCH_F_en_n;

assign  o_COLORLATCH_n = LATCH_D_en_n;

assign  o_ORA[2] = ~&{                                LATCH_C_en_n,   LATCH_D_en_n,   LATCH_E_en_n,   LATCH_F_en_n};
assign  o_ORA[1] = ~&{LATCH_A_en_n,   LATCH_B_en_n,                                   LATCH_E_en_n,   LATCH_F_en_n};
assign  o_ORA[0] = ~&{                LATCH_B_en_n,                   LATCH_D_en_n,                   LATCH_F_en_n};

reg             latching_start;
reg     [6:0]   attr_latch_en_sr;
assign  {LATCH_A_en_n, LATCH_B_en_n, LATCH_C_en_n,
         LATCH_D_en_n, LATCH_E_en_n, LATCH_F_en_n, o_ORINC} = attr_latch_en_sr;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(i_ABS_1H == 1'b0)
        begin
            attr_latch_en_sr[6]   <= ~latching_start;
            attr_latch_en_sr[5:0] <= attr_latch_en_sr[6:1];
        end
    end
end

reg     [7:0]   LATCH_A;
reg     [7:0]   LATCH_B;
reg     [7:0]   LATCH_C;
reg     [7:0]   LATCH_D;
reg     [7:0]   LATCH_E;
`ifdef SIMULATION
reg     [7:0]   LATCH_F;
`endif

assign  o_XPOS_D0 = LATCH_E[0];
assign  o_LATCH_A_D2 = LATCH_A[2];

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(!LATCH_A_en_n)
        begin
            LATCH_A <= i_OBJDATA & {6'b1111_11, __ENABLE_DOUBLE_HEIGHT_MODE, 1'b1};
        end

        if(!LATCH_B_en_n)
        begin
            LATCH_B <= i_OBJDATA;
        end

        if(!LATCH_C_en_n)
        begin
            LATCH_C <= i_OBJDATA;
        end

        if(!LATCH_D_en_n)
        begin
            LATCH_D <= i_OBJDATA;
        end

        if(!LATCH_E_en_n)
        begin
            LATCH_E <= i_OBJDATA;
        end

    `ifdef SIMULATION
        if(!LATCH_F_en_n)
        begin
            LATCH_F <= i_OBJDATA;
        end
    `endif
    end
end

`ifdef SIMULATION
    wire [9:0] dbg_sprite_zoom    = { LATCH_A[7:6], LATCH_B };
    wire [2:0] dbg_sprite_size    = LATCH_A[5:3];
    wire       dbg_sprite_hflip   = LATCH_A[0];
    wire [9:0] dbg_sprite_code    = { LATCH_D[7:6], LATCH_C };
    wire       dbg_sprite_vflip   = LATCH_D[5];
    wire [3:0] dbg_sprite_palette = LATCH_D[4:1];
    wire [8:0] dbg_sprite_xpos    = { LATCH_D[0], LATCH_E };
    wire [7:0] dbg_sprite_ypos    = LATCH_F;
`endif

reg             hzoom_cnt_n;
reg             hzoom_rst_n;
reg     [9:0]   hzoom_acc = 10'd0;
wire    [10:0]  hzoom_nextval = hzoom_acc + {LATCH_A[7:6], LATCH_B};
reg     [2:0]   hzoom_tileline_cntr;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(!hzoom_rst_n)
        begin
            hzoom_acc <= 10'd0;
            hzoom_tileline_cntr <= 3'd0;
        end
        else
        begin
            if(!hzoom_cnt_n)
            begin
                hzoom_acc <= hzoom_nextval[9:0];
                if(hzoom_nextval[10] == 1'b1)
                begin
                    hzoom_tileline_cntr <= hzoom_tileline_cntr + 3'd1;
                end
            end
        end
    end
end

reg             hline_complete;
wire            tileline0_complete = hzoom_nextval[10];
wire            tileline1_complete = &{hzoom_nextval[10], hzoom_tileline_cntr[0]};
wire            tileline3_complete = &{hzoom_nextval[10], hzoom_tileline_cntr[0], hzoom_tileline_cntr[1]};
wire            tileline7_complete = &{hzoom_nextval[10], hzoom_tileline_cntr[0], hzoom_tileline_cntr[1], hzoom_tileline_cntr[2]};

always @(*)
begin
    case({LATCH_A[5:3]})
        4'h0: hline_complete <= tileline3_complete;
        4'h1: hline_complete <= tileline1_complete;
        4'h2: hline_complete <= tileline3_complete;
        4'h3: hline_complete <= tileline7_complete;
        4'h4: hline_complete <= tileline0_complete;
        4'h5: hline_complete <= tileline1_complete;
        4'h6: hline_complete <= tileline0_complete;
        4'h7: hline_complete <= tileline1_complete;
    endcase
end

reg             vzoom_cnt_n;
reg             vzoom_rst_n;
reg     [9:0]   vzoom_acc = 10'd0;
wire    [10:0]  vzoom_nextval = vzoom_acc + {LATCH_A[7:6], LATCH_B};
reg     [3:0]   vzoom_vtile_cntr;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(!vzoom_rst_n)
        begin
            vzoom_acc <= 10'd0;
            vzoom_vtile_cntr <= 4'd0;
        end
        else
        begin
            if(!vzoom_cnt_n)
            begin
                vzoom_acc <= vzoom_nextval[9:0];
                if(vzoom_nextval[10] == 1'b1)
                begin
                    vzoom_vtile_cntr <= vzoom_vtile_cntr + 4'd1;
                end
            end
        end
    end
end

reg             vtile_complete_n;
wire            vtile0_complete_n  = ~vzoom_nextval[10];
wire            vtile1_complete_n  = ~&{vzoom_nextval[10], vzoom_vtile_cntr[0]};
wire            vtile3_complete_n  = ~&{vzoom_nextval[10], vzoom_vtile_cntr[0], vzoom_vtile_cntr[1]};
wire            vtile7_complete_n  = ~&{vzoom_nextval[10], vzoom_vtile_cntr[0], vzoom_vtile_cntr[1], vzoom_vtile_cntr[2]};
wire            vtile15_complete_n = ~&{vzoom_nextval[10], vzoom_vtile_cntr[0], vzoom_vtile_cntr[1], vzoom_vtile_cntr[2], vzoom_vtile_cntr[3]};

always @(*)
begin
    case({LATCH_A[1], LATCH_A[5:3]})
        4'h0: vtile_complete_n <= vtile3_complete_n;
        4'h1: vtile_complete_n <= vtile3_complete_n;
        4'h2: vtile_complete_n <= vtile1_complete_n;
        4'h3: vtile_complete_n <= vtile7_complete_n;
        4'h4: vtile_complete_n <= vtile0_complete_n;
        4'h5: vtile_complete_n <= vtile0_complete_n;
        4'h6: vtile_complete_n <= vtile1_complete_n;
        4'h7: vtile_complete_n <= vtile1_complete_n;
        4'h8: vtile_complete_n <= vtile7_complete_n;
        4'h9: vtile_complete_n <= vtile7_complete_n;
        4'hA: vtile_complete_n <= vtile3_complete_n;
        4'hB: vtile_complete_n <= vtile15_complete_n;
        4'hC: vtile_complete_n <= vtile1_complete_n;
        4'hD: vtile_complete_n <= vtile1_complete_n;
        4'hE: vtile_complete_n <= vtile3_complete_n;
        4'hF: vtile_complete_n <= vtile3_complete_n;
    endcase
end

reg             xpos_cnt_dly_n;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        xpos_cnt_dly_n <= ~o_WRTIME2;
    end
end

reg             ypos_cnt_n;
reg     [3:0]   ypos_cnt_dly_n;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        ypos_cnt_dly_n[0] <= ypos_cnt_n;
        ypos_cnt_dly_n[3:1] <= ypos_cnt_dly_n[2:0];
    end
end

reg     [7:0]   evenbuffer_xpos_counter;
reg     [7:0]   oddbuffer_xpos_counter;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(LATCH_F_en_n == 1'b0)
        begin
            evenbuffer_xpos_counter <= {LATCH_D[0], LATCH_E[7:1]} + LATCH_E[0];
            oddbuffer_xpos_counter <= {LATCH_D[0], LATCH_E[7:1]};
        end
        else if(ypos_cnt_dly_n[2] == 1'b0)
        begin
            evenbuffer_xpos_counter <= {LATCH_D[0], LATCH_E[7:1]} + LATCH_E[0];
            oddbuffer_xpos_counter <= {LATCH_D[0], LATCH_E[7:1]};
        end
        else
        begin
            if(xpos_cnt_dly_n == 1'b0)

            begin
                evenbuffer_xpos_counter <= evenbuffer_xpos_counter + 8'd1;
                oddbuffer_xpos_counter <= oddbuffer_xpos_counter + 8'd1;
            end
        end
    end
end

reg     [7:0]   buffer_ypos_counter;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(LATCH_F_en_n == 1'b0)
        begin
            buffer_ypos_counter <= i_OBJDATA;
        end
        else
        begin
            if(ypos_cnt_dly_n[3] == 1'b0)
            begin
                buffer_ypos_counter <= buffer_ypos_counter + 8'd1;
            end
        end
    end
end

wire            evenbuffer_xpos_d7 = evenbuffer_xpos_counter[7];

wire            x_offscreen = ~(~oddbuffer_xpos_counter[7] | oddbuffer_xpos_counter[6]);
wire            y_offscreen = (buffer_ypos_counter == 8'd255) ? 1'b1 : 1'b0;

wire            end_of_tileline = tileline0_complete | x_offscreen;
wire            end_of_hline = hline_complete | x_offscreen;

wire            end_of_last_hline_n = ~(~(vtile_complete_n) | y_offscreen);

wire    [2:0]   drawing_status = {end_of_last_hline_n, end_of_hline, end_of_tileline};

localparam KEEP_DRAWING     = 3'b100;
localparam END_OF_TILELINE  = 2'b01;
localparam END_OF_HLINE     = 3'b111;
localparam END_OF_SPRITE    = 3'b011;

reg     [1:0]   FSM_SUSPEND_DLY;
wire            FSM_SUSPEND = ((i_HBLANK_n & i_VBLANKH_n) | FSM_SUSPEND_DLY[1]) | ~DMA_4H_CLKD_n;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if({i_ABS_4H, i_ABS_2H, i_ABS_1H} == 3'd3)
        begin
            FSM_SUSPEND_DLY[0] <= (i_HBLANK_n & i_VBLANKH_n);
            FSM_SUSPEND_DLY[1] <= FSM_SUSPEND_DLY[0];
        end
    end
end

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(pixel3_n == 1'b0)
        begin
            o_CHAOV <= FSM_SUSPEND;
        end
    end
end

reg             LATCH_F_2H_NCLKD_en_n = 1'b1;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(pixel3_n == 1'b0)
        begin
            LATCH_F_2H_NCLKD_en_n <= LATCH_F_en_n;
        end
    end
end

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(hzoom_rst_n == 1'b0)
        begin
            hsize_parity <= 1'b1;
        end
        else
        begin
            if(hzoom_cnt_n == 1'b0)
            begin
                hsize_parity <= ~hsize_parity;
            end
        end
    end
end

localparam ATTR_LATCHING_S0 = 3'd1;
localparam ATTR_LATCHING_S1 = 3'd2;
localparam HCOUNT_S0 = 3'd3;
localparam HWAIT_S0 = 3'd4;
localparam ODDSIZE_S0 = 3'd5;
localparam XOFF_S0 = 3'd6;
localparam SUSPEND_S0 = 3'd0;

reg     [2:0]   sprite_engine_state = SUSPEND_S0;

always @ (posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        case(sprite_engine_state)

            ATTR_LATCHING_S0:
                sprite_engine_state <= ATTR_LATCHING_S1;

            ATTR_LATCHING_S1:
                if(pixel3_n == 1'b0)
                begin
                    if(new_vblank_n == 1'b0)
                    begin
                        sprite_engine_state <= ATTR_LATCHING_S0;
                    end
                    else
                    begin
                        if(LATCH_F_2H_NCLKD_en_n == 1'b0)
                        begin
                            if(FSM_SUSPEND == 1'b0)
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                            else
                            begin
                                sprite_engine_state <= SUSPEND_S0;
                            end
                        end
                        else
                        begin
                            sprite_engine_state <= ATTR_LATCHING_S1;
                        end
                    end
                end
                else
                begin
                    sprite_engine_state <= ATTR_LATCHING_S1;
                end

            HCOUNT_S0:
                if(drawing_status == END_OF_SPRITE)
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        if(new_vblank_n == 1'b0)
                        begin
                            sprite_engine_state <= ATTR_LATCHING_S0;
                        end
                        else
                        begin
                            if(FSM_SUSPEND == 1'b0)
                            begin
                                if(hsize_parity == 1'b0)
                                begin
                                    sprite_engine_state <= ATTR_LATCHING_S0;
                                end
                                else
                                begin
                                    sprite_engine_state <= ODDSIZE_S0;
                                end
                            end
                            else
                            begin
                                sprite_engine_state <= SUSPEND_S0;
                            end
                        end
                    end
                    else
                    begin
                        sprite_engine_state <= HWAIT_S0;
                    end
                end
                else if(drawing_status == END_OF_HLINE)
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        if(new_vblank_n == 1'b0)
                        begin
                            sprite_engine_state <= ATTR_LATCHING_S0;
                        end
                        else
                        begin
                            if(FSM_SUSPEND == 1'b0)
                            begin
                                if(hsize_parity == 1'b0)
                                begin
                                    if(evenbuffer_xpos_d7 == 1'b1)
                                    begin
                                        sprite_engine_state <= XOFF_S0;
                                    end
                                    else
                                    begin
                                        sprite_engine_state <= HCOUNT_S0;
                                    end
                                end
                                else
                                begin
                                    sprite_engine_state <= ODDSIZE_S0;
                                end
                            end
                            else
                            begin
                                sprite_engine_state <= SUSPEND_S0;
                            end
                        end
                    end
                    else
                    begin
                        sprite_engine_state <= HWAIT_S0;
                    end
                end
                else if(drawing_status[1:0] == END_OF_TILELINE)
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        if(new_vblank_n == 1'b0)
                        begin
                            sprite_engine_state <= ATTR_LATCHING_S0;
                        end
                        else
                        begin
                            if(FSM_SUSPEND == 1'b0)
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                            else
                            begin
                                sprite_engine_state <= SUSPEND_S0;
                            end
                        end
                    end
                    else
                    begin
                        sprite_engine_state <= HWAIT_S0;
                    end
                end
                else
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        if(new_vblank_n == 1'b0)
                        begin
                            sprite_engine_state <= ATTR_LATCHING_S0;
                        end
                        else
                        begin
                            if(FSM_SUSPEND == 1'b0)
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                            else
                            begin
                                sprite_engine_state <= SUSPEND_S0;
                            end
                        end
                    end
                    else
                    begin
                        sprite_engine_state <= HCOUNT_S0;
                    end
                end

            HWAIT_S0:
                if(pixel3_n == 1'b0)
                begin
                    if(new_vblank_n == 1'b0)
                    begin
                        sprite_engine_state <= ATTR_LATCHING_S0;
                    end
                    else
                    begin
                        if(FSM_SUSPEND == 1'b0)
                        begin
                            if(drawing_status == END_OF_SPRITE)
                            begin
                                if(hsize_parity == 1'b0)
                                begin
                                    sprite_engine_state <= ATTR_LATCHING_S0;
                                end
                                else
                                begin
                                    sprite_engine_state <= ODDSIZE_S0;
                                end
                            end
                            else if(drawing_status == END_OF_HLINE)
                            begin
                                if(hsize_parity == 1'b0)
                                begin
                                    if(evenbuffer_xpos_d7 == 1'b1)
                                    begin
                                        sprite_engine_state <= XOFF_S0;
                                    end
                                    else
                                    begin
                                        sprite_engine_state <= HCOUNT_S0;
                                    end
                                end
                                else
                                begin
                                    sprite_engine_state <= ODDSIZE_S0;
                                end
                            end
                            else
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                        end
                        else
                        begin
                            sprite_engine_state <= SUSPEND_S0;
                        end
                    end
                end
                else
                begin
                    sprite_engine_state <= HWAIT_S0;
                end

            ODDSIZE_S0:
                if(pixel3_n == 1'b0)
                begin
                    if(new_vblank_n == 1'b0)
                    begin
                        sprite_engine_state <= ATTR_LATCHING_S0;
                    end
                    else
                    begin
                        if(FSM_SUSPEND == 1'b0)
                        begin
                            if(drawing_status == END_OF_SPRITE)
                            begin
                                sprite_engine_state <= ATTR_LATCHING_S0;
                            end
                            else if(drawing_status == END_OF_HLINE)
                            begin
                                if(evenbuffer_xpos_d7 == 1'b1)
                                begin
                                    sprite_engine_state <= XOFF_S0;
                                end
                                else
                                begin
                                    sprite_engine_state <= HCOUNT_S0;
                                end
                            end
                            else
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                        end
                        else
                        begin
                            if(drawing_status == END_OF_SPRITE)
                            begin
                                sprite_engine_state <= ATTR_LATCHING_S0;
                            end
                            else
                            begin
                                sprite_engine_state <= SUSPEND_S0;
                            end
                        end
                    end
                end
                else
                begin
                    sprite_engine_state <= ODDSIZE_S0;
                end

            XOFF_S0:
                if(pixel3_n == 1'b0)
                begin
                    if(new_vblank_n == 1'b0)
                    begin
                        sprite_engine_state <= ATTR_LATCHING_S0;
                    end
                    else
                    begin
                        if(FSM_SUSPEND == 1'b0)
                        begin
                            if(drawing_status == END_OF_SPRITE)
                            begin
                                sprite_engine_state <= ATTR_LATCHING_S0;
                            end
                            else
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                        end
                        else
                        begin
                            sprite_engine_state <= XOFF_S0;
                        end
                    end
                end

            SUSPEND_S0:
                if(pixel3_n == 1'b0)
                begin
                    if(new_vblank_n == 1'b0)
                    begin
                        sprite_engine_state <= ATTR_LATCHING_S0;
                    end
                    else
                    begin
                        if(FSM_SUSPEND == 1'b0)
                        begin
                            if(drawing_status == END_OF_SPRITE)
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                            else if(drawing_status == END_OF_HLINE)
                            begin
                                if(hsize_parity == 1'b0)
                                begin
                                    if(evenbuffer_xpos_d7 == 1'b1)
                                    begin
                                        sprite_engine_state <= XOFF_S0;
                                    end
                                    else
                                    begin
                                        sprite_engine_state <= HCOUNT_S0;
                                    end
                                end
                                else
                                begin
                                    sprite_engine_state <= ODDSIZE_S0;
                                end
                            end
                            else
                            begin
                                sprite_engine_state <= HCOUNT_S0;
                            end
                        end
                        else
                        begin
                            sprite_engine_state <= SUSPEND_S0;
                        end
                    end
                end

            default:
                sprite_engine_state <= SUSPEND_S0;

        endcase
    end
end

always @(*) //Quartus
begin
    case(sprite_engine_state)
        ATTR_LATCHING_S0: begin
            latching_start <= 1'b1;

            hzoom_cnt_n <= 1'b1;
            hzoom_rst_n <= 1'b1;

            vzoom_cnt_n <= 1'b1;
            vzoom_rst_n <= 1'b1;

            ypos_cnt_n <= 1'b1;

            pixellatch_wait_n <= 1'b0;
        end
        ATTR_LATCHING_S1: begin
            if(LATCH_F_2H_NCLKD_en_n == 1'b0 && pixel3_n == 1'b0)
            begin
                latching_start <= 1'b0;

                hzoom_cnt_n <= 1'b1;
                hzoom_rst_n <= 1'b0;

                vzoom_cnt_n <= 1'b1;
                vzoom_rst_n <= 1'b0;

                ypos_cnt_n <= 1'b1;

                pixellatch_wait_n <= 1'b0;
            end
            else
            begin
                latching_start <= 1'b0;

                hzoom_cnt_n <= 1'b1;
                hzoom_rst_n <= 1'b1;

                vzoom_cnt_n <= 1'b1;
                vzoom_rst_n <= 1'b1;

                ypos_cnt_n <= 1'b1;

                pixellatch_wait_n <= 1'b0;
            end
        end

        HCOUNT_S0: begin

            latching_start <= 1'b0;

            if(drawing_status == END_OF_SPRITE)
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= ~hsize_parity;
                end
            end
            else if(drawing_status == END_OF_HLINE)
            begin
                if(hsize_parity == 1'b0)
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b0;

                        vzoom_cnt_n <= 1'b0;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b0;

                        pixellatch_wait_n <= 1'b1;
                    end
                    else
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= ~hsize_parity;
                    end
                end
                else
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b1;
                    end
                    else
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b0;
                    end
                end

            end
            else if(drawing_status[1:0] == END_OF_TILELINE)
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= ~hsize_parity;

                end
            end
            else
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
            end
        end

        HWAIT_S0: begin

            latching_start <= 1'b0;

            if(drawing_status == END_OF_SPRITE)
            begin
                if(hsize_parity == 1'b0)
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b1;
                    end
                    else
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b0;
                    end
                end
                else
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b1;
                    end
                    else
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b0;
                    end
                end
            end
            else if(drawing_status == END_OF_HLINE)
            begin
                if(hsize_parity == 1'b0)
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b0;

                        vzoom_cnt_n <= 1'b0;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b0;

                        pixellatch_wait_n <= 1'b1;
                    end
                    else
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b0;
                    end
                end
                else
                begin
                    if(pixel3_n == 1'b0)
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b1;
                    end
                    else
                    begin
                        hzoom_cnt_n <= 1'b1;
                        hzoom_rst_n <= 1'b1;

                        vzoom_cnt_n <= 1'b1;
                        vzoom_rst_n <= 1'b1;

                        ypos_cnt_n <= 1'b1;

                        pixellatch_wait_n <= 1'b0;
                    end
                end
            end
            else if(drawing_status[1:0] == END_OF_TILELINE)
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b0;
                end
            end
            else
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
            end
        end

        ODDSIZE_S0: begin

            latching_start <= 1'b0;

            if(drawing_status == END_OF_SPRITE)
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b0;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b0;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b0;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b0;
                end
            end
            else if(drawing_status == END_OF_HLINE)
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b0;

                    vzoom_cnt_n <= 1'b0;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b0;

                    pixellatch_wait_n <= 1'b0;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b0;
                end
            end
            else if(drawing_status[1:0] == END_OF_TILELINE)
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b0;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b0;
                end
            end
            else
            begin
                if(pixel3_n == 1'b0)
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b1;
                end
                else
                begin
                    hzoom_cnt_n <= 1'b1;
                    hzoom_rst_n <= 1'b1;

                    vzoom_cnt_n <= 1'b1;
                    vzoom_rst_n <= 1'b1;

                    ypos_cnt_n <= 1'b1;

                    pixellatch_wait_n <= 1'b0;
                end
            end
        end

        SUSPEND_S0: begin

            latching_start <= 1'b0;

            hzoom_cnt_n <= 1'b1;
            hzoom_rst_n <= 1'b1;

            vzoom_cnt_n <= 1'b1;
            vzoom_rst_n <= 1'b1;

            ypos_cnt_n <= 1'b1;

            pixellatch_wait_n <= 1'b0;
        end

        XOFF_S0: begin
            latching_start <= 1'b0;

            hzoom_cnt_n <= 1'b1;
            hzoom_rst_n <= 1'b1;

            vzoom_cnt_n <= 1'b1;
            vzoom_rst_n <= 1'b1;

            ypos_cnt_n <= 1'b1;

            pixellatch_wait_n <= 1'b0;
        end

        default: begin
            latching_start <= 1'b0;

            hzoom_cnt_n <= 1'b1;
            hzoom_rst_n <= 1'b1;

            vzoom_cnt_n <= 1'b1;
            vzoom_rst_n <= 1'b1;

            ypos_cnt_n <= 1'b1;

            pixellatch_wait_n <= 1'b0;
        end
    endcase
end

reg             wrtime1;
wire            oddsize_wrtime0 = (sprite_engine_state == ODDSIZE_S0 && pixel3_n == 1'b0) ? 1'b1 : 1'b0;
wire            evensize_wrtime0 = (sprite_engine_state == HCOUNT_S0) ? ~hsize_parity : 1'b0;
always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin

        wrtime1 <= evensize_wrtime0 | oddsize_wrtime0;
        o_WRTIME2 <= wrtime1;
    end
end

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        o_PIXELLATCH_WAIT_n <= pixellatch_wait_n;
    end
end

assign  o_PIXELSEL = hzoom_acc[9:7] ^ {3{LATCH_A[0]}};

wire    [2:0]   TILELINE_ADDR = hzoom_tileline_cntr ^ {3{LATCH_A[0]}};
wire    [2:0]   HLINE_ADDR = vzoom_acc[9:7] ^ {3{LATCH_D[5]}};
wire    [3:0]   VTILE_ADDR = vzoom_vtile_cntr ^ {4{LATCH_D[5]}};
reg     [13:0]  CHARRAM_ADDR;

`ifdef GX400_UNFOLD_DRAM_ADDR
    assign  o_OCA = CHARRAM_ADDR;
`else
    assign  o_OCA = (i_CHAMPX == 1'b0) ? CHARRAM_ADDR[7:0] : {1'b1, CHARRAM_ADDR[13:8], 1'b1};
`endif

always @(*)
begin
    case({LATCH_A[1], LATCH_A[5:3]})

        4'h0: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:3], VTILE_ADDR[1:0], HLINE_ADDR[2:0], TILELINE_ADDR[1:0]};
        4'h1: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:2], VTILE_ADDR[1:0], HLINE_ADDR[2:0], TILELINE_ADDR[0:0]};
        4'h2: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:2], VTILE_ADDR[0:0], HLINE_ADDR[2:0], TILELINE_ADDR[1:0]};
        4'h3: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:5], VTILE_ADDR[2:0], HLINE_ADDR[2:0], TILELINE_ADDR[2:0]};
        4'h4: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:0],            1'b0, HLINE_ADDR[2:0]                    };
        4'h5: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:0],                  HLINE_ADDR[2:0], TILELINE_ADDR[0:0]};
        4'h6: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:0], VTILE_ADDR[0:0], HLINE_ADDR[2:0]                    };
        4'h7: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:1], VTILE_ADDR[0:0], HLINE_ADDR[2:0], TILELINE_ADDR[0:0]};

        4'h8: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:4], VTILE_ADDR[2:0], HLINE_ADDR[2:0], TILELINE_ADDR[1:0]};
        4'h9: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:3], VTILE_ADDR[2:0], HLINE_ADDR[2:0], TILELINE_ADDR[0:0]};
        4'hA: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:4], VTILE_ADDR[1:0], HLINE_ADDR[2:0], TILELINE_ADDR[1:0]};
        4'hB: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:6], VTILE_ADDR[3:0], HLINE_ADDR[2:0], TILELINE_ADDR[2:0]};
        4'hC: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:0], VTILE_ADDR[0:0], HLINE_ADDR[2:0]                    };
        4'hD: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:1], VTILE_ADDR[0:0], HLINE_ADDR[2:0], TILELINE_ADDR[0:0]};
        4'hE: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:1], VTILE_ADDR[1:0], HLINE_ADDR[2:0]                    };
        4'hF: CHARRAM_ADDR <= {LATCH_D[7:6], LATCH_C[7:2], VTILE_ADDR[1:0], HLINE_ADDR[2:0], TILELINE_ADDR[0:0]};
    endcase
end

reg     [6:0]   buffer_x_screencounter = 7'd0;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        if(i_ABS_1H == 1'b1)
        begin
            if(i_OBJWR == 1'b1)
            begin
                buffer_x_screencounter <= 7'd0;
            end
            else
            begin
                if(buffer_x_screencounter == 7'd127)
                begin
                    buffer_x_screencounter <= 7'd0;
                end
                else
                begin
                    buffer_x_screencounter <= buffer_x_screencounter + 7'd1;
                end
            end
        end
    end
end

reg             prev_hblank;
reg     [7:0]   buffer_y_screencounter = 8'd15;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        prev_hblank <= i_HBLANK_n;

        if(i_VBLANK_n == 1'b0)
        begin
            buffer_y_screencounter <= 8'd15;

        end
        else
        begin
            if(i_HBLANK_n == 1'b1 && prev_hblank == 1'b0)
            begin
                if(buffer_y_screencounter == 8'd255)
                begin
                    buffer_y_screencounter <= 8'd0;
                end
                else
                begin
                    buffer_y_screencounter <= buffer_y_screencounter + 8'd1;
                end
            end
        end
    end
end

reg             buffer_frame_parity = 1'b0;
reg             prev_vblank;

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        prev_vblank <= i_VBLANK_n;

        if(i_VBLANK_n == 1'b0 && prev_vblank == 1'b1)
        begin
            buffer_frame_parity <= ~buffer_frame_parity;
        end
    end
end

reg     [15:0]  EVENBUFFER_ADDR;
reg     [15:0]  ODDBUFFER_ADDR;

`ifdef GX400_UNFOLD_DRAM_ADDR
    assign  o_FA = EVENBUFFER_ADDR;
    assign  o_FB = ODDBUFFER_ADDR;
`else
    assign  o_FA = (o_CAS == 1'b0) ? EVENBUFFER_ADDR[7:0] : EVENBUFFER_ADDR[15:8];
    assign  o_FB = (o_CAS == 1'b0) ?  ODDBUFFER_ADDR[7:0] :  ODDBUFFER_ADDR[15:8];
`endif

always @(*)
begin
    case(i_OBJWR)
        1'b1: begin
            EVENBUFFER_ADDR <= {~buffer_frame_parity, buffer_ypos_counter, evenbuffer_xpos_counter[6:0]};
            ODDBUFFER_ADDR  <= {~buffer_frame_parity, buffer_ypos_counter, oddbuffer_xpos_counter[6:0]};
        end
        1'b0: begin
            EVENBUFFER_ADDR <= {buffer_frame_parity, buffer_y_screencounter ^ {8{i_FLIP}}, buffer_x_screencounter ^ {7{i_FLIP}}};
            ODDBUFFER_ADDR  <= {buffer_frame_parity, buffer_y_screencounter ^ {8{i_FLIP}}, buffer_x_screencounter ^ {7{i_FLIP}}};
        end
    endcase
end

always @(posedge i_EMU_MCLK)
begin
    if(!i_EMU_CLK6MPCEN_n)
    begin
        o_XA7 <= evenbuffer_xpos_counter[7];
        o_XB7 <= oddbuffer_xpos_counter[7];
    end
end

assign  o_CAS = i_OBJHL;

reg debug;
always @(*)
begin
    if(oddbuffer_xpos_counter == 8'd124 && buffer_ypos_counter == 8'd218)
    begin
        debug <= 1'b1;
    end
    else
    begin
        debug <= 1'b0;
    end
end

endmodule
