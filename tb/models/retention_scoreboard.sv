`timescale 1ns/1ps
// Reference state comes only from accepted workload writes, never the saved bank.
module retention_scoreboard(
    input wire aon_clk_i, domain_clk_i, arst_ni, domain_rst_ni,
    input wire power_good_i, power_enable_i, gate_i, clock_req_i,
    input wire isolate_i, active_i, fault_i, block_i,
    input wire req_valid_i, req_ready_i, done_i, save_req_i, save_ack_i,
    input wire restore_req_i, restore_ack_i,
    input wire [31:0] req_data_i, raw_i, clamped_i,
    input integer work_cycles_i
);
    reg [31:0] expected_value=0, pending_value=0;
    integer pending=0, age=0, latency=0;
    integer accepted=0, completed=0, canceled=0, restores=0, saves=0;
    reg expected_done, previous_save=0, previous_restore=0;
    // Global reset deliberately discards the architectural retained value.
    always @(negedge arst_ni) expected_value=0;
    always @(negedge domain_rst_ni) begin
        canceled=canceled+pending; pending=0; age=0;
        previous_save=0; previous_restore=0;
    end
    always @(posedge domain_clk_i) begin
        if (domain_rst_ni) begin
            expected_done=0;
            if (pending) begin
                age=age+1;
                if (age==latency) begin
                    expected_value=pending_value; pending=0; completed=completed+1; expected_done=1;
                end
            end
            if (req_valid_i && req_ready_i) begin
                if (pending || block_i || isolate_i) $fatal(1,"retention scoreboard: unsafe admission");
                pending=1; age=0; latency=work_cycles_i; pending_value=req_data_i; accepted=accepted+1;
            end
            #1;
            if (domain_rst_ni) begin
                if (done_i !== expected_done) $fatal(1,"retention scoreboard: completion mismatch");
                if (save_ack_i && !previous_save) begin
                    if (!save_req_i || pending || raw_i !== expected_value)
                        $fatal(1,"retention scoreboard: invalid saved value");
                    saves=saves+1;
                end
                if (restore_ack_i && !previous_restore) begin
                    if (!restore_req_i || raw_i !== expected_value)
                        $fatal(1,"retention scoreboard: restored data mismatch");
                    restores=restores+1;
                end
                previous_save=save_ack_i; previous_restore=restore_ack_i;
                if (expected_done && raw_i !== expected_value)
                    $fatal(1,"retention scoreboard: completed write mismatch");
            end
        end
    end
    always @(posedge aon_clk_i) begin
        #2;
        if (arst_ni) begin
            if (isolate_i && clamped_i !== 32'b0) $fatal(1,"retention scoreboard: clamp leaked");
            if (!isolate_i && !fault_i && raw_i !== expected_value)
                $fatal(1,"retention scoreboard: exposed data mismatch");
            if (active_i && (!power_good_i || !domain_rst_ni || !gate_i || isolate_i))
                $fatal(1,"retention scoreboard: unsafe RUN");
            if (!fault_i && (!power_enable_i || isolate_i) && pending)
                $fatal(1,"retention scoreboard: shutdown before completion");
            if (!power_enable_i && (clock_req_i || gate_i || domain_rst_ni || !isolate_i))
                $fatal(1,"retention scoreboard: unsafe power removal");
        end
    end
    task check_empty;
        begin
            if (pending || accepted!=completed+canceled)
                $fatal(1,"retention scoreboard: unaccounted work");
            $display("PASS: M4 accounting accepted=%0d completed=%0d canceled=%0d saves=%0d restores=%0d",
                accepted,completed,canceled,saves,restores);
        end
    endtask
endmodule
