`timescale 1ns/1ps
// Independent reference: observes only public interfaces, never worker internals.
// Inputs/handshakes are sampled before NBA; responses/controls after NBA.
module transaction_scoreboard (
    input wire clk_i, rst_ni, clk_en_i, block_work_i, isolate_i, active_i,
    input wire req_valid_i, req_ready_i, idle_i, done_i,
    input wire [31:0] req_id_i, done_id_i,
    input integer req_cycles_i, accepted_i, completed_i
);
    integer pending=0, age=0, expected_latency=0;
    reg [31:0] expected_id=0;
    integer epoch_accepted=0, epoch_completed=0;
    integer total_accepted=0, total_completed=0, total_canceled=0;
    reg expected_ready, expected_done;
    // A separate reset process remains sensitive while the sampling process
    // waits for NBA outputs. Otherwise an asynchronous reset inside #1 is lost.
    task reset_epoch;
        begin
            total_canceled = total_canceled + pending;
            pending=0; age=0; epoch_accepted=0; epoch_completed=0;
        end
    endtask
    always @(negedge rst_ni) reset_epoch();
    always @(posedge clk_i) begin
        if (!rst_ni) reset_epoch();
        else begin
            expected_ready = clk_en_i && !block_work_i && (pending==0);
            if (req_ready_i !== expected_ready) $fatal(1,"scoreboard: incorrect request readiness");
            if (!block_work_i && (!active_i || !clk_en_i || isolate_i))
                $fatal(1,"scoreboard: unsafe work admission");
            expected_done=0;
            if (pending && clk_en_i) begin
                age=age+1;
                if (age==expected_latency) begin
                    expected_done=1;
                    pending=0;
                    epoch_completed=epoch_completed+1;
                    total_completed=total_completed+1;
                end
            end
            if (req_valid_i && expected_ready) begin
                if (req_cycles_i<1) $fatal(1,"scoreboard: invalid latency");
                pending=1; age=0; expected_latency=req_cycles_i; expected_id=req_id_i;
                epoch_accepted=epoch_accepted+1;
                total_accepted=total_accepted+1;
            end
            #1;
            if (rst_ni) begin
                if (done_i !== expected_done) $fatal(1,"scoreboard: missing or unexpected completion");
                if (done_i && done_id_i !== expected_id) $fatal(1,"scoreboard: completion ID mismatch");
                if (idle_i !== (pending==0)) $fatal(1,"scoreboard: idle disagrees with outstanding work");
                if (accepted_i !== epoch_accepted || completed_i !== epoch_completed)
                    $fatal(1,"scoreboard: transaction count mismatch");
                if (!clk_en_i && (pending!=0 || !isolate_i || !block_work_i))
                    $fatal(1,"scoreboard: unsafe clock shutdown with outstanding work");
                if (isolate_i && pending!=0)
                    $fatal(1,"scoreboard: isolation before work completed");
            end
        end
    end
    task check_empty;
        begin
            if (pending!=0 || total_accepted != total_completed+total_canceled)
                $fatal(1,"scoreboard: outstanding transactions at end of test");
            $display("PASS: scoreboard accepted=%0d completed=%0d reset-canceled=%0d outstanding=%0d",
                total_accepted,total_completed,total_canceled,pending);
        end
    endtask
endmodule
