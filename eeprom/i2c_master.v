`timescale 1ns / 1ps

module i2c_master(clk, reset, start, stop, write, read, ack_in, tick, data_in,
                  data_out, done, busy, ack_err, sda, scl);
    input clk, reset;
    input start, stop, write, read;
    input ack_in; // 더 받을지 말지 (1: 그만받는다, read에서 마지막 byte)
    input tick;
    input [7:0] data_in;
    output reg [7:0] data_out;
    output reg done, busy;
    output reg ack_err;
    inout sda;
    output scl;

    reg  out_sda_en;
    reg  out_sda_data;
    wire in_sda;

    assign sda = out_sda_en ? out_sda_data : 1'bz;
    assign in_sda = sda;

    // 상태 정의
    localparam IDLE      = 4'd0,

               START_1   = 4'd1,
               START_2   = 4'd2,
               START_3   = 4'd3,
               START_4   = 4'd4,

               WRITE_BIT = 4'd5,
               READ_BIT  = 4'd6,
               WAIT_ACK  = 4'd7,

               STOP_1    = 4'd8,
               STOP_2    = 4'd9,
               STOP_3    = 4'd10,
               STOP_4    = 4'd11,

               CMD_WAIT = 4'd12,
               ABORT_STOP = 4'd13;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [1:0] tick_cnt; // 400KHz 4번이면 100KHz
    reg [7:0] data_reg;
    // 명령어 latching*******
    reg r_write, r_read;

    reg r_scl;
    assign scl = (state == IDLE) ? 1'b1 : r_scl;


    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // 모든 레지스터 리셋
            state     <= IDLE;
            tick_cnt  <= 0;
            bit_cnt   <= 0;
            data_reg <= 0;
            r_scl   <= 1'b1;
            out_sda_en<= 1'b0;
            busy      <= 0;
            ack_err   <= 0;
            done      <= 0;
            data_out  <= 0;
            r_write   <= 0;
            r_read    <= 0;
            out_sda_data <= 0;
        end 
        else begin
            done <= 0;

            // 명령어 래칭: start 신호가 들어올 때 write/read 상태를 기억
            if (start) begin
                r_write <= write;
                r_read  <= read;
            end


            if (tick) begin
                case (state)
                    IDLE: begin
                        r_scl <= 1'b1;
                        out_sda_en <= 1'b0; //입력  

                        // 1. Transaction 시작 (START 또는 REPEATED START)
                        if (start) begin
                            busy <= 1;
                            ack_err   <= 0;
                            data_reg <= data_in;
                            out_sda_en   <= 1'b1; // 출력 (start조건 제어해야 하니까)
                            out_sda_data <= 1'b1;
                            state        <= START_1;
                        end
                    end

                    START_1: begin
                        out_sda_data <= 1'b1;                 
                        state <= START_2;
                    end

                    START_2: begin 
                        state <= START_3;
                    end

                    START_3: begin
                        out_sda_data <= 1'b0; // start 조건 
                        state <= START_4;
                        
                    end

                    START_4: begin
                        r_scl   <= 1'b0;
                        tick_cnt <= 0;
                        bit_cnt  <= 3'd7;
                        // inout 제어는 WRITE/READ 하기 전 여기에서 !! 
                        if (r_write) begin
                            state <= WRITE_BIT;
                            out_sda_en <= 1'b1;
                        end
                        else if  (r_read) begin
                            state <= READ_BIT;
                            out_sda_en <= 1'b0;
                        end
                        else 
                            state <= CMD_WAIT;
                    end

                    WRITE_BIT: begin
                        busy <= 1;
                        case (tick_cnt)
                            2'd0: begin 
                                // scl이 1 되기 전에 SDA에 데이터 준비
                                out_sda_data <= data_reg[bit_cnt]; // data_reg에는 data_in이 할당 되어있음
                                tick_cnt <= tick_cnt + 1; 
                                end
                            2'd1: begin 
                                r_scl <= 1'b1; 
                                tick_cnt <= tick_cnt + 1; 
                                end
                            2'd2: tick_cnt <= tick_cnt + 1;
                            2'd3: begin
                                r_scl <= 1'b0;
                                tick_cnt <= 0;
                                if (bit_cnt == 0) begin
                                    state <= WAIT_ACK;
                                    out_sda_data <= 0;
                                end 
                                else 
                                    bit_cnt <= bit_cnt - 3'd1;
                            end
                        endcase
                    end

                    WAIT_ACK: begin
                        busy <= 1;
                        case (tick_cnt)
                            2'd0: begin tick_cnt <= tick_cnt + 1;
                                         out_sda_en <= 1'b0;
                            end
                            2'd1: begin 
                                r_scl <= 1'b1; 
                                tick_cnt <= tick_cnt + 1; 
                            end
                            2'd2: begin
                                if (out_sda_en == 1'b0) 
                                    ack_err <= in_sda;
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd3: begin
                                r_scl <= 1'b0;
                                tick_cnt <= 0; // tick_cnt 초기화

                                if (in_sda) begin // NACK(1) 감지
                                    state <= ABORT_STOP; // 강제 STOP
                                    out_sda_en <= 1'b1; // stop 조건 위한 en 활성화
                                end 
                                else begin       // ACK 수신
                                    done  <= 1'b1;
                                    state <= CMD_WAIT;  
                                end
                            end
                        endcase
                    end
 
                    READ_BIT: begin
                        busy <= 1;
                        case (tick_cnt)
                            2'd0: begin
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd1: begin
                                r_scl <= 1'b1;
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd2: begin
                                // SCL이 High인 동안 SDA 값을 읽어서 저장 
                                data_reg <= {data_reg[6:0], in_sda};
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd3: begin
                                r_scl <= 1'b0;
                                tick_cnt <= 0;
                                 // 8비트를 모두 읽었을 때   
                                if (bit_cnt == 0) begin                                
                                    data_out   <= data_reg; // 완성 된 값
                                    out_sda_en   <= 1'b1;  // ACK/NACK 보낼 준비
                                    out_sda_data <= ack_in; 
                                    state        <= WAIT_ACK;
                                end
                                else 
                                    bit_cnt <= bit_cnt - 3'd1;
                            end
                        endcase
                    end

                    CMD_WAIT : begin
                        r_scl <= 1'b0;
                        out_sda_en <= 1'b0;
                        tick_cnt <= 0; // 추가 (w/r하기전에 tick_cnt도 초기화 해야 8bit 읽음)
                        busy <= 0;
                        // 2. Transaction 종료
                        if (stop) begin
                            out_sda_en <= 1'b1;  // 출력 (stop조건 제어해야 하니까)
                            state <= STOP_1;
                        end 
                        // 3. Repeated Start               
                        else if (start/* && (write || read)*/) begin
                            out_sda_en <= 1'b1; // 출력 (start조건 제어해야 하니까)
                            out_sda_data <= 1'b1;
                            data_reg <= data_in;
                            state <= START_1; 
                        end
                        else if (r_write) begin
                            out_sda_en <= 1'b1; // 출력 (start조건 제어해야 하니까)
                            state <= WRITE_BIT; 
                            data_reg <= data_in;
                            bit_cnt  <= 3'd7;
                        end
                        else if (read) begin
                            out_sda_en <= 1'b0; // 입력이니까 0
                            state <= READ_BIT; 
                            bit_cnt  <= 3'd7;
                        end
                    end

                    STOP_1: begin  // 이미 en은 1이 된 상태
                        out_sda_data <= 1'b0; 
                        state <= STOP_2; 
                    end
                    STOP_2: begin 
                        r_scl <= 1'b1; 
                        state <= STOP_3; 
                    end
                    STOP_3: begin 
                        out_sda_en <= 1'b0;  // SDA가 HiZ (1)로 stop 조건 완성
                        state <= STOP_4; 
                    end
                    STOP_4: begin 
                        done    <= 1'b1; 
                        busy    <= 0; 
                        state   <= IDLE; 
                    end

                    // ABORT_STOP 상태 추가
                    ABORT_STOP: begin
                        busy <= 1;
                        case (tick_cnt)
                            2'd0: begin
                                out_sda_data <= 1'b0;   
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd1: begin
                                r_scl <= 1'b1;
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd2: begin
                                out_sda_data <= 1'b1; // stop 조건
                                tick_cnt <= tick_cnt + 1;
                            end
                            2'd3: begin
                                done <= 1'b1; // ack_err는 1, done 신호 1
                                state <= IDLE; 
                                tick_cnt <= 0;
                                busy <= 0;
                            end
                        endcase
                    end

                    default: begin
                        state <= IDLE;
                        busy  <= 0;
                    end
            endcase
            end
        end
    end


///// simulation debugging 용 ////////////
    reg [39:0] i2c_state;
    always @(*) begin
        case (state)
            IDLE :      i2c_state = "IDLE ";
            START_1:    i2c_state = "STAR1";
            START_2:    i2c_state = "STAR2";
            START_3:    i2c_state = "STAR3";
            START_4:    i2c_state = "STAR4";
            WRITE_BIT:  i2c_state = "WRITE";
            READ_BIT:   i2c_state = "READ ";
            WAIT_ACK:   i2c_state = "WAIT ";
            STOP_1:     i2c_state = "STOP1";
            STOP_2:     i2c_state = "STOP2";
            STOP_3:     i2c_state = "STOP3";
            STOP_4:     i2c_state = "STOP4";
            CMD_WAIT:   i2c_state = "CMDWT";
            ABORT_STOP: i2c_state = "SHUTD";
            default:    i2c_state = "UNDEF";
        endcase
    end

endmodule