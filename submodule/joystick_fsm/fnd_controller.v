module fnd_controller(clk, reset, binary_in, seg, an);
    input clk;
    input reset;
    input [11:0] binary_in;
    output [7:0] seg;
    output [3:0] an;   // 자릿수 선택 

    wire [1:0] w_sel;
    wire [3:0] w_d1, w_d10, w_d100, w_d1000;

    fnd_digit_select u_fnd_digit_select(.clk(clk),.reset(reset), .digit_sel(w_sel));

    bin2bcd u_bin2bcd(.in_data(binary_in),.d1(w_d1),.d10(w_d10),.d100(w_d100),.d1000(w_d1000));

    fnd_display u_fnd_display(.digit_sel(w_sel),.d1(w_d1),.d10(w_d10),.d100(w_d100),.d1000(w_d1000),.an(an),.seg(seg));

endmodule



module bin2bcd(in_data, d1, d10, d100, d1000);
    input [13:0]  in_data;
    output reg [3:0]  d1, d10, d100, d1000;

    always @(*) begin
        d1    = in_data          % 10;
        d10   = (in_data / 10)   % 10;
        d100  = (in_data / 100)  % 10;
        d1000 = (in_data / 1000) % 10;

    end
endmodule




module fnd_display(digit_sel, d1, d10, d100, d1000, an, seg);
    input [1:0] digit_sel;
    input [3:0]  d1, d10,  d100, d1000;
    output reg [3:0] an;
    output reg [7:0] seg;


    reg [3:0]  bcd_data;

    always @(digit_sel) begin
        case(digit_sel)
            2'b00: begin bcd_data = d1; an = 4'b1110; end
            2'b01: begin bcd_data = d10; an = 4'b1101; end
            2'b10: begin bcd_data = d100; an = 4'b1011; end
            2'b11: begin bcd_data = d1000; an = 4'b0111; end
            default: begin  bcd_data = 4'b0000; an = 4'b1111; end
        endcase
    end 

    always @(bcd_data) begin
        case(bcd_data)
            4'd0: seg = 8'b11000000;  // 0
            4'd1: seg = 8'b11111001;  // 1
            4'd2: seg = 8'b10100100;  // 2
            4'd3: seg = 8'b10110000;  // 3
            4'd4: seg = 8'b10011001;  // 4
            4'd5: seg = 8'b10010010;  // 5
            4'd6: seg = 8'b10000010;  // 6
            4'd7: seg = 8'b11111000;  // 7
            4'd8: seg = 8'b10000000;  // 8
            4'd9: seg = 8'b10010000;  // 9
            default: seg = 8'b11111111;  // all off
        endcase
    end 
endmodule

module fnd_digit_select (clk, reset, digit_sel);
    input        clk,  reset;
    output reg [1:0] digit_sel;

    reg [16:0] count;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;
            digit_sel   <= 0;
        end 
        else if (count == 100_000-1) begin  // 1 ms @100 MHz
            count <= 0;
            digit_sel   <= digit_sel + 1;
        end 
        else begin
            count <= count + 1;
        end
    end
endmodule

