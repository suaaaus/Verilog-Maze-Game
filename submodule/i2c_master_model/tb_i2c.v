// // restart 동작 수행 ( 한 트랜잭션에 1byte write -> 3byte read)
`timescale 1ns / 1ps
module tb_i2c();
    reg clk;
    reg reset;
    reg start, stop, write, read;
    reg [7:0] data_in;
    reg ack_in;
    wire sda;
    wire scl;
    wire done, busy, ack_err;
    wire [7:0] data_out;
    
    // --- I2C 슬레이브 시뮬레이션을 위한 신호 ---
    reg sda_slave_drive;
    reg sda_slave_out;

    // --- DUT (top_i2c) 인스턴스화 ---
    top_i2c dut (
        .clk(clk), .reset(reset),
        .start(start), .stop(stop), .write(write), .read(read),
        .data_in(data_in), .ack_in(ack_in),
        .sda(sda), .scl(scl),
        .done(done), .busy(busy), .ack_err(ack_err), .data_out(data_out)
    );
    
    // --- SDA 라인 모델링 ---
    pullup(sda);
    assign sda = sda_slave_drive ? sda_slave_out : 1'bz;
    
    // --- 슬레이브 동작을 위한 Event 선언 ---
    event e_slave_ack;
    event e_slave_send;
    reg do_ack_value;
    reg [7:0] send_data_value;

    // =================================================================
    // Helper Task 정의
    // =================================================================
    task wait_for_done;
        begin
            @(posedge done);
            @(posedge clk);
        end
    endtask

    task slave_respond_ack;
        input do_ack;
        begin
            repeat (8) @(posedge scl);
            @(negedge scl);
            sda_slave_drive = 1;
            sda_slave_out   = do_ack ? 1'b0 : 1'b1;
            @(posedge scl);
            @(negedge scl);
            sda_slave_drive = 0;
        end
    endtask

    task slave_send_data;
        input [7:0] slave_data;
        integer i;
        begin
            @(negedge scl);
            for (i = 7; i >= 0; i = i - 1) begin
                sda_slave_drive = 1;
                sda_slave_out   = slave_data[i];
                @(posedge scl);
                @(negedge scl);
            end
            sda_slave_drive = 0; 
        end
    endtask

    // =================================================================
    // 시뮬레이션 로직
    // =================================================================
    
    // --- 클럭 생성 (100MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // --- Event 감지 always 블록 ---
    always @(e_slave_ack)
        slave_respond_ack(do_ack_value);

    always @(e_slave_send)
        slave_send_data(send_data_value);

    // --- 테스트 시나리오 ---
    initial begin
        $dumpfile("tb_i2c.vcd");
        $dumpvars(0, tb_i2c);
        
        reset = 1;
        start = 0; stop = 0; write = 0; read = 0;
        ack_in = 0;
        data_in = 8'h00;
        sda_slave_drive = 0;
        
        #100;
        reset = 0;
        #2000;
        
        $display("=== I2C Write -> Repeated START -> Multi-Byte Read Test ===");
        
        // 1. START & WRITE (예: EEPROM에 읽을 주소 0xA0 전송)
        $display("\n1. Writing target address 0xA0...");
        start = 1;
        write = 1;
        data_in = 8'hA0;
        wait(busy == 1);
        @(posedge clk);
        start = 0;
        write = 0;

        do_ack_value = 1; // 슬레이브가 ACK 응답
        -> e_slave_ack;
        wait_for_done();
        $display("   -> Address Sent.");

        #100; // 안정적인 REPEATED START를 위한 지연

        // 2. REPEATED START & READ 1번째 바이트
        $display("\n2. Sending Repeated START, Reading 1st Byte...");
        start = 1;
        read = 1;
        ack_in = 0; // "계속"을 의미하는 ACK
        wait(dut.U_i2c_master.state == 1); // START_1 상태
        @(posedge clk);
        start = 0;
        read = 0;

        send_data_value = 8'h11;
        -> e_slave_send;
        wait_for_done();
        $display("   -> 1st Byte Read: 0x%02X", data_out);

        // 3. READ 2번째 바이트
        $display("\n3. Reading 2nd Byte...");
        read = 1;
        ack_in = 0; // "계속"을 의미하는 ACK
        @(posedge clk);
        read = 0;

        send_data_value = 8'h22;
        -> e_slave_send;
        wait_for_done();
        $display("   -> 2nd Byte Read: 0x%02X", data_out);

        // 4. READ 3번째 바이트
        $display("\n4. Reading 3rd (Final) Byte...");
        read = 1;
        ack_in = 1; // "마지막"을 의미하는 NACK
        @(posedge clk);
        read = 0;

        send_data_value = 8'h33;
        -> e_slave_send;
        wait_for_done();
        $display("   -> 3rd Byte Read: 0x%02X", data_out);

        // 5. STOP
        $display("\n5. Sending STOP condition...");
        stop = 1;
        wait_for_done();
        stop = 0;
        
        if (!busy) $display("   -> Transaction complete. PASSED.");
        else       $display("   -> Bus is still busy. FAILED.");
        #2000;
        
        $display("\n=== All Tests Completed ===");
        #10000;
        $finish;
    end

endmodule