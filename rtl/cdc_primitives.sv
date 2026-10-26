`timescale 1ns/1ps
// Single-bit level crossing. Input must obey its enclosing handshake contract.
module cdc_level #(parameter RESET_VALUE=1'b0)(
    input wire clk_i, rst_ni, async_i,
    output wire sync_o
);
    (* ASYNC_REG = "TRUE" *) reg meta_q, sync_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin meta_q<=RESET_VALUE; sync_q<=RESET_VALUE; end
        else begin meta_q<=async_i; sync_q<=meta_q; end
    end
    assign sync_o=sync_q;
endmodule

// Common global reset: asynchronous assertion, two-edge local release.
module cdc_reset(input wire clk_i, arst_ni, output wire rst_no);
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_q;
    always @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) release_q<=2'b00;
        else release_q<={release_q[0],1'b1};
    end
    assign rst_no=release_q[1];
endmodule

// One source-clock pulse while ready -> exactly one destination-clock pulse.
// Both clocks must run. Global reset cancels an outstanding event.
module cdc_event(
    input wire src_clk_i, src_rst_ni, pulse_i,
    output wire ready_o,
    input wire dst_clk_i, dst_rst_ni,
    output reg pulse_o
);
    reg request_q, ack_q;
    wire request_sync, ack_sync;
    cdc_level req_sync(.clk_i(dst_clk_i),.rst_ni(dst_rst_ni),.async_i(request_q),.sync_o(request_sync));
    cdc_level ack_return(.clk_i(src_clk_i),.rst_ni(src_rst_ni),.async_i(ack_q),.sync_o(ack_sync));
    assign ready_o=src_rst_ni && !request_q && !ack_sync;
    always @(posedge src_clk_i or negedge src_rst_ni) begin
        if (!src_rst_ni) request_q<=0;
        else if (request_q && ack_sync) request_q<=0;
        else if (pulse_i && ready_o) request_q<=1;
    end
    always @(posedge dst_clk_i or negedge dst_rst_ni) begin
        if (!dst_rst_ni) begin ack_q<=0; pulse_o<=0; end
        else begin
            pulse_o<=request_sync && !ack_q;
            ack_q<=request_sync;
        end
    end
endmodule
