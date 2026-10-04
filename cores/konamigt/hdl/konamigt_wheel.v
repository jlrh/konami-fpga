module konamigt_wheel #(
    parameter [7:0] LIM     = 8'd52,
    parameter [6:0] MAXD    = 7'd10
)(
    input             rst,
    input             clk,
    input             LVBL,
    input      [ 6:0] joystick1,
    input      [15:0] joyana_l1,
    input      [15:0] joyana_r1,
    input      [ 1:0] dial,
    input             spin_en,
    input      [ 1:0] ctrl_type,
    input      [ 1:0] steer_mode,
    input      [ 1:0] ramp_spd,
    output     [15:0] wheel_word,
    output            shift
);

wire [7:0] steer, accel, brk_mag;
wire [6:0] opt_cnt;
wire       brake, optical;

ff_drivectrl #(
    .CENTER     ( 8'h80 ),
    .LIM        ( LIM   ),
    .ANA_MUL    ( 8'd58 ),
    .ANA_DZ     ( 8'd8  ),
    .STEP_UNIT  ( 8'd2  ),
    .OPT_UNIT   ( 8'd2  ),
    .OPT_MUL    ( 8'd48 ),
    .GAS_REST   ( 8'h00 ),
    .GAS_FULL   ( 8'h80 ),
    .GAS_DZ     ( 8'd16 ),
    .BRK_TH     ( 8'd72 ),
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
    .steer      ( steer      ),
    .accel      ( accel      ),
    .brake      ( brake      ),
    .brk_mag    ( brk_mag    ),
    .shift      ( shift      ),
    .optical    ( optical    ),
    .opt_cnt    ( opt_cnt    )
);

reg  [1:0] dial_l;
wire dial_up = (dial_l==2'b00 && dial==2'b01) || (dial_l==2'b01 && dial==2'b11) ||
               (dial_l==2'b11 && dial==2'b10) || (dial_l==2'b10 && dial==2'b00);
wire dial_dn = (dial_l==2'b00 && dial==2'b10) || (dial_l==2'b10 && dial==2'b11) ||
               (dial_l==2'b11 && dial==2'b01) || (dial_l==2'b01 && dial==2'b00);

reg        LVBLl, upd;
reg  [6:0] cnt, opt_l;
reg        dir_dn;
reg  signed [7:0] spin_d;
reg  signed [7:0] pos_l;
reg  signed [9:0] acc;

wire signed [8:0] pos_r = $signed({1'b0, steer}) - 9'sd128;
wire signed [8:0] slim  = $signed({1'b0, LIM});
wire signed [7:0] pos   = pos_r > slim ? slim[7:0] : pos_r < -slim ? -slim[7:0] : pos_r[7:0];
wire        [6:0] dopt  = opt_l - opt_cnt;
wire signed [9:0] d_in  = ( optical ? {{3{dopt[6]}}, dopt} : $signed({{2{pos[7]}}, pos}) - $signed({{2{pos_l[7]}}, pos_l}) )
                        + $signed({{2{spin_d[7]}}, spin_d});
wire signed [9:0] acc_n = acc + d_in;
wire signed [9:0] smax  = $signed({3'd0, MAXD});
wire signed [9:0] emit  = acc_n > smax ? smax : acc_n < -smax ? -smax : acc_n;
wire signed [9:0] rest  = acc_n - emit;

reg  [3:0] gas;
reg  [1:0] brk;

always @* begin
    if( accel > 8'd104 )      gas = 4'b1111;
    else if( accel > 8'd72 )  gas = 4'b0111;
    else if( accel > 8'd40 )  gas = 4'b0011;
    else if( accel > 8'd16 )  gas = 4'b0001;
    else                      gas = 4'b0000;
    if( brake )               brk = 2'b11;
    else if( brk_mag > 8'd24 )brk = 2'b01;
    else                      brk = 2'b00;
end

assign wheel_word = { gas, 2'b00, brk, dir_dn, cnt };

always @(posedge clk) begin
    LVBLl  <= LVBL;
    upd    <= LVBLl && !LVBL;
    dial_l <= dial;
    if( rst ) begin
        cnt    <= 7'd0;
        dir_dn <= 1'b0;
        acc    <= 10'sd0;
        spin_d <= 8'sd0;
        pos_l  <= pos;
        opt_l  <= opt_cnt;
    end else begin
        if( spin_en && dial_up && spin_d !=  8'sd10 ) spin_d <= spin_d + 8'sd1;
        if( spin_en && dial_dn && spin_d != -8'sd10 ) spin_d <= spin_d - 8'sd1;
        if( upd ) begin
            spin_d <= 8'sd0;
            pos_l  <= pos;
            opt_l  <= opt_cnt;
            acc    <= rest > 10'sd127 ? 10'sd127 : rest < -10'sd127 ? -10'sd127 : rest;
            if( emit != 10'sd0 ) begin
                cnt    <= cnt + emit[6:0];
                dir_dn <= emit[9];
            end
        end
    end
end

endmodule
