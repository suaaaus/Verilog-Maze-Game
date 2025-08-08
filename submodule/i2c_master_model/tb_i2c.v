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
    wire sda_slave_drive; // 슬레이브가 SDA를 구동할지 여부 (Master의 out_sda_en 반전)
    reg  sda_slave_out;   // 슬레이브가 내보낼 실제 값 (0 또는 1)
    
    // 슬레이브가 READ 명령에 응답하여 보낼 데이터를 저장하는 레지스터
    reg [7:0] slave_tx_data; 
    
    // --- DUT (top_i2c) 인스턴스화 ---
    top_i2c dut (
        .clk(clk), .reset(reset),
        .start(start), .stop(stop), .write(write), .read(read),
        .data_in(data_in), .ack_in(ack_in),
        .sda(sda), .scl(scl),
        .done(done), .busy(busy), .ack_err(ack_err), .data_out(data_out)
    );

    // --- SDA 라인 모델링 ---
    // 1. Master의 sda enable 신호가 꺼져있을 때 (Master가 sda를 high-z로 만들 때) 슬레이브가 SDA를 구동한다.
    assign sda_slave_drive = ~dut.U_i2c_master.out_sda_en;
    
    // 2. pull-up 저항 모델링 및 최종 sda 신호 결정
    pullup(sda);
    assign sda = sda_slave_drive ? sda_slave_out : 1'bz;

    // =================================================================
    // Helper Task 정의
    // =================================================================
    task wait_for_done;
        begin
            @(posedge done);
            @(posedge clk);
        end
    endtask

    // =================================================================
    // 슬레이브 로직 (하나의 always 블록으로 통합)
    // =================================================================
    // 이 블록은 슬레이브가 SDA 라인을 구동할 때 (sda_slave_drive == 1)
    // 어떤 값을 내보낼지 결정하는 유일한 로직입니다.
    always @(*) begin
        // 마스터가 데이터를 읽어가는 상태(READ_DATA)일 때
        if (dut.U_i2c_master.state == 4'd4) begin
            // 마스터가 현재 몇 번째 비트를 읽고 있는지(dut.bit_cnt)에 따라
            // 슬레이브가 전송할 데이터(slave_tx_data)의 해당 비트를 내보낸다.
            sda_slave_out = slave_tx_data[7 - dut.U_i2c_master.bit_cnt];
        end
        // 마스터가 ACK를 기다리는 상태(WAIT_ACK)일 때 (WRITE 또는 주소 전송 후)
        else if (dut.U_i2c_master.state == 4'd5) begin
            // ACK(0)를 보낸다.
            sda_slave_out = 1'b0;
        end
        // 그 외의 모든 경우
        else begin
            // 안전하게 1을 출력 (SDA 라인을 놓아주는 효과)
            sda_slave_out = 1'b1;
        end
    end

    // =================================================================
    // 시뮬레이션 로직
    // =================================================================
    
    // --- 클럭 생성 (100MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // --- 테스트 시나리오 ---
    initial begin
        $dumpfile("tb_i2c.vcd");
        $dumpvars(0, tb_i2c);
        
        reset = 1;
        start = 0; stop = 0; write = 0; read = 0;
        ack_in = 0;
        data_in = 8'h00;
        slave_tx_data = 8'h00;
        
        #100;
        reset = 0;
        #2000;
        
        $display("=== I2C 2-Write -> RS -> 3-Read Test (Reactive Slave) ===");
        
        // 1. START & WRITE 1번째 바이트 (주소)
        $display("\n1. Writing 1st byte (Address 0xA0)...");
        start = 1;
        write = 1;
        data_in = 8'hA0;
        wait(busy == 1);
        @(posedge clk);
        start = 0;
        write = 0;
        wait_for_done(); // 슬레이브가 자동으로 ACK를 보낼 것임
        $display("   -> 1st Byte Sent, Auto-ACK received.");

        // 2. WRITE 2번째 바이트 (데이터)
        $display("\n2. Writing 2nd byte (Data 0xAA)...");
        write = 1;
        data_in = 8'hAA;
        @(posedge clk);
        write = 0;
        wait_for_done(); // 슬레이브가 자동으로 ACK를 보낼 것임
        $display("   -> 2nd Byte Sent, Auto-ACK received.");
        
        #100; // 안정적인 REPEATED START를 위한 지연

        // 3. REPEATED START & READ 1번째 바이트
        $display("\n3. Sending RS, Reading 1st Byte...");
        slave_tx_data = 8'h11; // 슬레이브가 보낼 데이터 준비
        start = 1;
        read = 1;
        ack_in = 0; // "계속 읽을 것"을 의미하는 ACK
        wait(dut.U_i2c_master.state == 1);
        @(posedge clk);
        start = 0;
        read = 0;
        wait_for_done();
        $display("   -> 1st Byte Read: 0x%02X", data_out);

        // 4. READ 2번째 바이트
        $display("\n4. Reading 2nd Byte...");
        slave_tx_data = 8'h22; // 슬레이브가 보낼 데이터 준비
        read = 1;
        ack_in = 0; // "계속" (ACK)
        @(posedge clk);
        read = 0;
        wait_for_done();
        $display("   -> 2nd Byte Read: 0x%02X", data_out);

        // 5. READ 3번째 바이트
        $display("\n5. Reading 3rd (Final) Byte...");
        slave_tx_data = 8'h33; // 슬레이브가 보낼 데이터 준비
        read = 1;
        ack_in = 1; // "마지막" (NACK)
        @(posedge clk);
        read = 0;
        wait_for_done();
        $display("   -> 3rd Byte Read: 0x%02X", data_out);

        // 6. STOP
        $display("\n6. Sending STOP condition...");
        stop = 1;
        #3000;
        stop = 0;
        wait(busy == 0);
        
        #100;
        if (!busy) $display("\n   -> Transaction complete. PASSED.");
        else       $display("\n   -> Bus is still busy. FAILED.");
        #2000;
        
        $display("\n=== All Tests Completed ===");
        #10000;
        $finish;
    end

endmodule
