`timescale 1ns/1ps

module eeprom_controller #(
    parameter integer BYTES = 4,
    parameter [6:0]   SLA7  = 7'h50
)(
    input             clk,
    input             reset,
    input             tick,
    input             req,
    input             wr,
    input      [15:0] addr,
    input      [31:0] din,
    output reg [31:0] dout,
    output reg        grant,
    input             i2c_busy,
    input             i2c_done,
    input             i2c_ack_err,
    input       [7:0] i2c_data_out,
    output reg        i2c_start,
    output reg        i2c_stop,
    output reg        i2c_write,
    output reg        i2c_read,
    output reg  [7:0] i2c_data_in,
    output reg        ack_in
);

// FSM 상태 정의 (쓰기/읽기 완전 분리)
localparam S_IDLE              = 4'd0;
// 쓰기 FSM
localparam S_WR_POLL_START     = 4'd1;
localparam S_WR_POLL_WAIT      = 4'd2;
localparam S_WR_POLL_STOP      = 4'd3;
localparam S_WR_START          = 4'd4;
localparam S_WR_ADDR_H         = 4'd5;
localparam S_WR_ADDR_L         = 4'd6;
localparam S_WR_DATA           = 4'd7;
localparam S_WR_STOP           = 4'd8;
// 읽기 FSM
localparam S_RD_START_W        = 4'd9;
localparam S_RD_ADDR_H         = 4'd10;
localparam S_RD_ADDR_L         = 4'd11;
localparam S_RD_REP_START      = 4'd12;
localparam S_RD_DATA           = 4'd13;
// 공통 대기 상태
localparam S_WAIT_DONE         = 4'd15;

reg [3:0]  state;
reg [2:0]  byte_cnt;
reg [15:0] r_addr;
reg [31:0] r_din;
reg [31:0] r_dout;
reg hold_start, hold_write, hold_stop, hold_read;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= S_IDLE; grant <= 1'b0; dout <= 32'h0; byte_cnt <= 0;
        {i2c_start, i2c_stop, i2c_write, i2c_read} <= 4'b0;
        {hold_start, hold_write, hold_stop, hold_read} <= 4'b0;
    end else begin
        grant <= (state != S_IDLE);
        
        // hold 신호 및 출력 레지스터 관리
        i2c_start <= hold_start; i2c_write <= hold_write;
        i2c_stop  <= hold_stop;  i2c_read  <= hold_read;

        if (tick) {hold_start, hold_write, hold_stop, hold_read} <= 4'b0;

        // FSM 상태 전이
        case(state)
            S_IDLE:
                if (req && !i2c_busy) begin
                    r_addr <= addr; r_din <= din; byte_cnt <= 0;
                    if (wr) state <= S_WR_POLL_START;
                    else begin dout <= 32'h0; state <= S_RD_START_W; end
                end

            // --- 쓰기 FSM ---
            S_WR_POLL_START:  {hold_start, hold_write, i2c_data_in, state} <= {1'b1, 1'b1, {SLA7,1'b0}, S_WAIT_DONE};
            S_WR_POLL_WAIT:   if(!i2c_busy) state <= S_WR_POLL_START;
            S_WR_POLL_STOP:   {hold_stop, state} <= {1'b1, S_WR_POLL_WAIT};
            S_WR_START:       {hold_start, hold_write, i2c_data_in, state} <= {1'b1, 1'b1, {SLA7,1'b0}, S_WAIT_DONE};
            S_WR_ADDR_H:      {hold_write, i2c_data_in, state} <= {1'b1, r_addr[15:8], S_WAIT_DONE};
            S_WR_ADDR_L:      {hold_write, i2c_data_in, state} <= {1'b1, r_addr[7:0], S_WAIT_DONE};
            S_WR_DATA:        {hold_write, i2c_data_in, state} <= {1'b1, r_din[8*(BYTES-1-byte_cnt)+:8], S_WAIT_DONE};
            S_WR_STOP:        {hold_stop, state} <= {1'b1, S_IDLE};

            // --- 읽기 FSM ---
            S_RD_START_W:     {hold_start, hold_write, i2c_data_in, state} <= {1'b1, 1'b1, {SLA7,1'b0}, S_WAIT_DONE};
            S_RD_ADDR_H:      {hold_write, i2c_data_in, state} <= {1'b1, r_addr[15:8], S_WAIT_DONE};
            S_RD_ADDR_L:      {hold_write, i2c_data_in, state} <= {1'b1, r_addr[7:0], S_WAIT_DONE};
            S_RD_REP_START:   {hold_start, hold_write, i2c_data_in, state} <= {1'b1, 1'b1, {SLA7,1'b1}, S_WAIT_DONE};
            S_RD_DATA:        {hold_read, state} <= {1'b1, S_WAIT_DONE};

            // --- 공통 대기 상태 ---
            S_WAIT_DONE:
                if(i2c_done) begin
                    if(i2c_ack_err && !(state == S_RD_DATA && ack_in)) begin // 읽기 마지막 NACK은 에러 아님
                        if(state == S_WR_POLL_START) state <= S_WR_POLL_STOP;
                        else state <= S_WR_STOP;
                    end else begin
                        case(state)
                            S_WR_POLL_START:  state <= S_WR_START;
                            S_WR_START:       state <= S_WR_ADDR_H;
                            S_WR_ADDR_H:      state <= S_WR_ADDR_L;
                            S_WR_ADDR_L:      state <= S_WR_DATA;
                            S_WR_DATA:
                                if(byte_cnt < BYTES-1) {byte_cnt, state} <= {byte_cnt + 1, S_WR_DATA};
                                else {dout, state} <= {r_din, S_WR_STOP};
                            
                            S_RD_START_W:     state <= S_RD_ADDR_H;
                            S_RD_ADDR_H:      state <= S_RD_ADDR_L;
                            S_RD_ADDR_L:      state <= S_RD_REP_START;
                            S_RD_REP_START:   state <= S_RD_DATA;
                            S_RD_DATA: begin
                                r_dout[8*(BYTES-1 - byte_cnt) +: 8] <= i2c_data_out;
                                if(byte_cnt < BYTES-1) {byte_cnt, state} <= {byte_cnt + 1, S_RD_DATA};
                                else {dout, state} <= {{r_dout[31:8], i2c_data_out}, S_IDLE};
                            end
                            default: state <= S_IDLE;
                        endcase
                    end
                end
        endcase
    end
end

always @(*) begin
    ack_in = (state == S_RD_DATA) && (byte_cnt == BYTES-1);
end

endmodule