`timescale 1ns/1ps
// Behavioral readiness model only: no generated/gated clock or CDC claim.
// Delay D makes ready visible before the Dth START sampling edge.
module clock_controller #(
    parameter integer MAX_DELAY = 10
)(
    input wire clk_i, rst_ni, enable_i,
    input integer delay_i, // positive: directed; zero: seeded random
    output reg ready_o=0,
    output integer chosen_delay_o
);
    reg starting=0;
    integer elapsed=0, seed;
    reg [31:0] rng;
    initial begin
        seed=1;
        if ($value$plusargs("SEED=%d",seed)) begin end
        rng=32'h9e3779b9 ^ seed;
        if (rng==0) rng=1;
        if (MAX_DELAY<1) $fatal(1,"clock model MAX_DELAY must be positive");
    end
    always @(negedge clk_i or negedge rst_ni) begin
        if (!rst_ni || !enable_i) begin
            ready_o=0; starting=0; elapsed=0; chosen_delay_o=0;
        end else if (!ready_o) begin
            if (!starting) begin
                rng=rng ^ (rng << 13);
                rng=rng ^ (rng >> 17);
                rng=rng ^ (rng << 5);
                chosen_delay_o=(delay_i>0) ? delay_i : 1+(rng % MAX_DELAY);
                starting=1;
            end
            elapsed=elapsed+1;
            if (elapsed>=chosen_delay_o) ready_o=1;
        end
    end
endmodule
