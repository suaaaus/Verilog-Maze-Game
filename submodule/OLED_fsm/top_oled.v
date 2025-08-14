module top_oled (clk, reset, oled_busy_o, oled_init_done_o, scl, sda, i2c_ack_err, oled_err);
    input          clk,reset;
    output         oled_busy_o;
    output         oled_init_done_o;
    output         scl;
    inout          sda;
    output i2c_ack_err, oled_err;

    // --- 내부 신호 선언 ---
    wire oled_req, oled_granted;
    wire start, stop, write;
    wire [7:0] data_in;
    wire i2c_busy, i2c_done, i2c_ack_err, oled_err;
    //wire [7:0] bram_rdata;
    wire tick;
    
    // bram_write_hello 모듈의 출력을 받을 와이어
    wire writer_bram_we;
    wire [9:0] writer_bram_addr;
    wire [7:0] writer_bram_wdata;

    //assign oled_granted = oled_req;

    // --- 모듈 인스턴스화 ---
    tick_generator #(.INPUT_FREQ(100_000_000), .TICK_HZ(400_000)) 
        u_tick_gen(.clk(clk), .reset(reset), .tick(tick));

    i2c_master U_i2c_master(
        .clk(clk), .reset(reset), .start(start), .stop(stop), 
        .write(write), .read(1'b0), .ack_in(1'b0), .tick(tick), 
        .data_in(data_in), .data_out(), .done(i2c_done), .busy(i2c_busy), 
        .ack_err(i2c_ack_err), .sda(sda), .scl(scl)
    );

    OLED_fsm u_oled_fsm(
        .clk(clk), .reset(reset), 
        .busy(i2c_busy), .done(i2c_done), .ack_err(i2c_ack_err), .oled_granted(1'b1),
        .oled_busy(oled_busy_o), .oled_init_done(oled_init_done_o),
        .oled_req(oled_req), .start(start), .stop(stop), .write(write), 
        .data_in(data_in), .oled_err(oled_err)
    );


    
endmodule
