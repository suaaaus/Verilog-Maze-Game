module i2c_master(clk, reset, start, stop, write, read, ack_in, tick, data_in,
                  data_out, done, busy, ack_err, sda, scl);
    input clk, reset;
    input start, stop, write, read;
    input ack_in;
    input tick;
    input [7:0] data_in;
    output reg [7:0] data_out;
    output reg done, busy;
    output reg ack_err;
    inout sda;
    output reg scl;

    reg  out_sda_en;
    reg  out_sda_data;
    wire in_sda;

    assign sda = out_sda_en ? out_sda_data : 1'bz;
    assign in_sda = sda;

    // 상태 정의
    localparam IDLE      = 4'd0,
               START_1   = 4'd1,
               START_2   = 4'd2,
               WRITE_BIT = 4'd3,
               READ_BIT  = 4'd4,
               WAIT_ACK  = 4'd5,
               STOP_1    = 4'd6,
               STOP_2    = 4'd7,
               STOP_3    = 4'd8,
               STOP_4    = 4'd9;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [1:0] tick_cnt;
    reg [7:0] shift_reg;
    // 명령어 latching*******
    reg r_write, r_read;


    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            tick_cnt  <= 0;
            bit_cnt   <= 0;
            shift_reg <= 0;
            scl       <= 1'b1;
            out_sda_en<= 1'b0;
            busy      <= 0;
            ack_err   <= 0;
            done      <= 0;
            data_out  <= 0;
            // latching reg 리셋
            r_write   <= 0;
            r_read    <= 0;
        end 
        else begin
            done <= 0;
            // FSM의 모든 동작은 tick 펄스에 맞춰서 (400KHz)
            if (tick) begin
                case (state)
                    IDLE: begin
                        scl <= 1'b1;
                        out_sda_en <= 1'b0;
                        
                        if (start) begin
                            // START가 감지된 tick에서만 write/read를 함께 래칭
                            r_write   <= write;
                            r_read    <= read;
                            busy      <= 1;
                            ack_err   <= 0;
                            shift_reg <= data_in;
                            out_sda_en   <= 1'b1;
                            out_sda_data <= 1'b0; // SDA LOW (START 조건)
                            state        <= START_1;
                        end 
                        else if (stop) begin
                            state <= STOP_1;
                        // Multi-byte 를 읽는 경우 *********************
                        end 
                        else if (busy && (r_write || r_read)) begin
                            shift_reg <= data_in;
                            state     <= START_2; // START_1을 건너뛰고 바로 동작 시작
                        end
                    end

                    START_1: begin
                        scl   <= 1'b0;
                        state <= START_2;
                    end

                    START_2: begin
                        tick_cnt <= 0;
                        bit_cnt  <= 7;
                        // 저장해 두었던 r_write/r_read 값을 확인
                        if (r_write) state <= WRITE_BIT;
                        else if (r_read) state <= READ_BIT;
                        else state <= IDLE;
                    end

                    WRITE_BIT: begin
                        case (tick_cnt)
                            2'd0: begin out_sda_data <= shift_reg[bit_cnt]; tick_cnt <= tick_cnt + 1; end
                            2'd1: begin scl <= 1'b1; tick_cnt <= tick_cnt + 1; end
                            2'd2: tick_cnt <= tick_cnt + 1;
                            2'd3: begin
                                scl <= 1'b0;
                                tick_cnt <= 0;
                                if (bit_cnt == 0) begin
                                    state <= WAIT_ACK;
                                    out_sda_en <= 1'b0;
                                end else begin
                                    bit_cnt <= bit_cnt - 1;
                                end
                            end
                        endcase
                    end

                    WAIT_ACK: begin
                        case (tick_cnt)
                            2'd0: tick_cnt <= tick_cnt + 1;
                            2'd1: begin scl <= 1'b1; tick_cnt <= tick_cnt + 1; end
                            2'd2: begin
                                if (out_sda_en == 1'b0) ack_err <= in_sda;
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd3: begin
                                scl   <= 1'b0;
                                done  <= 1'b1;
                                state <= IDLE;
                            end
                        endcase
                    end

                    READ_BIT: begin
                        case (tick_cnt)
                            2'd0: begin out_sda_en <= 1'b0; tick_cnt <= tick_cnt + 1; end
                            2'd1: begin scl <= 1'b1; shift_reg[bit_cnt] <= in_sda; tick_cnt <= tick_cnt + 1; end
                            2'd2: tick_cnt <= tick_cnt + 1;
                            2'd3: begin
                                scl <= 1'b0;
                                tick_cnt <= 0;
                                if (bit_cnt == 0) begin
                                    data_out     <= shift_reg;
                                    out_sda_en   <= 1'b1;
                                    out_sda_data <= ack_in;
                                    state        <= WAIT_ACK;
                                end else begin
                                    bit_cnt      <= bit_cnt - 1;
                                end
                            end
                        endcase
                    end

                    STOP_1: begin out_sda_en <= 1'b1; out_sda_data <= 1'b0; state <= STOP_2; end
                    STOP_2: begin scl <= 1'b1; state <= STOP_3; end
                    STOP_3: begin out_sda_en <= 1'b0; state <= STOP_4; end
                    STOP_4: begin 
                        done <= 1'b1; 
                        busy <= 0; 
                        // 트랜잭션이 끝났으므로 래칭된 명령어 초기화 ************
                        r_write <= 0;
                        r_read  <= 0;
                        state <= IDLE; end
                endcase
            end
        end
    end

    reg [39:0] state_str;
    always @(*) begin
        case (state)
            IDLE :      state_str = "IDLE";
            START_1:    state_str = "STAR1";
            START_2:    state_str = "STAR2";
            WRITE_BIT:  state_str = "WRITE";
            READ_BIT:   state_str = "READ ";
            WAIT_ACK:   state_str = "WAIT ";
            STOP_1:   state_str = "STOP1";
            STOP_2:   state_str = "STOP2";
            STOP_3:   state_str = "STOP3";
            STOP_4:   state_str = "STOP4";
            default: state_str = "UNDEF";
        endcase
    end
endmodule