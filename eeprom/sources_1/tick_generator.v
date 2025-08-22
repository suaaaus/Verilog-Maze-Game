`timescale 1ns / 1ps

module tick_generator #(parameter integer INPUT_FREQ = 100_000_000,
                        parameter integer TICK_HZ = 1000) (clk, reset, tick);
    input clk, reset;
    output reg tick;
 
    localparam TICK_COUNT = INPUT_FREQ / TICK_HZ;

    reg [$clog2(TICK_COUNT)-1:0] r_tick_counter;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_tick_counter <= 0;
            tick <= 0;
        end else begin
            if (r_tick_counter == TICK_COUNT - 1) begin
                r_tick_counter <= 0;
                tick <= 1'b1;
            end else begin
                r_tick_counter <= r_tick_counter + 1;
                tick <= 1'b0;  
            end
        end
    end

endmodule
    // localparam integer HALF_COUNT = INPUT_FREQ / (2 * TICK_HZ);
    // reg [$clog2(HALF_COUNT)-1:0] counter;

    // always @(posedge clk or posedge reset) begin
    //     if (reset) begin
    //         counter <= 0;
    //         tick    <= 1;
    //     end else begin
    //         if (counter == HALF_COUNT - 1) begin
    //             counter <= 0;
    //             tick    <= ~tick;   // ✔ 반전
    //         end else begin
    //             counter <= counter + 1;
    //         end
    //     end
    // end
