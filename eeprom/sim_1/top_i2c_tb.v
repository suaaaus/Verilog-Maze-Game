`timescale 1ns / 1ps

// 이 테스트벤치는 전체 시스템인 top_i2c 모듈을 테스트합니다.
module top_i2c_tb;
    // --- DUT Inputs ---
    reg clk;
    reg reset;
    reg btn_req;
    reg wr_mode;
    reg show_hi;

    // --- DUT Outputs & Inouts ---
    wire sda;
    wire scl;
    wire [7:0] seg;
    wire [3:0] an;
    wire [15:0] led;

    // --- I2C EEPROM 슬레이브 시뮬레이션을 위한 신호 ---
    wire sda_slave_drive;
    reg  sda_slave_out;
    reg [7:0] slave_tx_data;
    reg [1:0] read_byte_count; // 몇 번째 바이트를 읽는지 카운트

    // --- DUT (top_i2c) 인스턴스화 ---
    top_i2c dut (
        .clk(clk), .reset(reset), .btn_req(btn_req), .wr_mode(wr_mode),
        .sda(sda), .scl(scl), .show_hi(show_hi),
        .seg(seg), .an(an), .led(led)
        // wp, A0, A1, A2는 top에서 상수로 구동되므로 연결하지 않아도 됩니다.
    );

    // --- [수정된 부분] SDA 라인 모델링 (오픈 드레인 & Pull-up) ---
    // 계층적 참조(dut.U_i2c_master)를 사용하여 top 모듈 내부의 i2c_master 신호에 접근합니다.
    wire master_drives_low = dut.U_i2c_master.out_sda_en && (dut.U_i2c_master.out_sda_data == 1'b0);
    wire slave_drives_low = sda_slave_drive && (sda_slave_out == 1'b0);
    assign sda = (master_drives_low || slave_drives_low) ? 1'b0 : 1'b1;
    assign sda_slave_drive = ~dut.U_i2c_master.out_sda_en;
    // =================================================================

    // --- 슬레이브 로직 (EEPROM 모델) ---
    always @(*) begin
        // 마스터가 데이터를 읽어가는 상태(READ_BIT)일 때
        if (dut.U_i2c_master.state == 4'd6) begin
            sda_slave_out = slave_tx_data[dut.U_i2c_master.bit_cnt];
        end
        // 마스터가 ACK를 기다리는 상태(WAIT_ACK)일 때
        else if (dut.U_i2c_master.state == 4'd7) begin
            sda_slave_out = 1'b0; // 항상 ACK 응답
        end
        else begin
            sda_slave_out = 1'b1; // 그 외에는 버스 제어권 놓음 (High-Z)
        end
    end

    // 읽기 동작 시, 슬레이브가 어떤 데이터를 보내야 할지 결정하는 로직
    always @(*) begin
        case(read_byte_count)
            2'd0: slave_tx_data = 8'hA1;
            2'd1: slave_tx_data = 8'hB2;
            2'd2: slave_tx_data = 8'hC3;
            2'd3: slave_tx_data = 8'hD4;
            default: slave_tx_data = 8'hFF;
        endcase
    end

    // eeprom_controller는 1바이트 읽고 트랜잭션을 종료하므로,
    // busy 신호가 high->low로 떨어질 때마다 읽기 카운터를 증가시킨다.
    always @(negedge dut.m_busy) begin
        if (reset == 0 && wr_mode == 0) begin
            read_byte_count <= read_byte_count + 1;
        end
    end
    // =================================================================

    // --- 시뮬레이션 로직 ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz 클럭
    end

    initial begin

        reset = 1;
        btn_req = 0;
        wr_mode = 0;
        show_hi = 0;
        read_byte_count = 0;
        #100;
        reset = 0;
        #2000;

        $display("=== top_i2c Write -> Read Test ===");

        // --- 시나리오 1: EEPROM에 데이터 쓰기 ---
        $display("\n1. Writing 0xA1B2C3D4 to EEPROM...");
        wr_mode = 1; // 쓰기 모드 설정
        #10;
        btn_req = 1; // 버튼 누름
        #10;
        btn_req = 0; // 버튼 뗌

        // EEPROM의 내부 쓰기 사이클(최대 5ms)을 포함하여 충분히 대기
        #10_000_000; // 10ms 대기
        $display("   -> Write operation complete.");

        // --- 시나리오 2: EEPROM에서 데이터 읽기 ---
        $display("\n2. Reading 4 bytes from EEPROM...");
        wr_mode = 0; // 읽기 모드 설정
        read_byte_count = 0; // 읽기 카운터 초기화
        #10;
        btn_req = 1; // 버튼 누름
        #10;
        btn_req = 0; // 버튼 뗌

        // 4바이트를 모두 읽을 때까지 대기 (1바이트당 약 250us 소요 가정)
        #2_000_000; // 2ms 대기
        $display("   -> Read operation complete.");
        $display("   -> Final Read Data (dut.dout_32): 0x%08X", dut.u_eeprom_controller.dout);

        // --- 결과 검증 ---
        if (dut.u_eeprom_controller.dout === 32'hA1B2C3D4) begin
            $display("\n[SUCCESS] Read data matches written data.");
        end else begin
            $display("\n[FAILURE] Read data does NOT match written data!");
        end

        #10000;
        $finish;
    end

endmodule