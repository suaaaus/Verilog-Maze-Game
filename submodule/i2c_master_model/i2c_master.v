module i2c_master(clk, reset, start, stop, write, read, ack_in, tick, data_in,
                  data_out, done/*, busy*/, ack_err, sda, scl);

    input clk, reset; // active high reset
    input start, stop, write, read;
    input ack_in;
    input tick; // 100KHz 기반 동작 tick
    input  [7:0] data_in;
    output reg [7:0] data_out;
    output reg done/*, busy*/;
    output reg ack_err;
    inout sda;
    output reg scl;

    // SDA open-drain
    // input으로 쓸 땐 sda_in / output으로 쓸 땐 sda_out
    wire sda_in;
    reg sda_out;
    
    assign sda = (sda_out) ? 1'b0 : 1'bz;  // 1:LOW 출력, 0:High-Z(입력 대기) 
    assign sda_in = sda;  // SDA 출력X (High-Z) - 입력 대기

    reg [3:0] state;
    reg [3:0] data_bit; 
    reg [7:0] shift_reg;

    localparam IDLE  = 4'b0000,
               START = 4'b0001,
               SEND_BYTE  = 4'b0010,
               WAIT_ACK  = 4'b0011,
               RECV_BYTE  = 4'b0100,
               SEND_ACK  = 4'b0101,
               SEND_NACK = 4'b0110,
               STOP = 4'b0111,
               DONE = 4'b1000;


    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 1'b0;
            ack_err <= 1'b0;
            scl <= 1'b1; // default high
            data_bit <= 4'd0; 
        end

        else begin
            case (state)
                IDLE : begin
                    done <= 1'b0;
                    ack_err <= 1'b0;
                    sda_out <= 1'b0;
                    data_bit <= 4'd0;
                    if (start) begin
                        state <= START;
                    end
                    else if (write) begin
                        shift_reg <= data_in;
                        data_bit <= 4'd0; 
                        state <= SEND_BYTE;
                    end
                    else if (read) begin
                        data_bit <= 4'd0;
                        state <= RECV_BYTE;
                    end
                    else if (stop) begin
                        state <= STOP;
                    end
                end

                START : begin
                    if (scl) begin
                        sda_out <= 1'b0; // sda_in으로
                        scl <= 1'b0;
                        state <= SEND_BYTE;
                    end
                end
                
/////////////////////// WRITE ///////////////////////
                SEND_BYTE : begin
                    if (tick) begin
                        scl <= ~scl; // 100KHz clk 생성

                        if (!scl) begin // scl이 low일 때 sda를 미리 준비해야함
                            sda_out <= ~shift_reg[7];// 0이면 SDA 당김 (LOW), 1이면 놔둠 (Z) 수정********
                        end
                        else begin // scl이 high 일 때
                            shift_reg <= {shift_reg[6:0], 1'b0}; // shift left
                            data_bit <= data_bit + 1;

                            if (data_bit == 4'd7) begin
                                data_bit <= 4'd0;
                                sda_out <= 1'b0; // SDA 입력모드
                                state <= WAIT_ACK;
                            end
                        end
                    end
                end

                WAIT_ACK : begin 
                    if (tick) begin
                        scl <= ~scl; // 100KHz clk 
                        if (scl) begin // high 일 때
                            ack_err <= sda_in;
                            // if (!sda_in) // low면 
                            //     ack_err <= 1'b0;
                            // else
                            //     ack_err <= 1'b1;
                            done <= 1'b1;
                            state <= IDLE; 
                        end
                    end
                end
///////////////////////  READ /////////////////////////
                RECV_BYTE : begin
                    sda_out <= 1'b0; // 입력 Z
                    if (tick) begin
                        scl <= ~scl;
                        if (scl) begin // high일때
                            shift_reg <= {shift_reg[6:0], sda_in};  // shift left
                            data_bit <= data_bit + 1'b1;

                            if (data_bit == 3'd7) begin
                                data_out <= {shift_reg[6:0], sda_in}; // 마지막 비트 포함
                                state <= (ack_in == 0) ? SEND_ACK : SEND_NACK;
                            end
                        end               
                    end
                end

                SEND_ACK : begin
                    if (tick) begin
                        scl <= 1'b1;
                        sda_out <= 1'b0;
                        state <= DONE;
                    end
                end

                SEND_NACK : begin
                    sda_out <= 1'b1;
                    if (tick) begin
                        scl <= 1'b1;
                        state <= DONE; // or stop
                    end
                end
///////////////////////////////////////////////////////
                STOP : begin
                    if (scl) begin
                        sda_out <= 1'b1;
                        state <= DONE;
                    end
                end

                DONE : begin
                    done <= 1'b1;
                    state <= IDLE;
                end
            
            endcase
        end
    end


    reg [39:0] state_str;
    always @(*) begin
        case (state)
            IDLE : state_str = "IDLE";
            START:   state_str = "START";
            SEND_BYTE:  state_str = "SEND ";
            WAIT_ACK:   state_str = "WAIT ";
            RECV_BYTE:   state_str = "RECV ";
            SEND_ACK:   state_str = " ACK ";
            SEND_NACK:   state_str = "NACK ";
            STOP:   state_str = "STOP ";
            DONE:   state_str = "DONE ";
            default: state_str = "UNDEF";
        endcase
    end


endmodule
