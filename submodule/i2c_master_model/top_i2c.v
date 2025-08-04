module top_i2c(clk, reset, start, stop, write, read, data_in, ack_in, sda, scl, done, busy, ack_err, data_out);
    input clk, reset;
    input start, stop, write, read;
    input [7:0] data_in;
    input ack_in;
    inout sda;
    output scl;
    output done, busy;
    output ack_err;
    output [7:0] data_out;

    wire tick_400KHz;
    tick_generator #(.INPUT_FREQ(100_000_000), .TICK_HZ(400_000)) U_tick_100KHz(.clk(clk), .reset(reset), .tick(tick_400KHz));

    i2c_master U_i2c_master(.clk(clk), .reset(reset), .start(start), .stop(stop), .write(write), .read(read), .ack_in(ack_in), 
                            .tick(tick_400KHz), .data_in(data_in),
                            .data_out(data_out), .done(done), .busy(busy), .ack_err(ack_err), .sda(sda), .scl(scl));
endmodule