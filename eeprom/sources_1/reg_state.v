`timescale 1ns / 1ps

module reg_state #(parameter W = 4)(
    input               clk,
    input               reset,
    input               EN,
    input       [W-1:0] D,
    output reg  [W-1:0] Q
    );

    always @(posedge clk) begin
        if (reset)
            Q <= {W{1'b0}};
        else if (EN)
            Q <= D;
    end

endmodule
