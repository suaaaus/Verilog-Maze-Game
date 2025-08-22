// module oled_map_display_controller(
//     clk, reset, draw_map_req, i2c_done, oled_granted, map_busy, 
//     oled_req, i2c_start, i2c_stop, i2c_write, i2c_data_in, i2c_busy
// );

    
    
//     // --- Port Declarations ---
//     input clk, reset;
//     input draw_map_req;
//     input i2c_done;
//     input oled_granted;
//     input i2c_busy;
//     output map_busy;
//     output oled_req;
//     output reg i2c_start, i2c_stop, i2c_write;
//     output reg [7:0] i2c_data_in;

//     // --- Parameters ---
//     localparam OLED_ADDR = 8'h78;

//     // FSM state
//     localparam S_IDLE                 = 5'd0;
//     localparam S_WAIT_FOR_GRANT       = 5'd1;
//     localparam S_START_TX             = 5'd2;
//     localparam S_WAIT_ADDR_ACK        = 5'd3;
//     localparam S_SEND_CMD_CTRL        = 5'd4; // 명령어용 Control Byte(0x00) 전송 상태
//     localparam S_WAIT_CMD_CTRL_ACK    = 5'd5;
//     localparam S_SET_PAGE             = 5'd6;
//     localparam S_WAIT_PAGE_ACK        = 5'd7;
//     localparam S_SET_COL_LOW          = 5'd8;
//     localparam S_WAIT_COL_L_ACK       = 5'd9;
//     localparam S_SET_COL_HIGH         = 5'd10;
//     localparam S_WAIT_COL_H_ACK       = 5'd11;
//     localparam S_SEND_DATA_CTRL       = 5'd12; // 데이터용 Control Byte(0x40) 전송 상태 (기존 SEND_DATA_HEADER)
//     localparam S_WAIT_DATA_CTRL_ACK   = 5'd13;
//     localparam S_SEND_DATA_LOOP       = 5'd14;
//     localparam S_WAIT_DATA_ACK        = 5'd15;
//     localparam S_CHECK_PAGE_DONE      = 5'd16;
//     localparam S_STOP_TX              = 5'd17;
//     localparam S_WAIT_STOP_DONE       = 5'd18;
//     localparam S_MAP_DONE = 5'd19;

//     reg [4:0] state, next_state;

//     assign map_busy = (state != S_IDLE);
//     assign oled_req = map_busy && draw_map_req;

//     // 카운터 및 ROM 연결
//     reg [3:0] page_cnt;
//     reg [6:0] col_cnt;
//     wire [9:0] rom_addr;
//     wire [7:0] rom_data;
//     reg r_done;

//     assign rom_addr = {page_cnt, col_cnt};

//     maze_map_rom u_map_rom (
//         .addr(rom_addr),
//         .data(rom_data)
//     );

//     // --- Sequential Logic ---
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             state <= S_IDLE;
//             page_cnt <= 0;
//             col_cnt <= 0;
//             r_done <= 0;
//         end 
//         else begin
//             state <= next_state;

//             if (i2c_done) r_done <= 1'b1;
//             else if (next_state != state) r_done <= 1'b0;
            
//             if (next_state != state) begin
//                 case(state)
//                     S_WAIT_DATA_ACK: begin
//                         if (col_cnt == 7'd127) col_cnt <= 0;
//                         else col_cnt <= col_cnt + 1;
//                     end
//                     S_CHECK_PAGE_DONE:
//                         page_cnt <= page_cnt + 1;
//                 endcase
//             end
            
//             if(state == S_IDLE && next_state == S_WAIT_FOR_GRANT) begin
//                 page_cnt <= 0;
//                 col_cnt <= 0;
//             end
//         end
//     end

//     // --- Combinational Logic 1: Next State Logic ---
//     always @(*) begin
//         next_state = state; // 기본적으로 현재 상태 유지
//         case (state)
//             S_IDLE:                 if (draw_map_req) next_state = S_WAIT_FOR_GRANT;
//             S_WAIT_FOR_GRANT:       if (oled_granted) next_state = S_START_TX;
//             S_START_TX:             if (i2c_busy) next_state = S_WAIT_ADDR_ACK;
//             S_WAIT_ADDR_ACK:        if (r_done) next_state = S_SEND_CMD_CTRL; // 주소 전송 후, 명령어 Control Byte 전송으로
            
//             S_SEND_CMD_CTRL:        if (i2c_busy) next_state = S_WAIT_CMD_CTRL_ACK;
//             S_WAIT_CMD_CTRL_ACK:    if (r_done) next_state = S_SET_PAGE; // 첫번째 명령어(페이지 설정)로

//             S_SET_PAGE:             if (i2c_busy) next_state = S_WAIT_PAGE_ACK;
//             S_WAIT_PAGE_ACK:        if (r_done) next_state = S_SET_COL_LOW; // 다음 명령어(컬럼 설정)로

//             S_SET_COL_LOW:          if (i2c_busy) next_state = S_WAIT_COL_L_ACK;
//             S_WAIT_COL_L_ACK:       if (r_done) next_state = S_SET_COL_HIGH; // 다음 명령어(컬럼 설정)로

//             S_SET_COL_HIGH:         if (i2c_busy) next_state = S_WAIT_COL_H_ACK;
//             S_WAIT_COL_H_ACK:       if (r_done) next_state = S_SEND_DATA_CTRL; // 모든 좌표 설정 후, 데이터 Control Byte 전송으로

//             S_SEND_DATA_CTRL:       if (i2c_busy) next_state = S_WAIT_DATA_CTRL_ACK;
//             S_WAIT_DATA_CTRL_ACK:   if (r_done) next_state = S_SEND_DATA_LOOP;

//             S_SEND_DATA_LOOP:       if (i2c_busy) next_state = S_WAIT_DATA_ACK;
//             S_WAIT_DATA_ACK:        if (r_done) next_state = (col_cnt == 7'd127) ? S_CHECK_PAGE_DONE : S_SEND_DATA_LOOP;

//             S_CHECK_PAGE_DONE:      next_state = (page_cnt == 4'd7) ? S_STOP_TX : S_SEND_CMD_CTRL; // 다음 페이지를 위해 다시 명령어 Control Byte 전송으로
            
//             S_STOP_TX:              if (!i2c_busy) next_state = S_WAIT_STOP_DONE;
//             S_WAIT_STOP_DONE:       if (r_done) next_state = S_MAP_DONE;
//             S_MAP_DONE: next_state = S_MAP_DONE;

//         endcase
//     end

//     // --- Combinational Logic 2: Output Logic ---
//     always @(*) begin
//         // 기본값 설정
//         i2c_start = 1'b0;
//         i2c_stop = 1'b0;
//         i2c_write = 1'b0;

//         case (state)
//             S_START_TX:         {i2c_start, i2c_write, i2c_data_in} = {1'b1, 1'b1, OLED_ADDR};
//             S_SEND_CMD_CTRL:    {i2c_write, i2c_data_in} = {1'b1, 8'h00}; // Command Control Byte
//             S_SET_PAGE:         {i2c_write, i2c_data_in} = {1'b1, 8'hB0 | page_cnt};
//             S_SET_COL_LOW:      {i2c_write, i2c_data_in} = {1'b1, 8'h00};
//             S_SET_COL_HIGH:     {i2c_write, i2c_data_in} = {1'b1, 8'h10};
//             S_SEND_DATA_CTRL:   {i2c_write, i2c_data_in} = {1'b1, 8'h40}; // Data Control Byte
//             S_SEND_DATA_LOOP:   {i2c_write, i2c_data_in} = {1'b1, rom_data};
//             S_STOP_TX:          i2c_stop = 1'b1;
//         endcase
//     end

//     reg [170:0] map_state;

//     always @(*) begin
//         case (state)
//             S_IDLE:               map_state = "          IDLE           ";
//             S_WAIT_FOR_GRANT:     map_state = "     WAIT_FOR_GRANT      ";
//             S_START_TX:           map_state = "        START_TX         ";
//             S_WAIT_ADDR_ACK:      map_state = "     WAIT_ADDR_ACK       ";
//             S_SEND_CMD_CTRL:      map_state = "     SEND_CMD_CTRL       ";
//             S_WAIT_CMD_CTRL_ACK:  map_state = "  WAIT_CMD_CTRL_ACK      ";
//             S_SET_PAGE:           map_state = "        SET_PAGE        ";
//             S_WAIT_PAGE_ACK:      map_state = "     WAIT_PAGE_ACK      ";
//             S_SET_COL_LOW:        map_state = "      SET_COL_LOW       ";
//             S_WAIT_COL_L_ACK:     map_state = "    WAIT_COL_L_ACK       ";
//             S_SET_COL_HIGH:       map_state = "     SET_COL_HIGH       ";
//             S_WAIT_COL_H_ACK:     map_state = "    WAIT_COL_H_ACK      ";
//             S_SEND_DATA_CTRL:     map_state = "    SEND_DATA_CTRL      ";
//             S_WAIT_DATA_CTRL_ACK: map_state = " WAIT_DATA_CTRL_ACK     ";
//             S_SEND_DATA_LOOP:     map_state = "    SEND_DATA_LOOP      ";
//             S_WAIT_DATA_ACK:      map_state = "     WAIT_DATA_ACK      ";
//             S_CHECK_PAGE_DONE:    map_state = "   CHECK_PAGE_DONE      ";
//             S_STOP_TX:            map_state = "         STOP_TX         ";
//             S_WAIT_STOP_DONE:     map_state = "    WAIT_STOP_DONE       ";
//             S_MAP_DONE: map_state="    MAP_DONE   ";
//             default:              map_state = "    UNKNOWN_STATE    ";
//         endcase
//     end

// endmodule


module oled_map_display_controller(
    clk, reset, draw_map_req, i2c_done, oled_granted, map_busy, 
    oled_req, i2c_start, i2c_stop, i2c_write, i2c_data_in, i2c_busy
);
    
    input clk, reset;
    input draw_map_req;
    input i2c_done;
    input oled_granted;
    input i2c_busy;
    output map_busy;
    output oled_req;
    output reg i2c_start, i2c_stop, i2c_write;
    output reg [7:0] i2c_data_in;

    localparam OLED_ADDR = 8'h78;

    // FSM state - 2개의 트랜잭션을 위해 상태 확장
    localparam [5:0] S_IDLE                 = 6'd0;
    // Command Transaction
    localparam [5:0] S_WAIT_FOR_GRANT_CMD   = 6'd1;
    localparam [5:0] S_START_TX_CMD         = 6'd2;
    localparam [5:0] S_WAIT_ADDR_ACK_CMD    = 6'd3;
    localparam [5:0] S_SEND_CMD_CTRL        = 6'd4;
    localparam [5:0] S_WAIT_CMD_CTRL_ACK    = 6'd5;
    localparam [5:0] S_SET_PAGE             = 6'd6;
    localparam [5:0] S_WAIT_PAGE_ACK        = 6'd7;
    localparam [5:0] S_SET_COL_LOW          = 6'd8;
    localparam [5:0] S_WAIT_COL_L_ACK       = 6'd9;
    localparam [5:0] S_SET_COL_HIGH         = 6'd10;
    localparam [5:0] S_WAIT_COL_H_ACK       = 6'd11;
    localparam [5:0] S_STOP_TX_CMD          = 6'd12;
    localparam [5:0] S_WAIT_STOP_CMD_DONE   = 6'd13;
    // Data Transaction
    localparam [5:0] S_WAIT_FOR_GRANT_DATA  = 6'd14;
    localparam [5:0] S_START_TX_DATA        = 6'd15;
    localparam [5:0] S_WAIT_ADDR_ACK_DATA   = 6'd16;
    localparam [5:0] S_SEND_DATA_CTRL       = 6'd17;
    localparam [5:0] S_WAIT_DATA_CTRL_ACK   = 6'd18;
    localparam [5:0] S_SEND_DATA_LOOP       = 6'd19;
    localparam [5:0] S_WAIT_DATA_ACK        = 6'd20;
    localparam [5:0] S_STOP_TX_DATA         = 6'd21;
    localparam [5:0] S_WAIT_STOP_DATA_DONE  = 6'd22;
    // Control
    localparam [5:0] S_CHECK_ALL_PAGES_DONE = 6'd23;
    localparam [5:0] S_MAP_DONE             = 6'd24;

    reg [5:0] state, next_state;
    reg r_done;

    assign map_busy = (state != S_IDLE && state != S_MAP_DONE);
    assign oled_req = map_busy && draw_map_req;

    reg [3:0] page_cnt;
    reg [6:0] col_cnt;
    wire [9:0] rom_addr;
    wire [7:0] rom_data;
    

    assign rom_addr = {page_cnt[2:0], col_cnt};

    maze_map_rom u_map_rom (.addr(rom_addr), .data(rom_data));

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            page_cnt <= 0;
            col_cnt <= 0;
            r_done <= 0;
        end else begin
            state <= next_state;
            if (i2c_done) r_done <= 1'b1;
            else if (next_state != state) r_done <= 1'b0;
            
            if (next_state != state) begin
                case(state)
                    S_WAIT_DATA_ACK:
                        if (col_cnt == 7'd127) col_cnt <= 0;
                        else col_cnt <= col_cnt + 1;
                    S_WAIT_STOP_DATA_DONE: // 데이터 트랜잭션이 끝나면 다음 페이지로
                        page_cnt <= page_cnt + 1;
                endcase
            end
            
            if(state == S_IDLE && next_state == S_WAIT_FOR_GRANT_CMD) begin
                page_cnt <= 0;
                col_cnt <= 0;
            end
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:                 if (draw_map_req) next_state = S_WAIT_FOR_GRANT_CMD;
            
            // --- Command Transaction ---
            S_WAIT_FOR_GRANT_CMD:   if (oled_granted) next_state = S_START_TX_CMD;
            S_START_TX_CMD:         if (i2c_busy) next_state = S_WAIT_ADDR_ACK_CMD;
            S_WAIT_ADDR_ACK_CMD:    if (r_done) next_state = S_SEND_CMD_CTRL;
            S_SEND_CMD_CTRL:        if (i2c_busy) next_state = S_WAIT_CMD_CTRL_ACK;
            S_WAIT_CMD_CTRL_ACK:    if (r_done) next_state = S_SET_PAGE;
            S_SET_PAGE:             if (i2c_busy) next_state = S_WAIT_PAGE_ACK;
            S_WAIT_PAGE_ACK:        if (r_done) next_state = S_SET_COL_LOW;
            S_SET_COL_LOW:          if (i2c_busy) next_state = S_WAIT_COL_L_ACK;
            S_WAIT_COL_L_ACK:       if (r_done) next_state = S_SET_COL_HIGH;
            S_SET_COL_HIGH:         if (i2c_busy) next_state = S_WAIT_COL_H_ACK;
            S_WAIT_COL_H_ACK:       if (r_done) next_state = S_STOP_TX_CMD;
            S_STOP_TX_CMD:          if (!i2c_busy) next_state = S_WAIT_STOP_CMD_DONE;
            S_WAIT_STOP_CMD_DONE:   if (r_done) next_state = S_WAIT_FOR_GRANT_DATA; // 명령어 전송 후 데이터 전송 요청

            // --- Data Transaction ---
            S_WAIT_FOR_GRANT_DATA:  if (oled_granted) next_state = S_START_TX_DATA;
            S_START_TX_DATA:        if (i2c_busy) next_state = S_WAIT_ADDR_ACK_DATA;
            S_WAIT_ADDR_ACK_DATA:   if (r_done) next_state = S_SEND_DATA_CTRL;
            S_SEND_DATA_CTRL:       if (i2c_busy) next_state = S_WAIT_DATA_CTRL_ACK;
            S_WAIT_DATA_CTRL_ACK:   if (r_done) next_state = S_SEND_DATA_LOOP;
            S_SEND_DATA_LOOP:       if (i2c_busy) next_state = S_WAIT_DATA_ACK;
            S_WAIT_DATA_ACK:        if (r_done) next_state = (col_cnt == 7'd127) ? S_STOP_TX_DATA : S_SEND_DATA_LOOP;
            S_STOP_TX_DATA:         if (!i2c_busy) next_state = S_WAIT_STOP_DATA_DONE;
            S_WAIT_STOP_DATA_DONE:  if (r_done) next_state = S_CHECK_ALL_PAGES_DONE;

            // --- Control ---
            S_CHECK_ALL_PAGES_DONE: next_state = (page_cnt == 4'd8) ? S_MAP_DONE : S_WAIT_FOR_GRANT_CMD;
            S_MAP_DONE:             next_state = S_MAP_DONE;
        endcase
    end

    always @(*) begin
        i2c_start = 1'b0;
        i2c_stop = 1'b0;
        i2c_write = 1'b0;
        // i2c_data_in = 8'h00;
        case (state)
            // Command Transaction Outputs
            S_START_TX_CMD:         {i2c_start, i2c_write, i2c_data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_SEND_CMD_CTRL:        {i2c_write, i2c_data_in} = {1'b1, 8'h00};
            S_SET_PAGE:             {i2c_write, i2c_data_in} = {1'b1, 8'hB0 | page_cnt[2:0]};
            S_SET_COL_LOW:          {i2c_write, i2c_data_in} = {1'b1, 8'h00};
            S_SET_COL_HIGH:         {i2c_write, i2c_data_in} = {1'b1, 8'h00};
            S_STOP_TX_CMD:          i2c_stop = 1'b1;

            // Data Transaction Outputs
            S_START_TX_DATA:        {i2c_start, i2c_write, i2c_data_in} = {1'b1, 1'b1, OLED_ADDR};
            S_SEND_DATA_CTRL:       {i2c_write, i2c_data_in} = {1'b1, 8'h40};
            S_SEND_DATA_LOOP:       {i2c_write, i2c_data_in} = {1'b1, rom_data};
            S_STOP_TX_DATA:         i2c_stop = 1'b1;
        endcase
    end

    reg [170:0] map_state;

    always @(*) begin
        case (state)
            S_IDLE:                 map_state = "           IDLE          ";
            S_WAIT_FOR_GRANT_CMD:  map_state = "    WAIT_FOR_GRANT_CMD    ";
            S_START_TX_CMD:        map_state = "       START_TX_CMD       ";
            S_WAIT_ADDR_ACK_CMD:   map_state = "    WAIT_ADDR_ACK_CMD     ";
            S_SEND_CMD_CTRL:       map_state = "      SEND_CMD_CTRL       ";
            S_WAIT_CMD_CTRL_ACK:   map_state = "   WAIT_CMD_CTRL_ACK      ";
            S_SET_PAGE:            map_state = "         SET_PAGE         ";
            S_WAIT_PAGE_ACK:       map_state = "      WAIT_PAGE_ACK       ";
            S_SET_COL_LOW:         map_state = "       SET_COL_LOW        ";
            S_WAIT_COL_L_ACK:      map_state = "     WAIT_COL_L_ACK       ";
            S_SET_COL_HIGH:        map_state = "      SET_COL_HIGH        ";
            S_WAIT_COL_H_ACK:      map_state = "     WAIT_COL_H_ACK       ";
            S_STOP_TX_CMD:         map_state = "       STOP_TX_CMD        ";
            S_WAIT_STOP_CMD_DONE:  map_state = "   WAIT_STOP_CMD_DONE     ";
            S_WAIT_FOR_GRANT_DATA: map_state = "   WAIT_FOR_GRANT_DATA    ";
            S_START_TX_DATA:       map_state = "      START_TX_DATA       ";
            S_WAIT_ADDR_ACK_DATA:  map_state = "   WAIT_ADDR_ACK_DATA     ";
            S_SEND_DATA_CTRL:      map_state = "     SEND_DATA_CTRL       ";
            S_WAIT_DATA_CTRL_ACK:  map_state = "  WAIT_DATA_CTRL_ACK      ";
            S_SEND_DATA_LOOP:      map_state = "     SEND_DATA_LOOP       ";
            S_WAIT_DATA_ACK:       map_state = "      WAIT_DATA_ACK       ";
            S_STOP_TX_DATA:        map_state = "      STOP_TX_DATA        ";
            S_WAIT_STOP_DATA_DONE: map_state = "  WAIT_STOP_DATA_DONE     ";
            S_CHECK_ALL_PAGES_DONE:map_state = " CHECK_ALL_PAGES_DONE     ";
            S_MAP_DONE:            map_state = "         MAP_DONE         ";
            default:               map_state = "        UNKNOWN_STATE     ";
        endcase
    end

endmodule
