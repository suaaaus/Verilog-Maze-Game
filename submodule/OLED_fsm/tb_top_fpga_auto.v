`timescale 1ns / 1ps

module tb_top_fpga_auto();

    localparam CLK_PERIOD = 10;
    reg  clk;
    reg  reset;
    wire LED_OLED_BUSY;
    wire LED_OLED_INIT_DONE;
    wire LED_WRITER_DONE;
    wire OLED_SCL;
    wire OLED_SDA; 
    wire i2c_ack_err, oled_err;

    // pullup 저항
    pullup(OLED_SDA);


    top_fpga_auto uut (
        .clk(clk),
        .reset(reset),
        .LED_OLED_BUSY(LED_OLED_BUSY),
        .LED_OLED_INIT_DONE(LED_OLED_INIT_DONE),
        .OLED_SCL(OLED_SCL),
        .OLED_SDA(OLED_SDA),
        .i2c_ack_err(i2c_ack_err), .oled_err(oled_err)
    );

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
    wire force_ack = (uut.u_oled_system.U_i2c_master.state    == 4'd7) && // i2c_master의 상태가 WAIT_ACK 일 때
                        // i2c_master가 sda를 샘플링하는 시점 (scl이 1일 때)
                      ((uut.u_oled_system.U_i2c_master.tick_cnt == 2'd2) || (uut.u_oled_system.U_i2c_master.tick_cnt == 2'd3));  

    // ACK를 받는 9번째 SCL에서만 ACK(0)
    // NACK를 받고싶으면 1하면 됨.
    assign OLED_SDA = force_ack ? 1'b0 : 1'bz;

endmodule