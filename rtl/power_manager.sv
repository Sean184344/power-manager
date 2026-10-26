`timescale 1ns/1ps
// v0.1: synchronous, single-domain clock-sleep controller.
// clk_en_o is a REQUEST to a clock controller, never a fabric-generated clock.
module power_manager #(
    parameter integer TIMEOUT_CYCLES = 8
)(
    input wire clk_i, rst_ni,
    input wire sleep_req_i, wake_i, idle_i, clock_ready_i,
    output reg block_work_o, isolate_o, clk_en_o,
    output wire sleeping_o, active_o,
    output reg fault_o,
    output wire [2:0] state_o
`ifdef FORMAL
    , output wire formal_sleep_armed_o
`endif
);
    localparam [2:0] RUN=0, DRAIN=1, ISOLATE=2, SLEEP=3,
                     START=4, RELEASE=5, FAULT=6;
    localparam integer CW = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [2:0] state_q, state_d;
    reg [CW-1:0] count_q;
    reg wake_pending_q, sleep_armed_q;
`ifdef FORMAL
    assign formal_sleep_armed_o=sleep_armed_q;
`endif
    wire wake_seen = wake_i | wake_pending_q;
    wire expired = (count_q == TIMEOUT_CYCLES-1);
    assign state_o = state_q;
    assign active_o = (state_q == RUN);
    assign sleeping_o = (state_q == SLEEP);

    always @* begin
        state_d = state_q;
        case (state_q)
            RUN: if (sleep_req_i && sleep_armed_q && !wake_seen) state_d = DRAIN;
            DRAIN: begin
                if (wake_seen) state_d = RUN;
                else if (idle_i) state_d = ISOLATE;
                else if (expired) state_d = RUN;
            end
            ISOLATE: if (wake_seen) state_d = RELEASE; else state_d = SLEEP;
            SLEEP: if (wake_seen) state_d = START;
            START: begin
                if (clock_ready_i) state_d = RELEASE;
                else if (expired) state_d = FAULT;
            end
            RELEASE: state_d = RUN;
            FAULT: state_d = FAULT;
            default: state_d = FAULT;
        endcase
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= START;
            count_q <= 0;
            wake_pending_q <= 0;
            sleep_armed_q <= 1;
            fault_o <= 0;
        end else begin
            state_q <= state_d;
            if (state_d != state_q || (state_q != DRAIN && state_q != START))
                count_q <= 0;
            else if (!expired) count_q <= count_q + 1'b1;
            // Accepted wake is retained until normal execution resumes.
            if (state_q == RUN) wake_pending_q <= 0;
            else if (wake_i) wake_pending_q <= 1;
            // One sleep attempt per request assertion, including aborted attempts.
            if (!sleep_req_i) sleep_armed_q <= 1;
            else if (state_q == RUN && state_d == DRAIN) sleep_armed_q <= 0;
            if ((state_q == DRAIN && !wake_seen && !idle_i && expired) ||
                (state_q == START && !clock_ready_i && expired) || state_d == FAULT)
                fault_o <= 1;
        end
    end

    always @* begin
        block_work_o = 1;
        isolate_o = 1;
        clk_en_o = 1;
        case (state_q)
            RUN: begin block_work_o = 0; isolate_o = 0; end
            DRAIN: isolate_o = 0;
            SLEEP: clk_en_o = 0;
            default: begin end
        endcase
    end
endmodule
