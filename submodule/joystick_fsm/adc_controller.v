// x축과 y축 번갈아가며 adc 측정
module adc_controller (clk, reset, vauxp_x_in, vauxp_y_in, adc_x_out, adc_y_out);
    input clk, reset;
    input vauxp_x_in, vauxp_y_in; // x, y축 아날로그 입력
    output reg [11:0] adc_x_out, adc_y_out;  // x, y축 디지털 출력

    // x축 : vaux6
    // y축 : vaux7
    
    reg  [6:0]  daddr_in; // DRP 주소 입력
    reg         den_in;   // DRP en 입력
    wire [15:0] do_out;   // DRP 준비 완료
    wire        drdy_out; // DRP 데이터 출력 
    
    // FSM state
    localparam  S_IDLE_X     = 3'b000,
                S_WAIT_X     = 3'b001, // X축 읽기 준비
                S_READ_X     = 3'b010, // X축 읽기
                S_IDLE_Y     = 3'b100, 
                S_WAIT_Y     = 3'b101, // Y축 읽기 준비
                S_READ_Y     = 3'b110; // Y축 읽기


    reg [2:0] state, next_state;

    // Next state logic
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= S_IDLE_X;
        else
            state <= next_state;
    end

    // Output logic
    always @(*) begin
        den_in = 1'b0;
        daddr_in = 7'h00; 
        next_state = state;

        case (state)
            S_IDLE_X: begin 
                den_in = 1'b1;
                daddr_in = 7'h16; // vaux6 채널 주소
                next_state = S_WAIT_X;
            end
            S_WAIT_X: begin 
                daddr_in = 7'h16;
                if (drdy_out)
                    next_state = S_READ_X;
                else
                    next_state = S_WAIT_X;
            end
            S_READ_X: begin
                daddr_in = 7'h16;
                adc_x_out = do_out[15:4]; // adc 해상도가 12비트라 상위 12비트만
                next_state = S_IDLE_Y; 
            end
            S_IDLE_Y: begin
                den_in = 1'b1;
                daddr_in = 7'h17; // vaux7 채널 주소
                next_state = S_WAIT_Y;
            end
            S_WAIT_Y: begin 
                daddr_in = 7'h17;
                if (drdy_out)
                    next_state = S_READ_Y;
                else
                    next_state = S_WAIT_Y;
            end
            S_READ_Y: begin 
                daddr_in = 7'h17;
                adc_y_out = do_out[15:4];
                next_state = S_IDLE_X; 
            end
            default: begin
                next_state = S_IDLE_X;
            end
        endcase
    end
    
    // XADC IP 
    xadc_wiz_0 xadc_inst (
        .daddr_in(daddr_in),
        .dclk_in(clk),
        .den_in(den_in),
        .dwe_in(1'b0),
        .di_in(16'b0),
        .reset_in(reset),
        
        .vauxp6(vauxp_x_in),
        .vauxn6(1'b0),
        .vauxp7(vauxp_y_in),
        .vauxn7(1'b0),
        
        .do_out(do_out),
        .drdy_out(drdy_out)
    );

endmodule