module top_joystick(clk, reset, sw, joystick_x_p, joystick_y_p, leds, seg, an);
    input clk, reset;
    input sw;
    input joystick_x_p, joystick_y_p; // 조이스틱 아날로그 입력  
    output [3:0] leds; 
    output [6:0] seg;
    output [3:0] an;

    wire [11:0] adc_x_val;
    wire [11:0] adc_y_val;
    wire [11:0] fnd_in;

    adc_controller U_adc_controller (
        .clk(clk),
        .reset(reset),
        .vauxp_x_in(joystick_x_p),
        .vauxp_y_in(joystick_y_p),
        .adc_x_out(adc_x_val),
        .adc_y_out(adc_y_val)
    );

    joystick_led_controller U_joystick_led_controller(
        .clk(clk),
        .reset(reset),
        .adc_x_value(adc_x_val), 
        .adc_y_value(adc_y_val),
        .leds(leds)
    );

    // 값 확인 위한 sw와 fnd 제어
    assign fnd_in = (sw) ? adc_y_val : adc_x_val;
    // X축, Y축의 ADC 값을 FND에 표시
    fnd_controller fnd_inst (
        .clk(clk),
        .reset(reset),
        .binary_in(fnd_in), 
        .seg(seg),
        .an(an)
    );
    
    
endmodule