`timescale 1ns / 1ps

module top_i2c(clk, reset, btn_req, wr_mode, sda, scl,  show_hi,seg,an,led,wp, A0, A1, A2);
    input           clk, reset;

    input           btn_req;
    input           wr_mode;   //w,r mode
    input           show_hi;


    inout           sda;
    output          scl;
    output [7:0]    seg;
    output [3:0]    an;
    // 0:m_busy, 1:m_ack_err, 2:wr_mode, 3:show_hi
    output [15:0]   led;    
    output wp, A0, A1, A2;
    
    // 항상 Low로 구동
    assign wp = 1'b0;
    assign A0 = 1'b0;
    assign A1 = 1'b0;
    assign A2 = 1'b0;

    wire tick_400KHz;
    tick_generator #(.INPUT_FREQ(100_000_000), .TICK_HZ(400_000)) U_tick_100KHz(.clk(clk), .reset(reset), .tick(tick_400KHz));

    // eeprom_controller <-> i2c_master
    wire        c_start, c_stop, c_write, c_read;
    wire [7:0]  c_din;
    wire        c_ack_in;

    wire [7:0]  m_dout;
    wire        m_done, m_busy, m_ack_err;
    ////////////////////

    i2c_master U_i2c_master(.clk(clk), .reset(reset), .start(c_start), .stop(c_stop), .write(c_write), .read(c_read), .ack_in(c_ack_in), 
                            .tick(tick_400KHz), .data_in(c_din),
                            .data_out(m_dout), .done(m_done), .busy(m_busy), .ack_err(m_ack_err), .sda(sda), .scl(scl));
    

    reg btn_sync0, btn_sync1, btn_sync2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            btn_sync0 <= 1'b0; btn_sync1 <= 1'b0; btn_sync2 <= 1'b0;
        end else begin
            // 스위치 동기화(3단)
            btn_sync0 <= btn_req;
            btn_sync1 <= btn_sync0;
            btn_sync2 <= btn_sync1;
        end
    end
    wire btn_rise = btn_sync1 & ~btn_sync2;

    reg req_level, seen_busy;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            req_level <= 1'b0;
            seen_busy <= 1'b0;
        end else begin
            if (btn_rise) req_level <= 1'b1;     // 요청 래치
            if (m_busy)   seen_busy <= 1'b1;     // 트랜잭션 진행 감지
            if (seen_busy && !m_busy) begin      // 트랜잭션 종료 시점
                req_level <= 1'b0;
                seen_busy <= 1'b0;
            end
        end
    end


    // master 출력은 top port로 
    // assign data_out = m_dout;
    // assign done     = m_done;
    // assign busy     = m_busy;
    // assign ack_err  = m_ack_err;
    
    // 주소 고정
    wire [15:0] eep_addr = 16'h0010;
    wire [31:0] din_const =32'ha1b2c3d4;
    // wire        grant = 1'b1;
    wire [31:0] dout_32;

    // 디버깅/////////////////////////
    wire grant_mon;
    reg [19:0] tick_cnt;
    always @(posedge clk or posedge reset) begin
      if (reset) tick_cnt <= 0;
      else if (tick_400KHz) tick_cnt <= tick_cnt + 1;
    end
    /////////////////////////////

    eeprom_controller #( .BYTES(4), .SLA7(7'h58))
    u_eeprom_controller(
        .clk(clk), 
        .reset(reset), 
        .tick(tick_400KHz),
        .req(req_level),    // sw1 0->1 
        .wr(wr_mode),       // sw2로 0(R), 1(W)
        .addr(eep_addr),    // 16'h0010
        .din(din_const),    // 32'ha1b2c3d4
        .dout(dout_32),     // fnd 출력 비교용
        .grant(grant_mon),   
        .i2c_busy(m_busy), 
        .i2c_done(m_done),  
        .i2c_ack_err(m_ack_err),
        .i2c_data_out(m_dout),
        .i2c_start(c_start), 
        .i2c_stop(c_stop), 
        .i2c_write(c_write), 
        .i2c_read(c_read),
        .i2c_data_in(c_din),
        .ack_in(c_ack_in) 
    );

    //show_hi를 sw로 제어
    fnd_controller_eep u_fnd_controller_eep(
        .clk(clk), 
        .reset(reset),
        .input_data(dout_32), // 전체 데이터 32bit
        .show_hi(show_hi),    // 1:[31:16], 0:[15:0]
        .seg_data(seg),
        .an(an)
    );

    // wire w_sda = sda;
    assign led[0]    = m_busy;
    assign led[1]    = wr_mode ? m_ack_err : 1'b0;
    assign led[2]    = wr_mode;     
    assign led[3]    = show_hi;     
    assign led[4]    = req_level;     
    assign led[5]    = grant_mon;     
    assign led[6]    = tick_cnt[19];
    assign led[7]    = sda;             // idle에서 1
    assign led[15:8] = 8'b0;
    
endmodule