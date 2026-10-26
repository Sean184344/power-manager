`timescale 1ns/1ps
// Behavioral single-slot worker. clk_en_i is a logical progress enable.
module managed_workload (
    input wire clk_i, rst_ni, clk_en_i, block_work_i,
    input wire req_valid_i,
    input wire [31:0] req_id_i,
    input integer req_cycles_i,
    output wire req_ready_o, idle_o,
    output reg done_o,
    output reg [31:0] done_id_o,
    output integer accepted_o, completed_o
);
    reg busy_q;
    reg [31:0] id_q;
    integer remaining_q;
    assign req_ready_o = rst_ni && clk_en_i && !block_work_i && !busy_q;
    assign idle_o = !busy_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 0;
            id_q <= 0;
            remaining_q <= 0;
            done_o <= 0;
            done_id_o <= 0;
            accepted_o <= 0;
            completed_o <= 0;
        end else begin
            done_o <= 0;
            if (clk_en_i && busy_q) begin
                if (remaining_q == 1) begin
                    busy_q <= 0;
                    done_o <= 1;
                    done_id_o <= id_q;
                    completed_o <= completed_o + 1;
                end else remaining_q <= remaining_q - 1;
            end
            if (req_valid_i && req_ready_o) begin
                if (req_cycles_i < 1) $fatal(1, "work latency must be positive");
                busy_q <= 1;
                id_q <= req_id_i;
                remaining_q <= req_cycles_i;
                accepted_o <= accepted_o + 1;
            end
        end
    end
endmodule
