`timescale 1ns/1ps
// M3 wrapper; retains the synchronous v0.1 FSM as a separate reusable core.
module power_manager_cdc #(
    parameter integer TIMEOUT_CYCLES=64
)(
    input wire aon_clk_i, domain_clk_i, wake_clk_i, arst_ni,
    input wire sleep_req_i, // AON synchronous level; sampled low to rearm
    input wire wake_pulse_i, // wake_clk synchronous, one cycle when wake_ready_o
    input wire domain_idle_i, // domain_clk synchronous; no accepted work remains
    input wire clock_ready_i, // held external clock-controller acknowledgement
    output wire wake_ready_o, wake_event_o,
    output wire aon_rst_no, domain_rst_no, wake_rst_no,
    output wire domain_block_work_o, isolate_o,
    output reg clock_req_o,
    output wire active_o, sleeping_o, fault_o,
    output wire sleep_ready_o, quiesced_o,
    output wire [2:0] state_o
);
    wire core_block, core_clock, clock_ready_sync;
    reg quiesce_req_q, domain_ack_q;
    wire domain_released_sync;
    reg sleep_armed_q;
    reg [2:0] previous_state_q;
    cdc_reset aon_reset(.clk_i(aon_clk_i),.arst_ni(arst_ni),.rst_no(aon_rst_no));
    cdc_reset domain_reset(.clk_i(domain_clk_i),.arst_ni(arst_ni),.rst_no(domain_rst_no));
    cdc_reset wake_reset(.clk_i(wake_clk_i),.arst_ni(arst_ni),.rst_no(wake_rst_no));
    cdc_event wake_bridge(.src_clk_i(wake_clk_i),.src_rst_ni(wake_rst_no),
        .pulse_i(wake_pulse_i),.ready_o(wake_ready_o),
        .dst_clk_i(aon_clk_i),.dst_rst_ni(aon_rst_no),.pulse_o(wake_event_o));
    cdc_level #(.RESET_VALUE(1'b1)) block_crossing(
        .clk_i(domain_clk_i),.rst_ni(domain_rst_no),.async_i(quiesce_req_q),.sync_o(domain_block_work_o));
    // Ack means blocked AND drained, not merely a snapshot of idle.
    // Hold it until the request clears, even if the AON FSM aborts entry.
    always @(posedge domain_clk_i or negedge domain_rst_no) begin
        if (!domain_rst_no) domain_ack_q<=0;
        else if (!domain_block_work_o) domain_ack_q<=0;
        else if (domain_idle_i) domain_ack_q<=1;
    end
    cdc_level ack_crossing(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),
        .async_i(domain_ack_q),.sync_o(quiesced_o));
    cdc_level released_crossing(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),
        .async_i(!domain_block_work_o),.sync_o(domain_released_sync));
    cdc_level ready_crossing(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),
        .async_i(clock_ready_i),.sync_o(clock_ready_sync));
    assign sleep_ready_o=active_o && !quiesce_req_q && !quiesced_o && domain_released_sync;
    always @(posedge aon_clk_i or negedge aon_rst_no) begin
        if (!aon_rst_no) begin
            quiesce_req_q<=1;
            clock_req_o<=1;
            sleep_armed_q<=1;
            previous_state_q<=3'd4;
        end else begin
            previous_state_q<=state_o;
            // Core request masking must not rearm a held external sleep level.
            if (!sleep_req_i) sleep_armed_q<=1;
            else if (state_o==3'd1 && previous_state_q!=3'd1) sleep_armed_q<=0;
            if (!quiesce_req_q && core_block) quiesce_req_q<=1;
            else if (quiesce_req_q && !core_block && quiesced_o) quiesce_req_q<=0;
            // Observe the off acknowledgement before a restart; stale ready
            // cannot satisfy a new START after a short SLEEP interval.
            if (clock_req_o && !core_clock) clock_req_o<=0;
            else if (!clock_req_o && core_clock && !clock_ready_sync) clock_req_o<=1;
        end
    end
    power_manager #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) core(
        .clk_i(aon_clk_i),.rst_ni(aon_rst_no),
        .sleep_req_i(sleep_req_i && sleep_armed_q && sleep_ready_o),
        .wake_i(wake_event_o),.idle_i(quiesce_req_q && quiesced_o),
        .clock_ready_i(clock_req_o && clock_ready_sync),
        .block_work_o(core_block),.isolate_o(isolate_o),.clk_en_o(core_clock),
        .sleeping_o(sleeping_o),.active_o(active_o),.fault_o(fault_o),.state_o(state_o));
endmodule
