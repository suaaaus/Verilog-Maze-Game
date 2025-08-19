`timescale 1ns / 1ps

module fnd_controller_eep(clk, reset, input_data, /*state,*/show_hi, seg_data, an);
    input           clk, reset;
    input  [31:0]   input_data; // 전체 데이터 32bit
    input           show_hi;    // 
    output [7:0]    seg_data;
    output [3:0]    an;
    
    // parameter AHU_TEMP = 2'b01;
    // parameter AHU_HUMM = 2'b10;

    wire [15:0] byte_2 = show_hi ? input_data[31:16] : input_data[15:0];
    wire [1:0]  w_sel;
    wire [3:0]  w_d1, w_d10, w_d100, w_d1000;

    wire [3:0] d1       = byte_2[3:0];
    wire [3:0] d10      = byte_2[7:4];
    wire [3:0] d100     = byte_2[11:8];
    wire [3:0] d1000    = byte_2[15:12];

    // 3. 모듈 연결
    fnd_digit_select u_fnd_digit_select_eeprom(
        .clk(clk),
        .reset(reset),
        .digit_sel(w_sel)
    );

    // bin2bcd_eeprom u_bin2bcd_eeprom(
    //     .clk(clk),
    //     .reset(reset),
    //     .d1_data(w_d1_data),
    //     .in_data(w_input_data),
    //     .d1(w_d1),
    //     .d10(w_d10),
    //     .d100(w_d100),
    //     .d1000(w_d1000)
    // );

    fnd_display_eeprom u_fnd_display_eeprom(
        .digit_sel(w_sel),
        .d1(d1),
        .d10(d10),
        .d100(d100),
        .d1000(d1000),
        .an(an),
        .seg(seg_data)
    );

endmodule

module fnd_digit_select(clk, reset, digit_sel);
    input        clk,  reset;
    output reg [1:0] digit_sel;

    reg [16:0] count;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;
            digit_sel   <= 0;
        end else if (count == 100_000-1) begin  // 1 ms @100 MHz
            count <= 0;
            digit_sel   <= digit_sel + 1;
        end else begin
            count <= count + 1;
        end
    end
endmodule


// module bin2bcd_eeprom(clk, reset, d1_data, in_data, d1, d10, d100, d1000);
//     input           clk, reset;
//     input           d1_data;
//     input   [13:0]  in_data;
//     output  [3:0]   d1, d10, d100, d1000;

//     assign d1       = in_data % 10;
//     assign d10      = (in_data / 10) % 10;
//     assign d100     = (in_data / 100) % 10;
//     assign d1000    = (in_data / 1000) % 10;
// endmodule 


module fnd_display_eeprom(digit_sel, d1, d10, d100, d1000, an, seg);
    input       [1:0]   digit_sel;
    input       [3:0]   d1, d10, d100, d1000;
    output reg  [3:0]   an;
    output reg  [7:0]   seg;

    reg [3:0]  nibble;

    always @(digit_sel) begin
        case(digit_sel)
            2'b00: begin nibble = d1; an = 4'b1110; end
            2'b01: begin nibble = d10; an = 4'b1101; end
            2'b10: begin nibble = d100; an = 4'b1011; end
            2'b11: begin nibble = d1000; an = 4'b0111; end
            default: begin  nibble = 4'b0000; an = 4'b1111; end
        endcase
    end 

    always @(nibble) begin
        case(nibble)
            4'd0 : seg = 8'b11000000;   // 0
            4'd1 : seg = 8'b11111001;   // 1
            4'd2 : seg = 8'b10100100;   // 2
            4'd3 : seg = 8'b10110000;   // 3
            4'd4 : seg = 8'b10011001;   // 4
            4'd5 : seg = 8'b10010010;   // 5
            4'd6 : seg = 8'b10000010;   // 6
            4'd7 : seg = 8'b11111000;   // 7
            4'd8 : seg = 8'b10000000;   // 8
            4'd9 : seg = 8'b10010000;   // 9
            4'd10: seg = 8'b10001000;   // A
            4'd11: seg = 8'b10000011;   // B
            4'd12: seg = 8'b11000110;   // C
            4'd13: seg = 8'b10100001;   // d
            4'd14: seg = 8'b10000110;   // E
            4'd15: seg = 8'b10001110;   // F
            default: seg = 8'b11111111; // all off
        endcase
    end 
endmodule