`timescale 1ns/1ps
// M4 power-gating sequencer. Reuses M3 crossing primitives; v0.1/M3 remain
// separate clock-sleep configurations. All physical controls are requests.
module power_manager_retention #(
    parameter integer TIMEOUT_CYCLES=64
)(
    input wire aon_clk_i, domain_clk_i, wake_clk_i, arst_ni,
    input wire sleep_req_i, wake_pulse_i,
    input wire power_good_i, clock_ready_i, domain_idle_i,
    input wire save_ack_i, restore_ack_i,
    output wire wake_ready_o, aon_rst_no, domain_rst_no,
    output wire domain_block_work_o, domain_save_req_o, domain_restore_req_o,
    output reg power_enable_o, clock_req_o,
    output wire isolate_o,
    output wire active_o, sleeping_o, fault_o,
    output wire [3:0] state_o
);
    localparam [3:0] OFF_WAIT=0, OFF=1, POWER_ON=2, CLOCK_ON=3,
        RESET_RELEASE=4, RESTORE=5, RESTORE_CLEAR=6, REOPEN=7, RUN=8,
        DRAIN=9, SAVE=10, SAVE_CLEAR=11, ISOLATE=12, STOP_CLOCK=13,
        POWER_DOWN=14, FAULT=15;
    reg [3:0] state_q, state_d;
    integer count_q;
    reg boot_q, wake_pending_q, sleep_armed_q, saved_q;
    reg block_req, save_req, restore_req, release_reset, isolate_req;
    wire wake_rst_n, wake_event, pg, ready, save_ack, restore_ack;
    wire quiesced, released, domain_reset_released, domain_reset_sync;
    reg domain_ack_q;
    wire wake_seen=wake_event || wake_pending_q;
    wire expired=(count_q==TIMEOUT_CYCLES-1);
    wire domain_arst_n=arst_ni && power_good_i && release_reset;
    // Keep reset asserted even before a stopped domain has seen its first edge.
    assign domain_rst_no=domain_arst_n && domain_reset_sync;
    assign state_o=state_q;
    assign active_o=(state_q==RUN) && power_good_i && domain_rst_no;
    assign isolate_o=isolate_req || !power_good_i;
    assign sleeping_o=(state_q==OFF);
    assign fault_o=(state_q==FAULT);
    initial begin
        if (TIMEOUT_CYCLES<4) $fatal(1,"M4 TIMEOUT_CYCLES must be at least 4");
    end

    cdc_reset aon_reset(.clk_i(aon_clk_i),.arst_ni(arst_ni),.rst_no(aon_rst_no));
    cdc_reset wake_reset(.clk_i(wake_clk_i),.arst_ni(arst_ni),.rst_no(wake_rst_n));
    cdc_reset domain_reset(.clk_i(domain_clk_i),.arst_ni(domain_arst_n),.rst_no(domain_reset_sync));
    cdc_event wake_bridge(.src_clk_i(wake_clk_i),.src_rst_ni(wake_rst_n),
        .pulse_i(wake_pulse_i),.ready_o(wake_ready_o),.dst_clk_i(aon_clk_i),
        .dst_rst_ni(aon_rst_no),.pulse_o(wake_event));
    cdc_level pg_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(power_good_i),.sync_o(pg));
    cdc_level ready_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(clock_ready_i),.sync_o(ready));
    cdc_level save_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(save_ack_i),.sync_o(save_ack));
    cdc_level restore_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(restore_ack_i),.sync_o(restore_ack));
    cdc_level reset_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(domain_rst_no),.sync_o(domain_reset_released));
    cdc_level #(.RESET_VALUE(1'b1)) block_sync(.clk_i(domain_clk_i),.rst_ni(domain_rst_no),
        .async_i(block_req),.sync_o(domain_block_work_o));
    cdc_level save_request(.clk_i(domain_clk_i),.rst_ni(domain_rst_no),
        .async_i(save_req),.sync_o(domain_save_req_o));
    cdc_level restore_request(.clk_i(domain_clk_i),.rst_ni(domain_rst_no),
        .async_i(restore_req),.sync_o(domain_restore_req_o));
    always @(posedge domain_clk_i or negedge domain_rst_no) begin
        if (!domain_rst_no) domain_ack_q<=0;
        else if (!domain_block_work_o) domain_ack_q<=0;
        else if (domain_idle_i) domain_ack_q<=1;
    end
    cdc_level quiesce_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(domain_ack_q),.sync_o(quiesced));
    cdc_level release_sync(.clk_i(aon_clk_i),.rst_ni(aon_rst_no),.async_i(!domain_block_work_o),.sync_o(released));

    always @* begin
        state_d=state_q;
        case (state_q)
            // Let reset-zeroed synchronizers sample the actual acknowledgements
            // before treating their low values as a completed OFF handshake.
            OFF_WAIT: if (count_q>=3 && !pg && !ready) state_d=OFF;
                      else if (expired) state_d=FAULT;
            OFF: if (boot_q || wake_seen) state_d=POWER_ON;
            POWER_ON: if (pg) state_d=CLOCK_ON; else if (expired) state_d=FAULT;
            CLOCK_ON: if (ready) state_d=RESET_RELEASE; else if (expired) state_d=FAULT;
            RESET_RELEASE: if (domain_reset_released && quiesced && !save_ack && !restore_ack)
                               state_d=saved_q ? RESTORE : REOPEN;
                           else if (expired) state_d=FAULT;
            RESTORE: if (restore_ack) state_d=RESTORE_CLEAR; else if (expired) state_d=FAULT;
            RESTORE_CLEAR: if (!restore_ack) state_d=REOPEN; else if (expired) state_d=FAULT;
            REOPEN: if (released && !quiesced) state_d=RUN; else if (expired) state_d=FAULT;
            RUN: if (sleep_req_i && sleep_armed_q && !wake_seen) state_d=DRAIN;
            DRAIN: if (quiesced) state_d=SAVE; else if (expired) state_d=FAULT;
            SAVE: if (save_ack) state_d=SAVE_CLEAR; else if (expired) state_d=FAULT;
            SAVE_CLEAR: if (!save_ack) state_d=ISOLATE; else if (expired) state_d=FAULT;
            ISOLATE: state_d=STOP_CLOCK;
            STOP_CLOCK: if (!ready) state_d=POWER_DOWN; else if (expired) state_d=FAULT;
            POWER_DOWN: if (!pg) state_d=OFF; else if (expired) state_d=FAULT;
            FAULT: state_d=FAULT;
            default: state_d=FAULT;
        endcase
        // Unexpected supply/clock loss after startup cannot resume using an old
        // snapshot. Only global reset can recover from these faults.
        if (state_q>=CLOCK_ON && state_q<=STOP_CLOCK && !pg) state_d=FAULT;
        if (state_q>=RESET_RELEASE && state_q<=ISOLATE && !ready) state_d=FAULT;
    end

    always @(posedge aon_clk_i or negedge aon_rst_no) begin
        if (!aon_rst_no) begin
            state_q<=OFF_WAIT; count_q<=0; boot_q<=1;
            wake_pending_q<=0; sleep_armed_q<=1; saved_q<=0;
        end else begin
            state_q<=state_d;
            if (state_d!=state_q || state_q==RUN || state_q==OFF) count_q<=0;
            else if (!expired) count_q<=count_q+1;
            if (state_q==OFF && state_d==POWER_ON) begin boot_q<=0; wake_pending_q<=0; end
            else if (state_q==RUN) wake_pending_q<=0;
            else if (wake_event) wake_pending_q<=1;
            if (!sleep_req_i) sleep_armed_q<=1;
            else if (state_q==RUN && state_d==DRAIN) sleep_armed_q<=0;
            if (state_q==SAVE && save_ack) saved_q<=1;
        end
    end

    always @* begin
        power_enable_o=1; clock_req_o=1; isolate_req=1;
        block_req=1; save_req=0; restore_req=0; release_reset=0;
        case (state_q)
            OFF_WAIT, OFF, POWER_DOWN: begin power_enable_o=0; clock_req_o=0; end
            POWER_ON, FAULT: clock_req_o=0;
            CLOCK_ON, STOP_CLOCK: begin
                if (state_q==STOP_CLOCK) clock_req_o=0;
            end
            RESET_RELEASE: release_reset=1;
            RESTORE: begin release_reset=1; restore_req=1; end
            RESTORE_CLEAR: release_reset=1;
            REOPEN, RUN: begin release_reset=1; block_req=0; isolate_req=0; end
            DRAIN: begin release_reset=1; isolate_req=0; end
            SAVE: begin release_reset=1; isolate_req=0; save_req=1; end
            SAVE_CLEAR: begin release_reset=1; isolate_req=0; end
            ISOLATE: release_reset=1;
            default: begin power_enable_o=0; clock_req_o=0; end
        endcase
    end
endmodule
