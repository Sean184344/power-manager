`timescale 1ns/1ps
// TESTBENCH ONLY. Falling-edge gate model; not a synthesizable clock-cell design.
module async_clock_controller #(parameter RESET_REQUEST=1'b1)(
    input wire raw_clk_i, arst_ni, request_i, withhold_ready_i,
    input integer start_delay_i, stop_delay_i,
    output wire domain_clk_o,
    output reg ready_o=0, gate_o=0
);
    wire request_sync;
    integer elapsed=0, stop_elapsed=0;
    cdc_level #(.RESET_VALUE(RESET_REQUEST)) request_receiver(
        .clk_i(raw_clk_i),.rst_ni(arst_ni),.async_i(request_i),.sync_o(request_sync));
    assign domain_clk_o=raw_clk_i && gate_o;
    always @(negedge raw_clk_i or negedge arst_ni) begin
        if (!arst_ni) begin gate_o=0; ready_o=0; elapsed=0; stop_elapsed=0; end
        else if (!request_sync) begin
            stop_elapsed=stop_elapsed+1;
            if (stop_elapsed>=stop_delay_i) begin gate_o=0; ready_o=0; elapsed=0; end
        end else if (!gate_o) begin
            stop_elapsed=0;
            elapsed=elapsed+1;
            if (elapsed>=start_delay_i) gate_o=1;
        end else begin stop_elapsed=0; ready_o=!withhold_ready_i; end
    end
endmodule
