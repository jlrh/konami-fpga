/*  ssriders — K053244/K053245 sprite table scanner.
    Free software under the GNU General Public License v3.
    2026 Jose Luis Rodriguez.  */

module k053244_scan(
    input             rst,
    input             clk,

    output reg [15:0] code,
    output reg [ 6:0] attr,
    output            hflip,
    output reg        vflip,
    output reg [ 9:0] hpos,
    output     [ 3:0] ysub,
    output reg [11:0] hzoom,
    output reg        hz_keep,

    input      [ 8:0] hdump,
    input      [ 8:0] vdump,
    input             hs,

    input      [15:0] scan_even,
    input      [15:0] scan_odd,
    output     [11:2] scan_addr,

    input      [ 9:0] xoffset,
    input      [ 9:0] yoffset,
    input             ghf, gvf,

    output reg        shd,

    output reg        dr_start,
    input             dr_busy,

    input      [ 7:0] debug_bus
);

parameter HFLIP_OFFSET = 0;

localparam [2:0] ST_CTRL=3'd0, ST_POS=3'd1, ST_ZOOM=3'd2, ST_ATTR=3'd3,
                 ST_ROW =3'd4, ST_DRAW=3'd5;

reg  [ 2:0] step;
reg  [ 6:0] scan_obj;
reg         done;

reg  [18:0] rowmul;
reg  [11:0] vzoom;
reg  [ 9:0] y, y2, x, ydist, srow, xadj, yadj;
reg  [ 8:0] vline, vhalf, vscl, hscl;
reg  [ 3:0] size;
reg  [ 2:0] hstep, hcode, hsum, vsum;
reg  [ 1:0] mirror;
reg  [ 6:0] pri;
reg         inzone, hs_l, hdone, sq, pre_vf, pre_hf, hhalf,
            vmir_eff, hmir_eff;

reg  [ 8:0] zrecip[0:255];
reg  [ 3:0] zbin  [0:15 ];

wire [ 1:0] hsz = size[1:0];
wire [ 1:0] vsz = size[3:2];
wire        hmir = mirror[0];

wire [ 1:0] nx_mir = scan_even[9:8];
wire [ 9:0] hflip_off = ghf ? HFLIP_OFFSET[9:0] : 10'd0;
wire        last_obj  = &scan_obj;

assign hflip     = (ghf ^ pre_hf) & ~hmir | hmir_eff;
assign scan_addr = { scan_obj, step[1:0] };
assign ysub      = srow[3:0];

function [8:0] zoom_step( input [11:0] z );
    case( z[11:8] )
        4'd0:    zoom_step = zrecip[z[7:0]];
        4'd1:    zoom_step = { 5'd0, zbin[z[7:4]] };
        4'd2:    zoom_step = 9'd3;
        4'd3,
        4'd4:    zoom_step = 9'd2;
        default: zoom_step = 9'd1;
    endcase
endfunction

function [8:0] half_extent( input [1:0] sz, input [8:0] scl );
    case( sz )
        2'd0: half_extent = scl>>2;
        2'd1: half_extent = scl>>1;
        2'd2: half_extent = scl;
        2'd3: half_extent = scl<<1;
    endcase
endfunction

(* direct_enable *) reg cen2=0;
always @(negedge clk) cen2 <= ~cen2;

always @(posedge clk) begin

    xadj   <= xoffset + 10'h66 + hflip_off;
    yadj   <= yoffset + 10'h107;
    hscl   <= zoom_step( hzoom );
    /* verilator lint_off WIDTH */
    rowmul <= vzoom[9:0] * ydist;
    /* verilator lint_on WIDTH */
end

always @* begin

    vhalf = half_extent( vsz, vscl );
    y2    = y + { 1'b0, vhalf };
    ydist = y2 + { vline[8], vline };
    srow  = rowmul[6+:10];

    case( vsz )
        2'd0: vmir_eff = nx_mir[1] && !srow[3] && srow[9:4]==0;
        2'd1: vmir_eff = nx_mir[1] && !srow[4] && srow[9:5]==0;
        2'd2: vmir_eff = nx_mir[1] && !srow[5] && srow[9:6]==0;
        2'd3: vmir_eff = nx_mir[1] && !srow[6] && srow[9:7]==0;
    endcase
    hmir_eff = hmir & hhalf;

    case( vsz )
        2'd0: inzone = ydist[9]==srow[9] && srow[9:4]==0;
        2'd1: inzone = ydist[9]==srow[9] && srow[9:5]==0;
        2'd2: inzone = ydist[9]==srow[9] && srow[9:6]==0;
        2'd3: inzone = ydist[9]==srow[9] && srow[9:7]==0;
    endcase
    if( rowmul[16] ) inzone = 0;

    case( hsz )
        2'd0: hdone = 1'b1;
        2'd1: hdone = hstep==3'd1;
        2'd2: hdone = hstep==3'd3;
        2'd3: hdone = hstep==3'd7;
    endcase
    case( hsz )
        2'd0: hsum = 3'd0;
        2'd1: hsum = hmir ? 3'd0                        : { 2'd0, hstep[0]^hflip };
        2'd2: hsum = hmir ? { 2'd0, hstep[0]^hflip }    : { 1'd0, hstep[1:0]^{2{hflip}} };
        2'd3: hsum = hmir ? { 1'd0, hstep[1:0]^{2{hflip}} } : hstep[2:0]^{3{hflip}};
    endcase
    case( vsz )
        2'd0: vsum = 3'd0;
        2'd1: vsum = { 2'd0, srow[4]^vflip };
        2'd2: vsum = { 1'd0, srow[5:4]^{2{vflip}} };
        2'd3: vsum = srow[6:4]^{3{vflip}};
    endcase
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        hs_l <= 0; scan_obj <= 0; step <= ST_CTRL; hstep <= 0;
        code <= 0; attr <= 0; pre_vf <= 0; pre_hf <= 0; vflip <= 0;
        vzoom <= 0; hzoom <= 0; hz_keep <= 0; hhalf <= 0; shd <= 0;
        done <= 0; dr_start <= 0;
    end else if( cen2 ) begin
        hs_l     <= hs;
        dr_start <= 0;

        if( hs && !hs_l && vdump>9'h10D && vdump<9'h1F1 ) begin
            done     <= 0;
            scan_obj <= 0;
            step     <= ST_CTRL;
            vline    <= vdump;
        end else if( !done ) begin
            step <= step + 3'd1;
            case( step )
                ST_CTRL: begin
                    hhalf   <= 0;
                    hstep   <= 0;
                    hz_keep <= 0;
                    { sq, pre_vf, pre_hf, size } <= scan_even[14:8];
                    code <= { 1'b0, scan_odd[14:0] };
                    pri  <= scan_even[6:0];

                    if( !scan_even[15] ) begin
                        step     <= ST_CTRL;
                        scan_obj <= scan_obj + 7'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                ST_POS: begin
                    y     <= gvf ? -scan_even[9:0] : scan_even[9:0];
                    x     <= ghf ? -scan_odd [9:0] : scan_odd [9:0];
                    hcode <= { code[4], code[2], code[0] };
                    hstep <= 0;
                end
                ST_ZOOM: begin
                    x     <= x + xadj;
                    y     <= y + yadj;
                    vzoom <= scan_even[11:0];

                    hzoom <= sq ? scan_even[11:0] : scan_odd[11:0];
                    vscl  <= zoom_step( scan_even[11:0] );
                end
                ST_ATTR: begin
                    mirror      <= scan_even[9:8];
                    { shd, attr } <= scan_even[7:0];
                    vflip       <= pre_vf ^ gvf ^ vmir_eff;
                end
                ST_ROW: begin

                    { code[5], code[3], code[1] } <= { code[5], code[3], code[1] } + vsum;
                    if( !inzone ) begin
                        step     <= ST_CTRL;
                        scan_obj <= scan_obj + 7'd1;
                        if( last_obj ) done <= 1;
                    end
                end
                default: begin
                    case( hsz )
                        2'd1: if( hstep>=3'd1 ) hhalf <= 1;
                        2'd2: if( hstep>=3'd2 ) hhalf <= 1;
                        2'd3: if( hstep>=3'd4 ) hhalf <= 1;
                    endcase
                    step <= ST_DRAW;
                    if( (!dr_start && !dr_busy) || !inzone ) begin
                        { code[4], code[2], code[0] } <= hcode + hsum;
                        if( hstep==0 ) begin
                            hpos <= x - half_extent( hsz, hscl );
                        end else begin
                            hpos    <= hpos + 10'h10;
                            hz_keep <= 1;
                        end
                        hstep    <= hstep + 3'd1;
                        dr_start <= inzone;
                        if( hdone || !inzone ) begin
                            step     <= ST_CTRL;
                            scan_obj <= scan_obj + 7'd1;
                            if( last_obj ) done <= 1;
                        end
                    end
                end
            endcase
        end
    end
end

integer zi;
initial begin : init_zrecip

    for( zi=0; zi<256; zi=zi+1 )
        zrecip[zi] = zi<5 ? 9'd511 : ((2048+zi/2)/zi > 511 ? 9'd511 : (2048+zi/2)/zi);
end

initial begin : init_zbin
    zbin[ 0]=8; zbin[ 1]=7; zbin[ 2]=7; zbin[ 3]=6; zbin[ 4]=6; zbin[ 5]=6; zbin[ 6]=6; zbin[ 7]=5;
    zbin[ 8]=5; zbin[ 9]=5; zbin[10]=5; zbin[11]=5; zbin[12]=4; zbin[13]=4; zbin[14]=4; zbin[15]=4;
end

endmodule
