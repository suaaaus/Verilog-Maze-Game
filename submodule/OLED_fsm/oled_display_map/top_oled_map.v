module top_oled_map (clk, reset, sda, scl, i2c_ack_err);
    input clk, reset;
    inout sda;
    output scl;
    output i2c_ack_err;

    // 1. Tick Generator -> I2C Master
    wire tick; // 400kHz tick sig

    // 2. I2C Master <-> FSMs
    wire i2c_done;
    wire i2c_busy;
    wire i2c_ack_err;

    // 3. FSMs -> Arbiter
    wire oled_init_req;
    wire oled_map_req;

    // 4. Arbiter -> FSMs
    wire oled_init_grant;
    //assign oled_init_grant =1'b1;
    wire oled_map_grant;
    wire [1:0] master_sel;

    // 5. FSMs -> Mux
    wire init_start, init_stop, init_write;
    wire [7:0] init_data_in;
    wire map_start, map_stop, map_write;
    wire [7:0] map_data_in;

    // 6. Mux -> I2C Master
    reg oled_start, oled_stop, oled_write, oled_busy, oled_done;
    reg [7:0] oled_data_in;

    // 7. Init FSM -> Map Controller
    wire oled_init_done;

    // Tick 생성기 (I2C 마스터용)
    tick_generator #(.INPUT_FREQ(100_000_000), .TICK_HZ(400_000))
        u_tick_gen(.clk(clk), .reset(reset), .tick(tick));

    // 1. OLED 초기화 FSM (Arbiter의 master0 사용)
    oled_init_fsm u_oled_init_fsm (
        .clk(clk),
        .reset(reset),
        .busy(i2c_busy),
        .done(i2c_done),
        .ack_err(i2c_ack_err),
        .oled_granted(1'b1), // Arbiter로부터 허가 신호 입력
        .oled_busy(),
        .oled_init_done(oled_init_done),
        .oled_req(oled_init_req),       // Arbiter로 버스 사용 요청
        .start(init_start),
        .stop(init_stop),
        .write(init_write),
        .data_in(init_data_in),
        .oled_err()
    );

    // 2. OLED 맵 데이터 전송 FSM (Arbiter의 OLED 슬롯 사용)
    oled_map_display_controller u_oled_map_ctrl (
        .clk(clk),
        .reset(reset),
        .draw_map_req(1'b0),      // 초기화가 끝나면 맵 그리기를 시작하라는 신호
        .i2c_done(i2c_done),
        .oled_granted(oled_map_grant),      // Arbiter로부터 허가 신호 입력
        .i2c_busy(i2c_busy),
        .map_busy(),
        .oled_req(oled_map_req),            // Arbiter로 버스 사용 요청
        .i2c_start(map_start),
        .i2c_stop(map_stop),
        .i2c_write(map_write),
        .i2c_data_in(map_data_in)
    );

    // 3. I2C 버스 중재기 (Arbiter)
    i2c_arbiter u_i2c_arbiter (
        .clk(clk),
        .reset(reset),
        .master0_req(oled_init_req),      // init_fsm을 master0 슬롯에 연결
        .master1_req(oled_map_req),        // map_controller를 oled 슬롯에 연결
        .master0_grant(oled_init_grant),
        .master1_grant(oled_map_grant),
        .master_sel(master_sel)         // 현재 버스 소유자를 Mux에 알려줌
    );

    // 4. Mux 로직: Arbiter의 선택에 따라 I2C 마스터에 전달할 신호를 결정
    always @(*) begin
        case(master_sel)
            2'b01: begin // Arbiter가 oled_init_fsm(master0 자리)에게 허가
                oled_start   = init_start;
                oled_stop    = init_stop;
                oled_write   = init_write;
                oled_data_in = init_data_in;

            end
            2'b10: begin // Arbiter가 oled_map_display_controller(OLED 자리)에게 허가
                oled_start   = map_start;
                oled_stop    = map_stop;
                oled_write   = map_write;
                oled_data_in = map_data_in;
            end
            default: begin // IDLE 상태
                oled_start   = 1'b0;
                oled_stop    = 1'b0;
                oled_write   = 1'b0;
                oled_data_in = 8'h00;
            end
        endcase
    end

    // 5. I2C 마스터
    i2c_master U_i2c_master(
        .clk(clk),
        .reset(reset),
        .start(oled_start),
        .stop(oled_stop),
        .write(oled_write),
        .read(1'b0),            // 읽기 기능은 사용하지 않음
        .ack_in(1'b0),          // 읽기 기능은 사용하지 않음
        .tick(tick),
        .data_in(oled_data_in),
        .data_out(),            // 읽기 기능은 사용하지 않음
        .done(i2c_done),
        .busy(i2c_busy),
        .ack_err(i2c_ack_err),
        .sda(sda),
        .scl(scl)
    );

endmodule