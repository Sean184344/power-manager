`timescale 1ns/1ps
// Behavioral supply; delays are counted on an always-running reference clock.
module power_supply(
    input wire clk_i, arst_ni, enable_i, missing_on_i, stuck_on_i, drop_i,
    input integer on_delay_i, off_delay_i,
    output reg good_o=0
);
    integer elapsed=0;
    always @(negedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin good_o=0; elapsed=0; end
        else if (drop_i) begin good_o=0; elapsed=0; end
        else if (enable_i && !good_o) begin
            elapsed=elapsed+1;
            if (!missing_on_i && elapsed>=on_delay_i) begin good_o=1; elapsed=0; end
        end else if (!enable_i && good_o) begin
            elapsed=elapsed+1;
            if (!stuck_on_i && elapsed>=off_delay_i) begin good_o=0; elapsed=0; end
        end else elapsed=0;
    end
endmodule
