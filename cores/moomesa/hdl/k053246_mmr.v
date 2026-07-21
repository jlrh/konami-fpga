/* =============================================================================================
    k053246_mmr.v — FORK PROPIO del motor de sprites (K053246/K053247) de COWBOYS (Moo Mesa).
    Origen: cores/simson/hdl/jt053246_mmr.v  (arbol jtcores, COMPARTIDO con simson/xmen/rungun...).
    Clonado 2026-07-20 (sesion 24). NO es una copia muerta: desde aqui EVOLUCIONA POR SU CUENTA.

    -- POR QUE SE CLONO ------------------------------------------------------------------------
    El modulo compartido PIERDE SPRITES al ratio de reloj real de la placa. Sintoma reportado y
    fotografiado en HW (fase 2, vagon del tren): al personaje le faltan torso y cabeza y los
    enemigos salen cortados, en las lineas donde se amontonan sprites.
    Capturas: debug/cowboys/raw/hw_snaps/20260720_085314/15/16-screen.png

    CAUSA RAIZ (medida): el FSM que recorre la tabla de objetos avanza a **clk/2**
    (original jt053246_scan.sv:95-96 `always @(negedge clk) cen2 <= ~cen2;` + `else if(cen2)`),
    luego los objetos procesables por linea escalan con el ratio de reloj:
       CLKDIV=8 (simulacion) -> 4096 clk/linea -> 2048 pasos -> alcanza el objeto ~0xd3..0xff
       CLKDIV=6 (PLACA REAL) -> 3072 clk/linea -> 1536 pasos -> se queda en el 0x4b (75 de 256)
    Los objetos no alcanzados NO SE DIBUJAN.

    MEDIDO en la escena 14198 (87 sprites, volcada del juego real por el usuario):
       CLKDIV=6  -> 128 de 224 lineas sin terminar -> sim==golden 7.57 %
       CLKDIV=8  ->  28 lineas sin terminar        -> 2.30 %
       CLKDIV=12 ->   0 lineas sin terminar        -> 2.30 %  (suelo = residuo ajeno)
    => es PURO presupuesto de tiempo, no un fallo funcional. La metrica ya existia en el RTL
       ($display "Obj scan did not finish" / "%d uncompleted lines"); nadie la miraba porque al
       ratio 8 de simulacion casi no salta.

    -- POR QUE NO SE ARREGLO EN EL COMPARTIDO --------------------------------------------------
    cores/simson/hdl lo usan otros cores y otros agentes: la regla del proyecto es NO TOCARLO.
    Y el fix puede no ser universal: cada placa Konami monta CUSTOMS DISTINTOS que pueden
    comportarse de otra manera. Se aprende de lo que hay y se vuela libre. Si el hallazgo sirve a
    otros, va por el _inbox del comun -- nunca editando su codigo.

    -- AVISOS ----------------------------------------------------------------------------------
    (1) TRAMPA DE NOMBRES (bug de harness de la ses.19): verilator y quartus resuelven modulos por
        NOMBRE, y el orden `-y` pone simson/hdl ANTES que cowboys/hdl. Un clon con el MISMO nombre
        quedaria SOMBREADO por el original y estarias probando codigo ajeno sin enterarte.
        POR ESO SE RENOMBRO TODO EL ARBOL: jtsimson_obj->cowboys_obj, jt053246*->k053246*.
        NO le devuelvas a ninguno su nombre original.
    (2) El HW ORIGINAL **NO** pierde esos sprites (verificado por el usuario en placa real) => es
        un defecto NUESTRO, no fidelidad. No lo "restaures" creyendo que el juego era asi.
    (3) Estos ficheros .sv/.v deben COPIARSE AL ARBOL jtcores por scripts/_cowboys_sync.sh. Si el
        sync solo copia *.v, los *.sv NO llegan y simularias/sintetizarias la version vieja.
   ============================================================================================= */
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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 5-2-2024 */

module k053246_mmr(
    input             rst,
    input             clk,

    input             k44_en,   // enable k053244/5 mode (default k053246/7)
    // CPU interface - 8 bits!
    input             cs,
    input             cpu_we,
    input      [ 3:0] cpu_addr, // bit 3 only in k44 mode
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,  // used in 16-bit mode

    output reg [ 7:0] cfg,
    output reg [ 9:0] xoffset,
    output reg [ 9:0] yoffset,
    output reg [22:1] rmrd_addr, // This might be set by 53247/55673 and not 53246
    // 53247 (X-Men) would be [21:1] whereas 55673 (Run&Gun) is [22:1]

    input      [ 7:0] st_addr,
    output reg [ 7:0] st_dout
);

`ifdef SIMULATION
reg [7:0] mmr_init[0:7];
integer f,fcnt=0;

initial begin
    f=$fopen("obj_mmr.bin","rb");
    if( f!=0 ) begin
        fcnt=$fread(mmr_init,f);
        $fclose(f);
        $display("Read %1d bytes for 053246 MMR", fcnt);
        mmr_init[5][4] = 1; // enable DMA, which will be low if the game was paused for the dump
        $display("xoffset=%X",{ mmr_init[1][1:0], mmr_init[0] });
        $display("yoffset=%X",{ mmr_init[3][1:0], mmr_init[2] });
    end
end
`endif

wire mode8 = cfg[2]; // guess, use it for 8-bit access on 46/47 pair

// Register map
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        xoffset <= 0; yoffset <= 0; cfg <= 0;
`ifdef SIMULATION
        if( fcnt!=0 ) begin
            xoffset <= { mmr_init[1][1:0], mmr_init[0] };
            yoffset <= { mmr_init[3][1:0], mmr_init[2] };
            cfg     <= mmr_init[5];
        end
`endif
        st_dout <= 0;
    end else begin
        if( cs && cpu_we ) begin
            if( mode8 || k44_en ) case( {cpu_addr[3] & k44_en, cpu_addr[2:0]} )
                0: xoffset[9:8] <= cpu_dout[1:0];
                1: xoffset[7:0] <= cpu_dout[7:0];
                2: yoffset[9:8] <= cpu_dout[1:0];
                3: yoffset[7:0] <= cpu_dout[7:0];
                4: if(!k44_en) rmrd_addr[ 8: 1] <= cpu_dout[7:0];
                5: begin
                    cfg <= cpu_dout[7:0]; // $34 (simpsons/vendetta) $30/20 (xmen)
                end
                6: if(!k44_en) rmrd_addr[22:17] <= {1'b0,cpu_dout[4:0]};
                7: if(!k44_en) rmrd_addr[16: 9] <= cpu_dout[7:0];
                // k44_en only
                8:  rmrd_addr[16: 9] <= cpu_dout[7:0];
                9:  rmrd_addr[ 8: 1] <= cpu_dout[7:0];
                11: rmrd_addr[22:17] <={1'b0,cpu_dout[4:0]};
            endcase else case( cpu_addr[2:1] ) // 16-bit access
                0: begin
                    if( !cpu_dsn[1] ) xoffset[9:8] <= cpu_dout[9:8];
                    if( !cpu_dsn[0] ) xoffset[7:0] <= cpu_dout[7:0];
                end
                1: begin
                    if( !cpu_dsn[1] ) yoffset[9:8] <= cpu_dout[9:8];
                    if( !cpu_dsn[0] ) yoffset[7:0] <= cpu_dout[7:0];
                end
                2: begin
                    if( !cpu_dsn[1] ) rmrd_addr[8:1] <= cpu_dout[15:8];
                    if( !cpu_dsn[0] ) begin
                        cfg <= cpu_dout[7:0];
                    end
                end
                3: begin
                    if( !cpu_dsn[1] ) rmrd_addr[22:17] <= cpu_dout[13:8];
                    if( !cpu_dsn[0] ) rmrd_addr[16: 9] <= cpu_dout[ 7:0];
                end
            endcase
        end
        case( st_addr[2:0] )
            0: st_dout <= xoffset[7:0];
            1: st_dout <= {6'd0,xoffset[9:8]};
            2: st_dout <= yoffset[7:0];
            3: st_dout <= {6'd0,yoffset[9:8]};
            5: st_dout <= cfg;
            default: st_dout <= 0;
        endcase
    end
end

endmodule