module top_fpga_auto (clk, reset, LED_OLED_BUSY, LED_OLED_INIT_DONE, OLED_SCL, OLED_SDA, i2c_ack_err, oled_err);
    input          clk, reset;  
    output         LED_OLED_BUSY;
    output         LED_OLED_INIT_DONE;
    output         OLED_SCL;
    inout          OLED_SDA;
    output i2c_ack_err, oled_err;


    wire oled_init_done_sig;
    wire oled_busy_sig;

    top_oled u_oled_system (
        .clk(clk), 
        .reset(reset),
        .oled_busy_o(oled_busy_sig),
        .oled_init_done_o(oled_init_done_sig),
        .scl(OLED_SCL), 
        .sda(OLED_SDA),
        .i2c_ack_err(i2c_ack_err), .oled_err(oled_err)
    );

    assign LED_OLED_BUSY = oled_busy_sig;
    assign LED_OLED_INIT_DONE = oled_init_done_sig;

endmodule