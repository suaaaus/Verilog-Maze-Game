module OLED_fsm(clk, reset, busy, done, ack_err, oled_granted, oled_busy, oled_init_done, oled_req, start, stop, write, data_in, oled_err);
    input clk, reset;
    input busy, done, ack_err;
    input oled_granted;
    output oled_busy, oled_init_done;
    output reg oled_req;
    output reg start, stop, write;
    output reg [7:0] data_in;
    output oled_err;

    // oled slave (SSD1306)의 addr
    localparam OLED_ADDR = 8'h78;

    // FSM state :
    localparam S_IDLE                 = 5'd0;
    localparam S_POWER_ON_WAIT        = 5'd1;

    // 초기화를 3단계로 나눔 ( charge pump 때 딜레이 주기 위함)
    // initial sequence 1
    localparam S_INIT1_REQ            = 5'd2;
    localparam S_INIT1_SEND_ADDR      = 5'd3;
    localparam S_INIT1_WAIT_ADDR_ACK  = 5'd4;
    localparam S_INIT1_SEND_BYTE      = 5'd5;
    localparam S_INIT1_WAIT_BYTE_ACK  = 5'd6;
    localparam S_INIT1_REQ_STOP       = 5'd7;
    localparam S_INIT1_WAIT_STOP      = 5'd8;
    localparam S_INIT_DELAY1_WAIT     = 5'd9;

    // initial sequence 2
    localparam S_INIT2_REQ            = 5'd10;
    localparam S_INIT2_SEND_ADDR      = 5'd11;
    localparam S_INIT2_WAIT_ADDR_ACK  = 5'd12;
    localparam S_INIT2_SEND_BYTE      = 5'd13;
    localparam S_INIT2_WAIT_BYTE_ACK  = 5'd14;
    localparam S_INIT2_REQ_STOP       = 5'd15;
    localparam S_INIT2_WAIT_STOP      = 5'd16;
    localparam S_INIT_DELAY2_WAIT     = 5'd17;

    // initial sequence 3
    localparam S_INIT3_REQ            = 5'd18;
    localparam S_INIT3_SEND_ADDR      = 5'd19;
    localparam S_INIT3_WAIT_ADDR_ACK  = 5'd20;
    localparam S_INIT3_SEND_BYTE      = 5'd21;
    localparam S_INIT3_WAIT_BYTE_ACK  = 5'd22;
    localparam S_INIT3_REQ_STOP       = 5'd23;
    localparam S_INIT3_WAIT_STOP      = 5'd24;

    localparam S_READY                = 5'd25;
    localparam S_ERROR                = 5'd26; // 에러 발생 시 재전송 로직???

    // delay parameter
    localparam WAIT_10MS  = 27'd1_000_000;
    localparam WAIT_100MS = 27'd10_000_000;
    localparam POWER_ON_DELAY = 27'd5_000_000;

    reg [4:0] state, next_state;
    reg [26:0] wait_counter;
    reg r_done; // 명령어 래칭
    reg [4:0] cmd_ptr;
    reg [1:0] retry_cnt; // 재시도 counter 00 01 10 11 -- 3번까지

    // initial sequence 마다 명령어 몇개
    localparam SEQ1_LEN = 15;
    localparam SEQ2_LEN = 2;
    localparam SEQ3_LEN = 1;

    reg [7:0] init_cmd_rom [0:SEQ1_LEN+SEQ2_LEN+SEQ3_LEN-1];

    initial begin
        // initial sequence 1
        init_cmd_rom[0]  = 8'hA8; init_cmd_rom[1]  = 8'h3F; 
        init_cmd_rom[2]  = 8'hD3; init_cmd_rom[3]  = 8'h00; 
        init_cmd_rom[4]  = 8'h40; init_cmd_rom[5]  = 8'hA1; init_cmd_rom[6]  = 8'hC8; init_cmd_rom[7]  = 8'hDA; 
        init_cmd_rom[8]  = 8'h12; init_cmd_rom[9] = 8'h81; init_cmd_rom[10] = 8'h7F;
        init_cmd_rom[11] = 8'hA4; init_cmd_rom[12] = 8'hA6; init_cmd_rom[13] = 8'hD5; 
        init_cmd_rom[14] = 8'h80; 
        // initial sequence 2
        init_cmd_rom[15] = 8'h8D; init_cmd_rom[16] = 8'h14;
        // initial sequence 3
        init_cmd_rom[17] = 8'hAF;
    end

    // output 그냥 assign
    assign oled_busy = (state != S_READY && state != S_ERROR);
    assign oled_init_done = (state == S_READY);
    assign oled_err = (state == S_ERROR);

    // Sequential Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            wait_counter <= 0;
            cmd_ptr <= 0;
            r_done <= 1'b0;
            retry_cnt <= 0;
        end else begin
            state <= next_state;

            // done 명령어 래칭
            if (done) begin
                r_done <= 1'b1;
            end 
            else if (next_state != state) begin // 상태가 변경되면 무조건 클리어
                r_done <= 1'b0;
            end

            // delay counter
            if (state == S_POWER_ON_WAIT || state == S_INIT_DELAY1_WAIT || state == S_INIT_DELAY2_WAIT) begin
                wait_counter <= wait_counter + 1;
            end 
            else if (next_state != state) begin
                wait_counter <= 0;
            end
            
            // cmd_ptr 업데이트
            if ((state == S_INIT1_WAIT_BYTE_ACK && next_state == S_INIT1_SEND_BYTE) ||
                (state == S_INIT2_WAIT_BYTE_ACK && next_state == S_INIT2_SEND_BYTE) ||
                (state == S_INIT3_WAIT_BYTE_ACK && next_state == S_INIT3_SEND_BYTE)) begin
                cmd_ptr <= cmd_ptr + 1;
            end

            // state 변하면 cmd_ptr reset
            if ((state == S_IDLE && next_state == S_POWER_ON_WAIT) ||
                (state == S_INIT1_WAIT_STOP && next_state == S_INIT_DELAY1_WAIT) ||
                (state == S_INIT2_WAIT_STOP && next_state == S_INIT_DELAY2_WAIT)) begin
                cmd_ptr <= 0;
            end

            // 재시도 카운터 업데이트 
            // 1. 성공 시 리셋
            if (r_done && !ack_err) begin
                retry_cnt <= 0;
            end
            // 2. 에러 시 증가
            else if (r_done && ack_err && retry_cnt < 3) begin
                retry_cnt <= retry_cnt + 1;
            end

        end
    end

    // FSM Combinational - Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:         next_state = S_POWER_ON_WAIT;
            S_POWER_ON_WAIT:    if (wait_counter >= POWER_ON_DELAY) next_state = S_INIT1_REQ;

            // initial sequence 1
            S_INIT1_REQ:        if (oled_granted) next_state = S_INIT1_SEND_ADDR;
            S_INIT1_SEND_ADDR:  if (busy) next_state = S_INIT1_WAIT_ADDR_ACK;
                                else next_state = S_INIT1_SEND_ADDR;
            S_INIT1_WAIT_ADDR_ACK: /*if (r_done && !ack_err)
                                    next_state = S_INIT1_SEND_BYTE;
                                else if (ack_err) next_state = S_ERROR;*/
                                if (r_done) begin // 작업이 끝나면 
                                    if (!ack_err) begin // 성공했다면
                                        next_state = S_INIT1_SEND_BYTE;
                                    end 
                                    else begin // 실패했다면
                                        if (retry_cnt < 3) next_state = S_INIT1_REQ; // 재시도
                                        else next_state = S_ERROR;                   // 최종 실패
                                    end
                                end
            S_INIT1_SEND_BYTE:  if (done) next_state = S_INIT1_WAIT_BYTE_ACK;
                                else next_state = S_INIT1_SEND_BYTE;
            S_INIT1_WAIT_BYTE_ACK: /*if (r_done && !ack_err) begin
                                        if (cmd_ptr < SEQ1_LEN + 1 -1) next_state = S_INIT1_SEND_BYTE;
                                        else next_state = S_INIT1_REQ_STOP;
                                    end
                                    else if (ack_err) next_state = S_ERROR;*/
                                    if (r_done) begin // 작업이 끝나면
                                        if (!ack_err) begin // 성공했다면
                                            if (cmd_ptr < SEQ1_LEN) next_state = S_INIT1_SEND_BYTE;
                                            else next_state = S_INIT1_REQ_STOP; // 바로 다음 딜레이 상태로!
                                        end else begin // 실패했다면
                                            if (retry_cnt < 3) next_state = S_INIT1_REQ; // 재시도
                                            else next_state = S_ERROR;                    // 최종 실패
                                        end
                                    end
            S_INIT1_REQ_STOP:    if (!busy) next_state = S_INIT1_WAIT_STOP;
                                 else next_state = S_INIT1_REQ_STOP;
            S_INIT1_WAIT_STOP:   if (r_done && !busy) next_state = S_INIT_DELAY1_WAIT;
                    
            // delay 1
            S_INIT_DELAY1_WAIT:     if (wait_counter >= WAIT_10MS) next_state = S_INIT2_REQ;

            // initial sequence 2
            S_INIT2_REQ:            if (oled_granted) next_state = S_INIT2_SEND_ADDR;
            S_INIT2_SEND_ADDR:      if (busy) next_state = S_INIT2_WAIT_ADDR_ACK;
                                    else next_state = S_INIT2_SEND_ADDR;
            S_INIT2_WAIT_ADDR_ACK:  if (r_done) begin // 작업이 끝나면 
                                        if (!ack_err) begin // 성공했다면
                                            next_state = S_INIT2_SEND_BYTE;
                                        end 
                                        else begin // 실패했다면
                                            if (retry_cnt < 3) next_state = S_INIT2_REQ; // 재시도
                                            else next_state = S_ERROR;                   // 최종 실패
                                        end
                                    end
            S_INIT2_SEND_BYTE:      if (done) next_state = S_INIT2_WAIT_BYTE_ACK;
                                    else next_state = S_INIT2_SEND_BYTE;
            S_INIT2_WAIT_BYTE_ACK:  if (r_done) begin // 작업이 끝나면
                                        if (!ack_err) begin // 성공했다면
                                            if (cmd_ptr < SEQ2_LEN) next_state = S_INIT2_SEND_BYTE;
                                            else next_state = S_INIT2_REQ_STOP; // 바로 다음 딜레이 상태로!
                                        end 
                                        else begin // 실패했다면
                                            if (retry_cnt < 3) next_state = S_INIT2_REQ; // 재시도
                                            else next_state = S_ERROR;                    // 최종 실패
                                        end
                                    end
                                    
            S_INIT2_REQ_STOP:       if (!busy) next_state = S_INIT2_WAIT_STOP;
            S_INIT2_WAIT_STOP:      if (r_done && !busy) next_state = S_INIT_DELAY2_WAIT;

            // delay 2
            S_INIT_DELAY2_WAIT:     if (wait_counter >= WAIT_100MS) next_state = S_INIT3_REQ;

            // initial sequence 3
            S_INIT3_REQ:            if (oled_granted) next_state = S_INIT3_SEND_ADDR;
            S_INIT3_SEND_ADDR:      if (busy) next_state = S_INIT3_WAIT_ADDR_ACK;
                                    else next_state = S_INIT3_SEND_ADDR;
            S_INIT3_WAIT_ADDR_ACK:  if (r_done) begin // 작업이 끝나면 
                                        if (!ack_err) begin // 성공했다면
                                            next_state = S_INIT3_SEND_BYTE;
                                        end 
                                        else begin // 실패했다면
                                            if (retry_cnt < 3) next_state = S_INIT3_REQ; // 재시도
                                            else next_state = S_ERROR;                   // 최종 실패
                                        end
                                    end
            S_INIT3_SEND_BYTE:      if (done) next_state = S_INIT3_WAIT_BYTE_ACK;
                                    else next_state = S_INIT3_SEND_BYTE;
            S_INIT3_WAIT_BYTE_ACK:  if (r_done) begin // 작업이 끝나면
                                        if (!ack_err) begin // 성공했다면
                                            if (cmd_ptr < SEQ3_LEN) next_state = S_INIT3_SEND_BYTE;
                                            else next_state = S_INIT3_REQ_STOP; 
                                        end 
                                        else begin // 실패했다면
                                            if (retry_cnt < 3) next_state = S_INIT3_REQ; // 재시도
                                            else next_state = S_ERROR;                    // 최종 실패
                                        end
                                    end
            S_INIT3_REQ_STOP:       if (!busy) next_state = S_INIT3_WAIT_STOP;
            S_INIT3_WAIT_STOP:      if (r_done && !busy) next_state = S_READY;

            S_READY:                next_state = S_READY;
            S_ERROR:                next_state = S_ERROR; // 에러 발생 시 멈춤
            default:                next_state = S_IDLE;
        endcase
    end
    
    // FSM Combinational - Output Logic
    always @(*) begin
        oled_req = 1'b0;
        start = 1'b0;
        stop = 1'b0;
        write = 1'b0;
        data_in = 8'h00;

        case (state)
            // initial sequence 1
            S_INIT1_REQ:       oled_req = 1'b1;
            S_INIT1_SEND_ADDR: {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_INIT1_SEND_BYTE: begin
                                 write = 1'b1;
                                 if (cmd_ptr == 0) data_in = 8'h00; // Control Byte
                                 else data_in = init_cmd_rom[cmd_ptr - 1];
                               end
            S_INIT1_REQ_STOP:  stop = 1'b1;
            
            // initial sequence 2
            S_INIT2_REQ:       oled_req = 1'b1;
            S_INIT2_SEND_ADDR: {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_INIT2_SEND_BYTE: begin
                                 write = 1'b1;
                                 if (cmd_ptr == 0) data_in = 8'h00; // Control Byte
                                 else data_in = init_cmd_rom[cmd_ptr - 1 + SEQ1_LEN];
                               end
            S_INIT2_REQ_STOP:  stop = 1'b1;
            
            // initial sequence 3
            S_INIT3_REQ:       oled_req = 1'b1;
            S_INIT3_SEND_ADDR: {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_INIT3_SEND_BYTE: begin
                                 write = 1'b1;
                                 if (cmd_ptr == 0) data_in = 8'h00; // 단일 명령어니까 0!! Control Byte
                                 else data_in = init_cmd_rom[cmd_ptr - 1 + SEQ1_LEN + SEQ2_LEN];
                               end
            S_INIT3_REQ_STOP:  stop = 1'b1;
        endcase
    end

    reg [170:0] oled_state;
    always @(*) begin
        case (state) 
            S_IDLE:                 oled_state = "      IDLE   ";
            S_POWER_ON_WAIT:        oled_state = "POWER_ON_WAIT";

            S_INIT1_REQ:            oled_state = "   INIT1_REQ    ";
            S_INIT1_SEND_ADDR:      oled_state = "INIT1_SEND_ADDR   ";
            S_INIT1_WAIT_ADDR_ACK:  oled_state = "INIT1_WAIT_ADDR_ACK";
            S_INIT1_SEND_BYTE:      oled_state = "INIT1_SEND_BYTE   ";
            S_INIT1_WAIT_BYTE_ACK:  oled_state = "INIT1_WAIT_BYTE_ACK";
            S_INIT1_REQ_STOP:       oled_state = "INIT1_REQ_STOP   ";
            S_INIT1_WAIT_STOP:      oled_state = "INIT1_WAIT_STOP   ";
            S_INIT_DELAY1_WAIT:     oled_state = "INIT_DELAY1_WAIT   ";

            S_INIT2_REQ:            oled_state = "    INIT2_REQ    ";
            S_INIT2_SEND_ADDR:      oled_state = "INIT2_SEND_ADDR  ";
            S_INIT2_WAIT_ADDR_ACK:  oled_state = "INIT2_WAIT_ADDR_ACK";
            S_INIT2_SEND_BYTE:      oled_state = "INIT2_SEND_BYTE  ";
            S_INIT2_WAIT_BYTE_ACK:  oled_state = "INIT2_WAIT_BYTE_ACK";
            S_INIT2_REQ_STOP:       oled_state = "INIT2_REQ_STOP  ";
            S_INIT2_WAIT_STOP:      oled_state = "INIT2_WAIT_STOP  ";
            S_INIT_DELAY2_WAIT:     oled_state = "INIT_DELAY2_WAIT";

            S_INIT3_REQ:            oled_state = "INIT3_REQ   ";
            S_INIT3_SEND_ADDR:      oled_state = "INIT3_SEND_ADDR";
            S_INIT3_WAIT_ADDR_ACK:  oled_state = "INIT3_WAIT_ADDR_ACK";
            S_INIT3_SEND_BYTE:      oled_state = "INIT3_SEND_BYTE";
            S_INIT3_WAIT_BYTE_ACK:  oled_state = "INIT3_WAIT_BYTE_ACK";
            S_INIT3_REQ_STOP:       oled_state = "INIT3_REQ_STOP";
            S_INIT3_WAIT_STOP:      oled_state = "INIT3_WAIT_STOP";

            S_READY:                oled_state = "READY";
            S_ERROR:                oled_state = "ERROR"; // 에러 발생 시 멈춤 상태

            default:              oled_state = "    UNDEF    ";
        endcase
    end

endmodule


//  // oled 주소
//     localparam OLED_ADDR = 8'h78;

//     // FSM state 정의
//     localparam S_IDLE                 = 4'd0;
//     localparam S_POWER_ON_WAIT        = 4'd1;
//     localparam S_INIT_REQ             = 4'd2;
//     localparam S_INIT_SEND_ADDR       = 4'd3;
//     localparam S_INIT_WAIT_ADDR_ACK   = 4'd4;
//     localparam S_INIT_SEND_CTRL_BYTE  = 4'd5;
//     localparam S_INIT_WAIT_CTRL_ACK   = 4'd6;
//     localparam S_INIT_SEND_CMD_BYTE   = 4'd7;
//     localparam S_INIT_WAIT_CMD_ACK    = 4'd8;
//     localparam S_INIT_REQ_STOP        = 4'd9;
//     localparam S_INIT_WAIT_STOP       = 4'd10;
//     localparam S_READY                = 4'd11;
//     localparam S_ERROR                = 4'd12;

//     localparam POWER_ON_DELAY = 27'd5_000_000; // 50ms

//     reg [3:0] state, next_state;
//     reg [26:0] wait_counter;
//     reg r_done;
//     reg [4:0] cmd_ptr; / 명령어 index 포인터

//     // 명령어 rom 저장
//     localparam INIT_CMD_TOTAL = 26;
//     reg [7:0] init_cmd_rom [0:INIT_CMD_TOTAL-1];
//     initial begin
//         init_cmd_rom[0]  = 8'hAE; init_cmd_rom[1]  = 8'hD5; init_cmd_rom[2]  = 8'h80;
//         init_cmd_rom[3]  = 8'hA8; init_cmd_rom[4]  = 8'h3F; init_cmd_rom[5]  = 8'hD3;
//         init_cmd_rom[6]  = 8'h00; init_cmd_rom[7]  = 8'h40; init_cmd_rom[8]  = 8'h8D;
//         init_cmd_rom[9]  = 8'h14; init_cmd_rom[10] = 8'h20; init_cmd_rom[11] = 8'h00;
//         init_cmd_rom[12] = 8'hA1; init_cmd_rom[13] = 8'hC8; init_cmd_rom[14] = 8'hDA;
//         init_cmd_rom[15] = 8'h12; init_cmd_rom[16] = 8'h81; init_cmd_rom[17] = 8'hCF;
//         init_cmd_rom[18] = 8'hD9; init_cmd_rom[19] = 8'hF1; init_cmd_rom[20] = 8'hDB;
//         init_cmd_rom[21] = 8'h40; init_cmd_rom[22] = 8'hA4; init_cmd_rom[23] = 8'hA6;
//         init_cmd_rom[24] = 8'h2E; init_cmd_rom[25] = 8'hAF;
//     end

//     // output assign
//     assign oled_busy = (state != S_READY && state != S_ERROR);
//     assign oled_init_done = (state == S_READY);
//     assign oled_err = (state == S_ERROR);

//     // sequential logic
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             state <= S_IDLE;
//             wait_counter <= 0;
//             cmd_ptr <= 0;
//             r_done <= 1'b0;
//         end else begin
//             state <= next_state;

//             if (done) r_done <= 1'b1;
//             else if (next_state != state) r_done <= 1'b0;

//             if (state == S_POWER_ON_WAIT) wait_counter <= wait_counter + 1;
//             else if (next_state != state) wait_counter <= 0;

//             if (state == S_INIT_WAIT_STOP && next_state == S_INIT_REQ) begin
//                 cmd_ptr <= cmd_ptr + 1;
//             end
//         end
//     end

//     // combinational logic - Next State Logic
//     always @(*) begin
//         next_state = state;
//         case (state)
//             S_IDLE:                 next_state = S_POWER_ON_WAIT;
//             S_POWER_ON_WAIT:        if (wait_counter >= POWER_ON_DELAY) next_state = S_INIT_REQ;

//             S_INIT_REQ:             if (oled_granted) next_state = S_INIT_SEND_ADDR;
//             S_INIT_SEND_ADDR:       if (busy) next_state = S_INIT_WAIT_ADDR_ACK;
//             S_INIT_WAIT_ADDR_ACK:   if (r_done) next_state = (ack_err) ? S_ERROR : S_INIT_SEND_CTRL_BYTE;
            
//             S_INIT_SEND_CTRL_BYTE:  if (busy) next_state = S_INIT_WAIT_CTRL_ACK;
//             S_INIT_WAIT_CTRL_ACK:   if (r_done) next_state = (ack_err) ? S_ERROR : S_INIT_SEND_CMD_BYTE;

//             S_INIT_SEND_CMD_BYTE:   if (done) next_state = S_INIT_WAIT_CMD_ACK;
//             S_INIT_WAIT_CMD_ACK:    if (r_done) next_state = (ack_err) ? S_ERROR : S_INIT_REQ_STOP;

//             S_INIT_REQ_STOP:        if (!busy) next_state = S_INIT_WAIT_STOP;
//             S_INIT_WAIT_STOP:       if (r_done) begin
//                                         if (cmd_ptr == INIT_CMD_TOTAL - 1) next_state = S_READY;
//                                         else next_state = S_INIT_REQ;
//                                     end
            
//             S_READY:                next_state = S_READY;
//             S_ERROR:                next_state = S_ERROR;
//             default:                next_state = S_IDLE;
//         endcase
//     end
    
//     // Combinational logic - Output logic
//         always @(*) begin
//         oled_req = 1'b0;
//         start = 1'b0;
//         stop = 1'b0;
//         write = 1'b0;
//         data_in = 8'h00;

//         case (state)
//             S_INIT_REQ:             oled_req = 1'b1;
//             S_INIT_SEND_ADDR:       {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
//             S_INIT_SEND_CTRL_BYTE:  {write, data_in} = {1'b1, 8'h00}; // 항상 단일 명령어
//             S_INIT_SEND_CMD_BYTE:   {write, data_in} = {1'b1, init_cmd_rom[cmd_ptr]};
//             S_INIT_REQ_STOP:        stop = 1'b1;
//         endcase
//     end

//     reg [153:0] oled_state;

//     always @(*) begin
//         case (state)
//             S_IDLE:                 oled_state = "        IDLE        ";
//             S_POWER_ON_WAIT:        oled_state = "   POWER_ON_WAIT    ";
//             S_INIT_REQ:             oled_state = "      INIT_REQ      ";
//             S_INIT_SEND_ADDR:       oled_state = "   INIT_SEND_ADDR   ";
//             S_INIT_WAIT_ADDR_ACK:   oled_state = "INIT_WAIT_ADDR_ACK ";
//             S_INIT_SEND_CTRL_BYTE:  oled_state = "INIT_SEND_CTRL_BYTE";
//             S_INIT_WAIT_CTRL_ACK:   oled_state = "INIT_WAIT_CTRL_ACK ";
//             S_INIT_SEND_CMD_BYTE:   oled_state = " INIT_SEND_CMD_BYTE";
//             S_INIT_WAIT_CMD_ACK:    oled_state = " INIT_WAIT_CMD_ACK ";
//             S_INIT_REQ_STOP:        oled_state = "    INIT_REQ_STOP   ";
//             S_INIT_WAIT_STOP:       oled_state = "   INIT_WAIT_STOP   ";
//             S_READY:                oled_state = "       READY        ";
//             S_ERROR:                oled_state = "       ERROR        ";
//             default:                oled_state = "       UNKNOWN        ";
//         endcase
//     end

// endmodule