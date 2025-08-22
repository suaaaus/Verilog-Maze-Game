`timescale 1ns / 1ps

module tb_top_oled_map();

    localparam CLK_PERIOD = 10;
    reg   clk;
    reg   reset;
    wire  scl;
    wire  sda;

    // --- DUT Instantiation ---
    top_oled_map u_dut (
        .clk(clk),
        .reset(reset),
        .scl(scl),
        .sda(sda)
    );

    // pullup 저항
    pullup(sda);


    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin

        reset = 1;
        #(CLK_PERIOD * 2);
        reset = 0;

        #(20_000_000); 
        
        $finish;
    end
    
    // 무조건 ACK 성공하는 slave 시뮬레이션
    wire force_ack = (u_dut.U_i2c_master.state    == 4'd7) && // i2c_master의 상태가 WAIT_ACK 일 때
                        // i2c_master가 sda를 샘플링하는 시점 (scl이 1일 때)
                      ((u_dut.U_i2c_master.tick_cnt == 2'd2) || (u_dut.U_i2c_master.tick_cnt == 2'd3));  

    // ACK를 받는 9번째 SCL에서만 ACK(0)
    // NACK를 받고싶으면 1하면 됨.
    assign sda = force_ack ? 1'b0 : 1'bz;

endmodule