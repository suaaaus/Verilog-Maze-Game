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
endmodule

// module tick_generator #(
//     parameter integer INPUT_FREQ = 100_000_000,
//     parameter integer TICK_HZ    = 100_000     // 원하는 SCL 주파수 (100kHz)
// )(
//     input wire clk,
//     input wire reset,
//     output reg tick        // 1클럭짜리 펄스 (상위 FSM 구동용)
//     //output reg tick_phase   // 0 또는 1: SCL LOW/HIGH 구분용
// );

//     localparam integer HALF_CYCLE = INPUT_FREQ / (TICK_HZ * 2);  // SCL HIGH 또는 LOW 하나 길이

//     reg [$clog2(HALF_CYCLE)-1:0] counter;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             tick <= 0;
//             //tick_phase <= 0;
//         end else begin
//             if (counter == HALF_CYCLE - 1) begin
//                 counter <= 0;
//                 //tick_phase <= ~tick_phase;  // 0 → 1 → 0 → 1 → ...
//                 tick <= 1;                  // 1클럭 펄스
//             end else begin
//                 counter <= counter + 1;
//                 tick <= 0;
//             end
//         end
//     end

// endmodule
