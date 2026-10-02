module jthotchase_ctrl(
    input             rst,
    input             clk,
    input             LVBL,
    input      [ 6:0] joystick1,
    input      [15:0] joyana_l1,
    input      [15:0] joyana_r1,
    input      [ 1:0] ctrl_type,
    input      [ 1:0] steer_mode,
    input      [ 1:0] ramp_spd,
    output     [ 7:0] steer,
    output     [ 7:0] accel,
    output            brake,
    output            shift,
    output            optical,
    output     [ 6:0] opt_cnt
);

wire [7:0] wheel;

ff_drivectrl #(
    .CENTER     ( 8'h80 ),
    .LIM        ( 8'h16 ),
    .ANA_MUL    ( 8'd24 ),
    .ANA_DZ     ( 8'd8  ),
    .STEP_UNIT  ( 8'd1  ),
    .OPT_UNIT   ( 8'd2  ),
    .OPT_MUL    ( 8'd40 ),
    .GAS_REST   ( 8'h00 ),
    .GAS_FULL   ( 8'h80 ),
    .GAS_DZ     ( 8'd8  ),
    .BRK_TH     ( 8'h40 ),
    .BOOT_FRAMES( 10'd0 )
) u_drive(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .LVBL       ( LVBL       ),
    .joystick1  ( joystick1  ),
    .joyana_l1  ( joyana_l1  ),
    .joyana_r1  ( joyana_r1  ),
    .ctrl_type  ( ctrl_type  ),
    .steer_mode ( steer_mode ),
    .ramp_spd   ( ramp_spd   ),
    .steer      ( wheel      ),
    .accel      ( accel      ),
    .brake      ( brake      ),
    .brk_mag    (            ),
    .shift      ( shift      ),
    .optical    ( optical    ),
    .opt_cnt    ( opt_cnt    )
);

assign steer = optical ? ( brake ? 8'hff : 8'h00 ) : wheel;

endmodule
