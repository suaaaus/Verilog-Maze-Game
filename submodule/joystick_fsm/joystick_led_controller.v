module joystick_led_controller (
    input clk, 
    input reset, 
    input [11:0] adc_x_value,
    input [11:0] adc_y_value, 
    output reg [3:0] leds
);
    // LED 출력: [3:우, 2:좌, 1:하, 0:상]
    wire tick;
    tick_generator #(.INPUT_FREQ(100_000_000), .TICK_HZ(400_000)) 
        u_tick_gen(.clk(clk), .reset(reset), .tick(tick));


    localparam Y_UP_THRESHOLD   = 12'd800;   
    localparam Y_DOWN_THRESHOLD = 12'd4000; 
    localparam X_LEFT_THRESHOLD  = 12'd400;   
    localparam X_RIGHT_THRESHOLD = 12'd3600;  

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            leds <= 4'b0000; 
        end 
        else begin
            if (tick) begin
                leds <= 4'b0000; 

                // Y축 확인 (상/하) 
                if (adc_y_value < Y_UP_THRESHOLD) begin
                    leds[0] <= 1'b1; // '상' LED 
                end 
                else if (adc_y_value > Y_DOWN_THRESHOLD && adc_x_value < 12'd2860) begin
                    leds[1] <= 1'b1; // '하' LED 
                end

                // X축 확인 (좌/우)
                if (adc_x_value < X_LEFT_THRESHOLD) begin
                    leds[2] <= 1'b1; // '좌' LED 
                end 
                else if (adc_x_value > X_RIGHT_THRESHOLD && adc_y_value == 12'd4095) begin
                    leds[3] <= 1'b1; // '우' LED 
                    leds[1] <= 1'b0;
                end
            
            end
        end
    end

endmodule