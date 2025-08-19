`timescale 1ns/1ps
module eeprom_controller #(
  parameter integer BYTES      = 4,
  parameter [6:0]   SLA7       = 7'h50,  // 24C256: 0x50~0x57 (A2/A1/A0)
  parameter integer ADDR_BYTES = 2       // 24C256: 2바이트 주소
)(
  input              clk,
  input              reset,
  input              tick,         // 400 kHz tick (마스터와 명령 정렬)
  input              req,          // 1회 트랜잭션 요청(레벨)
  input              wr,           // 1: Write, 0: Read
  input      [15:0]  addr,         // 시작 주소
  input      [31:0]  din,          // 쓰기 데이터 (MSB first)
  output reg [31:0]  dout,         // 읽기 데이터 (MSB first)
  output reg         grant,        // 사용 중 표시(옵션)

  // I2C master IF
  input              i2c_busy,
  input              i2c_done,
  input              i2c_ack_err,
  input      [7:0]   i2c_data_out,
  output reg         i2c_start,
  output reg         i2c_stop,
  output reg         i2c_write,
  output reg         i2c_read,     // READ 1바이트 시작 펄스
  output reg  [7:0]  i2c_data_in,
  output reg         ack_in        // ACK(0)/NACK(1)
);

  // 상태
  localparam IDLE          = 4'd0;
  localparam WAIT_ACK      = 4'd1;

  // WRITE
  localparam R_SLAW        = 4'd2;   // 주소 지정 공통(SLAW, W)
  localparam W_MEM_H       = 4'd3;
  localparam W_MEM_L       = 4'd4;
  localparam W_DATA        = 4'd5;
  localparam W_POLL        = 4'd6;   // 내부 write-cycle ACK 폴링
  localparam W_POLL_RETRY  = 4'd7;   // 폴링 NACK → STOP 후 재START 대기

  // READ (바이트마다 랜덤 리드)
  localparam R_MEM_H       = 4'd8;
  localparam R_MEM_L       = 4'd9;
  localparam R_SLAR        = 4'd10;  // SLA+R (ReSTART)
  localparam R_DATA        = 4'd11;  // READ 1바이트 트리거
  localparam R_RETRY       = 4'd12;  // SLAR NACK → STOP 후 재SLAR 대기
  localparam R_ADDR_RETRY  = 4'd13;  // 주소 바이트 NACK → STOP 후 재SLAW 대기
  localparam R_NEXT        = 4'd14;  // 다음 바이트용: STOP 완료(!busy) 대기 → SLAW

  reg [3:0]  state, prev_state;
  reg [2:0]  wbyte_cnt;
  reg [2:0]  rd_idx;
  reg [15:0] rd_addr;

  // READ 결과 임시 버퍼(모두 성공 시에만 dout로 커밋)
  reg [31:0] rd_buf;

  // 마스터 명령 1틱 펄스선
  reg hold_start, hold_write, hold_stop, hold_read;

  // READ 트리거/ACK 유지
  reg arm_read;    // !i2c_busy에서 1틱 read 펄스 생성
  reg ack_hold;    // 이번 바이트 ACK(0)/NACK(1)

  wire [7:0] addr_hi = {1'b0, rd_addr[14:8]};

  // WAIT_ACK 동안 직전 상태 기록
  always @(posedge clk or posedge reset) begin
    if (reset) prev_state <= IDLE;
    else if (state != WAIT_ACK) prev_state <= state;
  end

  // 본 동작
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state       <= IDLE;
      grant       <= 1'b0;
      dout        <= 32'h0;
      rd_buf      <= 32'h0;

      i2c_start   <= 1'b0;
      i2c_stop    <= 1'b0;
      i2c_write   <= 1'b0;
      i2c_read    <= 1'b0;
      i2c_data_in <= 8'h00;
      ack_in      <= 1'b0;

      hold_start  <= 1'b0;
      hold_write  <= 1'b0;
      hold_stop   <= 1'b0;
      hold_read   <= 1'b0;

      wbyte_cnt   <= 3'd0;
      rd_idx      <= 3'd0;
      rd_addr     <= 16'h0000;

      arm_read    <= 1'b0;
      ack_hold    <= 1'b0;

    end else begin
      // 펄스 라인 구동
      i2c_start <= hold_start;
      i2c_write <= hold_write;
      i2c_stop  <= hold_stop;
      i2c_read  <= hold_read;
      ack_in    <= ack_hold;

      // 1틱 후 펄스 클리어 + READ 트리거
      if (tick) begin
        hold_start <= 1'b0;
        hold_write <= 1'b0;
        hold_stop  <= 1'b0;
        hold_read  <= 1'b0;
        if (arm_read && !i2c_busy) hold_read <= 1'b1;
      end

      case (state)
        // ------------------------------------------------
        // IDLE
        // ------------------------------------------------
        IDLE: begin
          grant     <= 1'b0;
          wbyte_cnt <= 3'd0;
          rd_idx    <= 3'd0;
          rd_addr   <= addr;
          arm_read  <= 1'b0;
          ack_hold  <= 1'b0;

          if (req && !i2c_busy) begin
            grant   <= 1'b1;
            rd_buf  <= 32'h0;       // 이번 READ 결과 채움
            if (!wr) dout <= 32'h0; // ★ 요청대로: READ 시작 즉시 dout 클리어

            // 공통 진입: SLAW(W)
            i2c_data_in <= {SLA7,1'b0};
            hold_start  <= 1'b1;
            hold_write  <= 1'b1;
            state       <= WAIT_ACK;
          end
        end

        // ------------------------------------------------
        // WRITE 경로
        // ------------------------------------------------
        W_MEM_H: begin
          i2c_data_in <= addr_hi;
          hold_write  <= 1'b1;
          state       <= WAIT_ACK;
        end

        W_MEM_L: begin
          i2c_data_in <= rd_addr[7:0];
          hold_write  <= 1'b1;
          state       <= WAIT_ACK;
        end

        W_DATA: begin
          i2c_data_in <= din[8*(BYTES-1 - wbyte_cnt) +: 8]; // MSB first
          hold_write  <= 1'b1;
          state       <= WAIT_ACK;
        end

        W_POLL: begin
          i2c_data_in <= {SLA7,1'b0};  // SLAW(W)
          hold_start  <= 1'b1;
          hold_write  <= 1'b1;
          state       <= WAIT_ACK;
        end

        W_POLL_RETRY: begin
          if (!i2c_busy) begin
            i2c_data_in <= {SLA7,1'b0};
            hold_start  <= 1'b1;
            hold_write  <= 1'b1;
            state       <= WAIT_ACK;
          end
        end

        // ------------------------------------------------
        // READ 경로 (바이트마다 랜덤 리드)
        // ------------------------------------------------
        R_MEM_H: begin
          i2c_data_in <= addr_hi;
          hold_write  <= 1'b1;
          state       <= WAIT_ACK;
        end

        R_MEM_L: begin
          i2c_data_in <= rd_addr[7:0];
          hold_write  <= 1'b1;
          state       <= WAIT_ACK;
        end

        R_SLAR: begin
          i2c_data_in <= {SLA7,1'b1};  // SLA+R
          hold_start  <= 1'b1;         // ReSTART
          hold_write  <= 1'b1;
          ack_hold    <= 1'b1;         // 이 마스터는 READ ACK을 못 보냄 → 항상 NACK(1)
          state       <= WAIT_ACK;
        end

        R_RETRY: begin
          if (!i2c_busy) begin
            i2c_data_in <= {SLA7,1'b1}; // SLAR 재시도
            hold_start  <= 1'b1;
            hold_write  <= 1'b1;
            state       <= WAIT_ACK;
          end
        end

        R_ADDR_RETRY: begin
          if (!i2c_busy) begin
            i2c_data_in <= {SLA7,1'b0}; // 주소 지정 재시작: SLAW부터
            hold_start  <= 1'b1;
            hold_write  <= 1'b1;
            state       <= WAIT_ACK;
          end
        end

        R_DATA: begin
          arm_read <= 1'b1;            // !busy 시 READ 1바이트 트리거
          state    <= WAIT_ACK;
        end

        R_NEXT: begin
          if (!i2c_busy) begin
            // 다음 바이트: 다시 SLAW부터
            i2c_data_in <= {SLA7,1'b0};
            hold_start  <= 1'b1;
            hold_write  <= 1'b1;
            state       <= WAIT_ACK;
          end
        end

        // ------------------------------------------------
        // 공통 이벤트
        // ------------------------------------------------
        WAIT_ACK: begin
          if (i2c_done) begin
            // READ의 '의도된' NACK은 에러 아님
            if (i2c_ack_err && !(prev_state==R_DATA && ack_hold==1'b1)) begin
              // 예기치 않은 NACK → STOP 보장 후 재시도/종료
              hold_stop <= 1'b1;
              case (prev_state)
                W_POLL:                 state <= W_POLL_RETRY;
                R_SLAR:                 state <= R_RETRY;
                R_MEM_H, R_MEM_L,
                R_NEXT, IDLE:          state <= R_ADDR_RETRY; // SLAW부터 재시도
                default: begin
                  grant    <= 1'b0;
                  arm_read <= 1'b0;
                  ack_hold <= 1'b0;
                  state    <= IDLE;  // 실패 시 dout은 이미 0으로 클리어됨(요청사항)
                end
              endcase
            end else begin
              // 정상 경로(ACK 또는 의도된 NACK)
              case (prev_state)
                // 진입 분기
                IDLE:    state <= wr ? ((ADDR_BYTES==2)?W_MEM_H:W_MEM_L)
                                     : ((ADDR_BYTES==2)?R_MEM_H:R_MEM_L);

                // ---------- WRITE ----------
                W_MEM_H: state <= W_MEM_L;
                W_MEM_L: begin wbyte_cnt <= 3'd0; state <= W_DATA; end

                W_DATA: begin
                  if (wbyte_cnt + 1 == BYTES) begin
                    hold_stop <= 1'b1;
                    state     <= W_POLL;
                  end else begin
                    wbyte_cnt <= wbyte_cnt + 1;
                    state     <= W_DATA;
                  end
                end

                W_POLL, W_POLL_RETRY: begin
                  hold_stop <= 1'b1;
                  dout      <= din;   // 쓰기값 미러
                  grant     <= 1'b0;
                  state     <= IDLE;
                end

                // ---------- READ ----------
                // SLAW가 성공했으면 주소 상/하위로
                R_NEXT,
                R_ADDR_RETRY: state <= (ADDR_BYTES==2) ? R_MEM_H : R_MEM_L;
                R_MEM_H:      state <= R_MEM_L;
                R_MEM_L:      state <= R_SLAR;

                R_SLAR, R_RETRY: begin
                  // SLAR ACK 후 1바이트 READ
                  arm_read <= 1'b0;
                  state    <= R_DATA;
                end

                R_DATA: begin
                  // 바이트 수신 완료: STOP 명시 생성(다음 바이트/종료 위해 busy 풀어줌)
                  rd_buf[8*(BYTES-1 - rd_idx) +: 8] <= i2c_data_out;
                  arm_read  <= 1'b0;
                  hold_stop <= 1'b1;

                  if (rd_idx + 1 == BYTES) begin
                    dout   <= rd_buf;   // 모든 바이트 성공 → 커밋
                    grant  <= 1'b0;
                    state  <= IDLE;
                  end else begin
                    rd_idx  <= rd_idx + 1;
                    rd_addr <= rd_addr + 1;
                    state   <= R_NEXT;  // STOP 완료(!busy) 대기 후 다음 바이트
                  end
                end

                default: state <= IDLE;
              endcase
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end
endmodule
