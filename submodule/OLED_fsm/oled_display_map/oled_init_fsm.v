
module oled_init_fsm(clk, reset, busy, done, ack_err, oled_granted, oled_busy, oled_init_done, oled_req, start, stop, write, data_in, oled_err);
    input clk, reset;
    input busy, done, ack_err;
    input oled_granted;
    output oled_busy, oled_init_done;
    output reg oled_req;
    output reg start, stop, write;
    output reg [7:0] data_in;
    output oled_err;

    // oled 주소
    localparam OLED_ADDR = 8'h78;

    // FSM state 정의
    localparam S_IDLE                = 5'd0;
    localparam S_POWER_ON_WAIT       = 5'd1;
    localparam S_INIT_REQ            = 5'd2;
    localparam S_INIT_SEND_ADDR      = 5'd3;
    localparam S_INIT_WAIT_ADDR_ACK  = 5'd4;
    localparam S_INIT_SEND_CTRL_BYTE = 5'd5;
    localparam S_INIT_WAIT_CTRL_ACK  = 5'd6;
    localparam S_INIT_SEND_CMD_BYTE  = 5'd7;
    localparam S_INIT_WAIT_CMD_ACK   = 5'd8;
    localparam S_INIT_REQ_STOP       = 5'd9;
    localparam S_INIT_WAIT_STOP      = 5'd10;
    localparam S_READY               = 5'd11;
    localparam S_ERROR               = 5'd12;
    
    // 데이터 전송 state 
    localparam S_DATA_REQ_START      = 5'd13;
    localparam S_DATA_SEND_ADDR      = 5'd14;
    localparam S_DATA_WAIT_ADDR_ACK  = 5'd15;
    localparam S_DATA_SEND_CTRL_BYTE = 5'd16;
    localparam S_DATA_WAIT_CTRL_ACK  = 5'd17;
    localparam S_DATA_STREAM         = 5'd18;
    localparam S_DATA_STREAM_WAIT_ACK= 5'd19;
    localparam S_DATA_REQ_STOP       = 5'd20;
    localparam S_DATA_WAIT_STOP      = 5'd21;
    localparam S_DATA_END            = 5'd22;


    localparam POWER_ON_DELAY = 27'd5_000_000; // 50ms

    reg [4:0] state, next_state;
    reg [26:0] wait_counter;
    reg r_done;
    reg [4:0] cmd_ptr;
    reg [12:0] data_ptr;
    reg [7:0] data_from_rom;

    // 초기화 명령어 ROM
    localparam INIT_CMD_TOTAL = 26;
    reg [7:0] init_cmd_rom [0:INIT_CMD_TOTAL-1];
    initial begin
        init_cmd_rom[0]  = 8'hAE; init_cmd_rom[1]  = 8'hD5; init_cmd_rom[2]  = 8'h80;
        init_cmd_rom[3]  = 8'hA8; init_cmd_rom[4]  = 8'h3F; init_cmd_rom[5]  = 8'hD3;
        init_cmd_rom[6]  = 8'h00; init_cmd_rom[7]  = 8'h40; init_cmd_rom[8]  = 8'h8D;
        init_cmd_rom[9]  = 8'h14; init_cmd_rom[10] = 8'h20; init_cmd_rom[11] = 8'h00;
        init_cmd_rom[12] = 8'hA1; init_cmd_rom[13] = 8'hC8; init_cmd_rom[14] = 8'hDA;
        init_cmd_rom[15] = 8'h12; init_cmd_rom[16] = 8'h81; init_cmd_rom[17] = 8'hCF;
        init_cmd_rom[18] = 8'hD9; init_cmd_rom[19] = 8'hF1; init_cmd_rom[20] = 8'hDB;
        init_cmd_rom[21] = 8'h40; init_cmd_rom[22] = 8'hA4; init_cmd_rom[23] = 8'hA6;
        init_cmd_rom[24] = 8'h2E; init_cmd_rom[25] = 8'hAF;
    end

    // 맵 데이터 ROM
    localparam DATA_SIZE = 1024;
    reg [7:0] data_rom [0:DATA_SIZE-1];
    initial begin
        $readmemh("map_data.hex", data_rom);
    end

    // BRAM 파이프라인 레지스터
    always @(posedge clk) begin
        data_from_rom <= data_rom[data_ptr];
    end
    
    assign oled_busy = (state != S_READY && state != S_ERROR && state != S_DATA_END);
    assign oled_init_done = (state >= S_READY);
    assign oled_err = (state == S_ERROR);

    

    // Sequential Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            wait_counter <= 0;
            cmd_ptr <= 0;
            data_ptr <= 0;
            r_done <= 1'b0;
        end 
        else begin
            state <= next_state;

            if (done) r_done <= 1'b1;
            else if (next_state != state) r_done <= 1'b0;

            if (state == S_POWER_ON_WAIT) wait_counter <= wait_counter + 1;
            else if (next_state != state) wait_counter <= 0;

            if (state == S_INIT_WAIT_STOP && next_state == S_INIT_REQ) begin
                cmd_ptr <= cmd_ptr + 1;
            end

            // 데이터 포인터는 스트리밍 중에 증가
            if (state == S_DATA_STREAM_WAIT_ACK && next_state == S_DATA_STREAM) begin
                data_ptr <= data_ptr + 1;
            end
        end
    end

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:                next_state = S_POWER_ON_WAIT;
            S_POWER_ON_WAIT:       if (wait_counter >= POWER_ON_DELAY) next_state = S_INIT_REQ;

            // 초기화 
            S_INIT_REQ:            if (oled_granted) next_state = S_INIT_SEND_ADDR; else next_state = S_INIT_REQ;
            S_INIT_SEND_ADDR:      if (busy) next_state = S_INIT_WAIT_ADDR_ACK;
            S_INIT_WAIT_ADDR_ACK:  if (r_done) next_state = (ack_err) ? S_ERROR : S_INIT_SEND_CTRL_BYTE;
            S_INIT_SEND_CTRL_BYTE: if (busy) next_state = S_INIT_WAIT_CTRL_ACK;
            S_INIT_WAIT_CTRL_ACK:  if (r_done) next_state = (ack_err) ? S_ERROR : S_INIT_SEND_CMD_BYTE;
            S_INIT_SEND_CMD_BYTE:  if (done) next_state = S_INIT_WAIT_CMD_ACK;
            S_INIT_WAIT_CMD_ACK:   if (r_done) next_state = (ack_err) ? S_ERROR : S_INIT_REQ_STOP;
            S_INIT_REQ_STOP:       if (!busy) next_state = S_INIT_WAIT_STOP;
            S_INIT_WAIT_STOP:      if (r_done) begin
                                       if (cmd_ptr == INIT_CMD_TOTAL - 1) next_state = S_READY;
                                       else next_state = S_INIT_REQ;
                                   end
            
            //  데이터 스트리밍 
            S_READY:               next_state = S_DATA_REQ_START;
            
            S_DATA_REQ_START:      if (oled_granted) next_state = S_DATA_SEND_ADDR; else next_state = S_DATA_REQ_START;
            S_DATA_SEND_ADDR:      if (busy) next_state = S_DATA_WAIT_ADDR_ACK;
            S_DATA_WAIT_ADDR_ACK:  if (r_done) next_state = (ack_err) ? S_ERROR : S_DATA_SEND_CTRL_BYTE;
            S_DATA_SEND_CTRL_BYTE: if (busy) next_state = S_DATA_WAIT_CTRL_ACK;
            S_DATA_WAIT_CTRL_ACK:  if (r_done) next_state = (ack_err) ? S_ERROR : S_DATA_STREAM; // 스트림 시작
            
            S_DATA_STREAM:         if (busy) next_state = S_DATA_STREAM_WAIT_ACK;
            S_DATA_STREAM_WAIT_ACK:if (r_done) begin
                                       if (ack_err) begin
                                           next_state = S_ERROR;
                                       end else if (data_ptr == DATA_SIZE - 1) begin
                                           next_state = S_DATA_REQ_STOP; // 1024개 전송 완료
                                       end else begin
                                           next_state = S_DATA_STREAM; // 다음 바이트 전송
                                       end
                                   end
            
            S_DATA_REQ_STOP:       if (!busy) next_state = S_DATA_WAIT_STOP;
            S_DATA_WAIT_STOP:      if (r_done) next_state = S_DATA_END; // 통신 종료
            
            S_DATA_END:            next_state = S_DATA_END; // 작업 완료
            S_ERROR:               next_state = S_ERROR;




            default:               next_state = S_IDLE;
        endcase
    end
    
    // Output Logic
    always @(*) begin
        //oled_req = 1'b0;
        start = 1'b0;
        stop = 1'b0;
        write = 1'b0;
        //data_in = 8'h00;

        case (state)
            S_INIT_REQ:            oled_req = 1'b1;
            S_INIT_SEND_ADDR:      {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_INIT_SEND_CTRL_BYTE: {write, data_in} = {1'b1, 8'h00};
            S_INIT_SEND_CMD_BYTE:  {write, data_in} = {1'b1, init_cmd_rom[cmd_ptr]};
            S_INIT_REQ_STOP:       stop = 1'b1;

            S_DATA_REQ_START:      oled_req = 1'b1;
            S_DATA_SEND_ADDR:      {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_DATA_SEND_CTRL_BYTE: {write, data_in} = {1'b1, 8'h40};
            S_DATA_STREAM:         {write, data_in} = {1'b1, data_from_rom};
            S_DATA_REQ_STOP:       stop = 1'b1;
        endcase
    end

    reg [170:0] oled_state;

    always @(*) begin
        case (state)
            S_IDLE:                 oled_state = "           IDLE            ";
            S_POWER_ON_WAIT:        oled_state = "      POWER_ON_WAIT        ";
            S_INIT_REQ:             oled_state = "         INIT_REQ          ";
            S_INIT_SEND_ADDR:       oled_state = "     INIT_SEND_ADDR        ";
            S_INIT_WAIT_ADDR_ACK:   oled_state = "   INIT_WAIT_ADDR_ACK      ";
            S_INIT_SEND_CTRL_BYTE:  oled_state = "  INIT_SEND_CTRL_BYTE      ";
            S_INIT_WAIT_CTRL_ACK:   oled_state = "  INIT_WAIT_CTRL_ACK       ";
            S_INIT_SEND_CMD_BYTE:   oled_state = "  INIT_SEND_CMD_BYTE       ";
            S_INIT_WAIT_CMD_ACK:    oled_state = "  INIT_WAIT_CMD_ACK        ";
            S_INIT_REQ_STOP:        oled_state = "      INIT_REQ_STOP        ";
            S_INIT_WAIT_STOP:       oled_state = "     INIT_WAIT_STOP        ";
            S_READY:                oled_state = "           READY           ";
            S_ERROR:                oled_state = "           ERROR           ";

            // 데이터 전송 상태
            S_DATA_REQ_START:       oled_state = "     DATA_REQ_START        ";
            S_DATA_SEND_ADDR:       oled_state = "     DATA_SEND_ADDR        ";
            S_DATA_WAIT_ADDR_ACK:   oled_state = "   DATA_WAIT_ADDR_ACK      ";
            S_DATA_SEND_CTRL_BYTE:  oled_state = "  DATA_SEND_CTRL_BYTE      ";
            S_DATA_WAIT_CTRL_ACK:   oled_state = "  DATA_WAIT_CTRL_ACK       ";
            S_DATA_STREAM:          oled_state = "        DATA_STREAM        ";
            S_DATA_STREAM_WAIT_ACK: oled_state = " DATA_STREAM_WAIT_ACK      ";
            S_DATA_REQ_STOP:        oled_state = "      DATA_REQ_STOP        ";
            S_DATA_WAIT_STOP:       oled_state = "     DATA_WAIT_STOP        ";
            S_DATA_END:             oled_state = "         DATA_END          ";

            default:                oled_state = "        UNKNOWN_STATE       ";
        endcase
    end

endmodule



// module oled_init_fsm(clk, reset, busy, done, ack_err, oled_granted, oled_busy, oled_init_done, oled_req, start, stop, write, data_in, oled_err);
//     input clk, reset;
//     input busy, done, ack_err;
//     input oled_granted;
//     output oled_busy, oled_init_done;
//     output oled_req;
//     output reg start, stop, write;
//     output reg [7:0] data_in;
//     output oled_err;

//     // oled 주소
//     localparam OLED_ADDR = 8'h78;

//     // --- FSM state 정의 ---
//     // 초기화 상태
//     localparam [5:0] S_IDLE                 = 6'd0;
//     localparam [5:0] S_POWER_ON_WAIT        = 6'd1;
//     localparam [5:0] S_INIT_REQ             = 6'd2;
//     localparam [5:0] S_INIT_SEND_ADDR       = 6'd3;
//     localparam [5:0] S_INIT_WAIT_ADDR_ACK   = 6'd4;
//     localparam [5:0] S_INIT_SEND_CTRL_BYTE  = 6'd5;
//     localparam [5:0] S_INIT_WAIT_CTRL_ACK   = 6'd6;
//     localparam [5:0] S_INIT_SEND_CMD_BYTE   = 6'd7;
//     localparam [5:0] S_INIT_WAIT_CMD_ACK    = 6'd8;
//     localparam [5:0] S_INIT_REQ_STOP        = 6'd9;
//     localparam [5:0] S_INIT_WAIT_STOP       = 6'd10;
//     localparam [5:0] S_READY                = 6'd11; // 초기화 완료, 화면 채우기 시작
//     localparam [5:0] S_ERROR                = 6'd12;

//     // 화면 채우기(Fill) 상태 (명령어 트랜잭션)
//     localparam [5:0] S_FILL_REQ_CMD         = 6'd20;
//     localparam [5:0] S_FILL_SEND_ADDR_CMD   = 6'd21;
//     localparam [5:0] S_FILL_WAIT_ADDR_ACK_CMD = 6'd22;
//     localparam [5:0] S_FILL_SEND_CTRL_CMD   = 6'd23;
//     localparam [5:0] S_FILL_WAIT_CTRL_ACK_CMD = 6'd24;
//     localparam [5:0] S_FILL_SET_PAGE        = 6'd25;
//     localparam [5:0] S_FILL_WAIT_PAGE_ACK   = 6'd26;
//     localparam [5:0] S_FILL_SET_COL_L       = 6'd27;
//     localparam [5:0] S_FILL_WAIT_COL_L_ACK  = 6'd28;
//     localparam [5:0] S_FILL_SET_COL_H       = 6'd29;
//     localparam [5:0] S_FILL_WAIT_COL_H_ACK  = 6'd30;
//     localparam [5:0] S_FILL_STOP_CMD        = 6'd31;
//     localparam [5:0] S_FILL_WAIT_STOP_CMD   = 6'd32;

//     // 화면 채우기(Fill) 상태 (데이터 트랜잭션)
//     localparam [5:0] S_FILL_REQ_DATA        = 6'd40;
//     localparam [5:0] S_FILL_SEND_ADDR_DATA  = 6'd41;
//     localparam [5:0] S_FILL_WAIT_ADDR_ACK_DATA = 6'd42;
//     localparam [5:0] S_FILL_SEND_CTRL_DATA  = 6'd43;
//     localparam [5:0] S_FILL_WAIT_CTRL_ACK_DATA = 6'd44;
//     localparam [5:0] S_FILL_SEND_DATA       = 6'd45;
//     localparam [5:0] S_FILL_WAIT_DATA_ACK   = 6'd46;
//     localparam [5:0] S_FILL_STOP_DATA       = 6'd47;
//     localparam [5:0] S_FILL_WAIT_STOP_DATA  = 6'd48;
//     localparam [5:0] S_FILL_UPDATE_COUNTERS = 6'd49;


//     localparam POWER_ON_DELAY = 27'd5_000_000; // 100ms @ 50MHz

//     reg [5:0] state, next_state;
//     reg [26:0] wait_counter;
//     reg r_done;
    

//     assign oled_busy = (state != S_IDLE);
//     assign oled_req = oled_busy && oled_granted;


//     // 카운터
//     reg [4:0] init_cmd_ptr; // 초기화 명령어 포인터
//     reg [2:0] page_cnt;     // 페이지 카운터 (0~7)
//     reg [6:0] col_cnt;      // 컬럼 카운터 (0~127)

//     // 명령어 rom 저장
//     localparam INIT_CMD_TOTAL = 26;
//     reg [7:0] init_cmd_rom [0:INIT_CMD_TOTAL-1];
//     initial begin
//         init_cmd_rom[0]  = 8'hAE; init_cmd_rom[1]  = 8'hD5; init_cmd_rom[2]  = 8'h80;
//         init_cmd_rom[3]  = 8'hA8; init_cmd_rom[4]  = 8'h3F; init_cmd_rom[5]  = 8'hD3;
//         init_cmd_rom[6]  = 8'h00; init_cmd_rom[7]  = 8'h40; init_cmd_rom[8]  = 8'h8D;
//         init_cmd_rom[9]  = 8'h14; init_cmd_rom[10] = 8'h20; init_cmd_rom[11] = 8'h00; // 페이지 모드
//         init_cmd_rom[12] = 8'hA1; init_cmd_rom[13] = 8'hC8; init_cmd_rom[14] = 8'hDA;
//         init_cmd_rom[15] = 8'h12; init_cmd_rom[16] = 8'h81; init_cmd_rom[17] = 8'hCF;
//         init_cmd_rom[18] = 8'hD9; init_cmd_rom[19] = 8'hF1; init_cmd_rom[20] = 8'hDB;
//         init_cmd_rom[21] = 8'h40; init_cmd_rom[22] = 8'hA4; init_cmd_rom[23] = 8'hA6;
//         init_cmd_rom[24] = 8'h2E; init_cmd_rom[25] = 8'hAF; // Display ON
//     end

//     // output assign
//     assign oled_busy = (state != S_IDLE && state != S_ERROR);
//     assign oled_init_done = (state >= S_READY); // 초기화가 끝나면 1로 유지
//     assign oled_err = (state == S_ERROR);

//     // sequential logic
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             state <= S_IDLE;
//             wait_counter <= 0;
//             init_cmd_ptr <= 0;
//             page_cnt <= 0;
//             col_cnt <= 0;
//             r_done <= 1'b0;
//         end 
//         else begin
//             state <= next_state;

//             if (done) r_done <= 1'b1;
//             else if (next_state != state) r_done <= 1'b0;

//             if (state == S_POWER_ON_WAIT) begin
//                 wait_counter <= wait_counter + 1;
//             end else if (next_state != state) begin
//                 wait_counter <= 0;
//             end

//             // 카운터 업데이트 로직
//             if (next_state != state) begin
//                 if (state == S_INIT_WAIT_STOP) begin
//                     init_cmd_ptr <= init_cmd_ptr + 1;
//                 end else if (state == S_FILL_WAIT_DATA_ACK) begin
//                     col_cnt <= col_cnt + 1;
//                 end else if (state == S_FILL_UPDATE_COUNTERS) begin
//                     col_cnt <= 0; // 데이터 전송 완료 후 컬럼 카운터 리셋
//                     if (page_cnt == 3'd7) begin
//                         page_cnt <= 0; // 모든 페이지 완료 후 페이지 카운터 리셋
//                     end else begin
//                         page_cnt <= page_cnt + 1;
//                     end
//                 end
//             end
//         end
//     end

//     // combinational logic - Next State Logic
//     always @(*) begin
//         next_state = state;
//         case (state)
//             // --- 초기화 FSM ---
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
//                                         if (init_cmd_ptr == INIT_CMD_TOTAL - 1) next_state = S_READY;
//                                         else next_state = S_INIT_REQ;
//                                     end
//             S_READY:                next_state = S_FILL_REQ_CMD; // 초기화 끝나면 화면 채우기 시작
//             S_ERROR:                next_state = S_ERROR;

//             // --- 화면 채우기 FSM (명령어) ---
//             S_FILL_REQ_CMD:         if (oled_granted) next_state = S_FILL_SEND_ADDR_CMD;
//             S_FILL_SEND_ADDR_CMD:   if (busy) next_state = S_FILL_WAIT_ADDR_ACK_CMD;
//             S_FILL_WAIT_ADDR_ACK_CMD: if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_SEND_CTRL_CMD;
//             S_FILL_SEND_CTRL_CMD:   if (busy) next_state = S_FILL_WAIT_CTRL_ACK_CMD;
//             S_FILL_WAIT_CTRL_ACK_CMD: if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_SET_PAGE;
//             S_FILL_SET_PAGE:        if (busy) next_state = S_FILL_WAIT_PAGE_ACK;
//             S_FILL_WAIT_PAGE_ACK:   if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_SET_COL_L;
//             S_FILL_SET_COL_L:       if (busy) next_state = S_FILL_WAIT_COL_L_ACK;
//             S_FILL_WAIT_COL_L_ACK:  if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_SET_COL_H;
//             S_FILL_SET_COL_H:       if (busy) next_state = S_FILL_WAIT_COL_H_ACK;
//             S_FILL_WAIT_COL_H_ACK:  if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_STOP_CMD;
//             S_FILL_STOP_CMD:        if (!busy) next_state = S_FILL_WAIT_STOP_CMD;
//             S_FILL_WAIT_STOP_CMD:   if (r_done) next_state = S_FILL_REQ_DATA; // 명령어 전송 후 데이터 전송 요청

//             // --- 화면 채우기 FSM (데이터) ---
//             S_FILL_REQ_DATA:        if (oled_granted) next_state = S_FILL_SEND_ADDR_DATA;
//             S_FILL_SEND_ADDR_DATA:  if (busy) next_state = S_FILL_WAIT_ADDR_ACK_DATA;
//             S_FILL_WAIT_ADDR_ACK_DATA: if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_SEND_CTRL_DATA;
//             S_FILL_SEND_CTRL_DATA:  if (busy) next_state = S_FILL_WAIT_CTRL_ACK_DATA;
//             S_FILL_WAIT_CTRL_ACK_DATA: if (r_done) next_state = (ack_err) ? S_ERROR : S_FILL_SEND_DATA;
//             S_FILL_SEND_DATA:       if (busy) next_state = S_FILL_WAIT_DATA_ACK;
//             S_FILL_WAIT_DATA_ACK:   if (r_done) begin
//                                         if (ack_err) next_state = S_ERROR;
//                                         else if (col_cnt == 7'd127) next_state = S_FILL_STOP_DATA; // 128개 전송 완료
//                                         else next_state = S_FILL_SEND_DATA;
//                                     end
//             S_FILL_STOP_DATA:       if (!busy) next_state = S_FILL_WAIT_STOP_DATA;
//             S_FILL_WAIT_STOP_DATA:  if (r_done) next_state = S_FILL_UPDATE_COUNTERS;
//             S_FILL_UPDATE_COUNTERS: next_state = S_FILL_REQ_CMD; // 다음 페이지 그리러 가기 (무한 반복)
            
//             default:                next_state = S_IDLE;
//         endcase
//     end
    
//     // Combinational logic - Output logic
//     always @(*) begin
//         //oled_req = 1'b0;
//         start = 1'b0;
//         stop = 1'b0;
//         write = 1'b0;
//         data_in = 8'h00;

//         // // I2C 버스 요청 로직
//         // case (state) 
//         //     S_INIT_REQ, S_FILL_REQ_CMD, S_FILL_REQ_DATA:
//         //         oled_req = 1'b1;
//         //     default:
//         //         oled_req = 1'b0;
//         // endcase

//         // I2C 신호 및 데이터 출력 로직
//         case (state)
//             // 초기화
//             S_INIT_SEND_ADDR:       {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
//             S_INIT_SEND_CTRL_BYTE:  {write, data_in} = {1'b1, 8'h00};
//             S_INIT_SEND_CMD_BYTE:   {write, data_in} = {1'b1, init_cmd_rom[init_cmd_ptr]};
//             S_INIT_REQ_STOP:        stop = 1'b1;
            
//             // 화면 채우기 (명령어)
//             S_FILL_SEND_ADDR_CMD:   {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
//             S_FILL_SEND_CTRL_CMD:   {write, data_in} = {1'b1, 8'h00}; // Command Control Byte
//             S_FILL_SET_PAGE:        {write, data_in} = {1'b1, 8'hB0 | page_cnt};
//             S_FILL_SET_COL_L:       {write, data_in} = {1'b1, 8'h00};
//             S_FILL_SET_COL_H:       {write, data_in} = {1'b1, 8'h10};
//             S_FILL_STOP_CMD:        stop = 1'b1;

//             // 화면 채우기 (데이터)
//             S_FILL_SEND_ADDR_DATA:  {start, write, data_in} = {1'b1, 1'b1, OLED_ADDR};
//             S_FILL_SEND_CTRL_DATA:  {write, data_in} = {1'b1, 8'h40}; // Data Control Byte
//             S_FILL_SEND_DATA:       {write, data_in} = {1'b1, 8'hFF}; // 화면을 채울 데이터
//             S_FILL_STOP_DATA:       stop = 1'b1;
//         endcase
//     end

// endmodule
