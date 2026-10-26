`timescale 1ns/1ps
module tb_workload;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, sleep_req=0, wake=0, ready=1, valid=0;
    reg [31:0] id=0;
    integer latency=1;
    wire block_work, isolate, clk_en, sleeping, active, fault;
    wire idle, req_ready, done;
    wire [31:0] done_id;
    wire [2:0] state;
    wire signed [31:0] accepted, completed;
    integer checks=0;
    power_manager #(.TIMEOUT_CYCLES(4)) dut(
        .clk_i(clk), .rst_ni(rst_n), .sleep_req_i(sleep_req), .wake_i(wake),
        .idle_i(idle), .clock_ready_i(ready), .block_work_o(block_work),
        .isolate_o(isolate), .clk_en_o(clk_en), .sleeping_o(sleeping),
        .active_o(active), .fault_o(fault), .state_o(state));
    managed_workload worker(
        .clk_i(clk), .rst_ni(rst_n), .clk_en_i(clk_en), .block_work_i(block_work),
        .req_valid_i(valid), .req_id_i(id), .req_cycles_i(latency),
        .req_ready_o(req_ready), .idle_o(idle), .done_o(done), .done_id_o(done_id),
        .accepted_o(accepted), .completed_o(completed));
    transaction_scoreboard scoreboard(
        .clk_i(clk), .rst_ni(rst_n), .clk_en_i(clk_en), .block_work_i(block_work),
        .isolate_i(isolate), .active_i(active), .req_valid_i(valid),
        .req_ready_i(req_ready), .idle_i(idle), .done_i(done), .req_id_i(id),
        .done_id_i(done_id), .req_cycles_i(latency),
        .accepted_i(accepted), .completed_i(completed));
    task tick; begin @(posedge clk); #3; end endtask
    task check(input reg ok, input string label_text);
        begin
            checks=checks+1;
            if (ok !== 1'b1) $fatal(1,"FAIL: %s state=%0d",label_text,state);
        end
    endtask
    task boot;
        begin
            @(negedge clk); rst_n=0; valid=0; sleep_req=0; wake=0; ready=1;
            tick(); @(negedge clk); rst_n=1;
            tick(); tick(); check(active && idle,"boot ready for work");
        end
    endtask
    task submit(input integer tag, input integer cycles, input reg sleep_too);
        begin
            @(negedge clk); valid=1; id=tag; latency=cycles; sleep_req=sleep_too;
            check(req_ready,"request can be accepted"); tick();
            @(negedge clk); valid=0;
        end
    endtask
    initial begin
        $dumpfile("build/workload.vcd"); $dumpvars(0,tb_workload);
        boot();
        // The RUN->DRAIN edge may still accept work: idle must reflect that work.
        submit(11,3,1);
        check(state==1 && !idle && accepted==1,"entry-edge transaction accepted");
        valid=1; id=99; // Offered work must be rejected throughout shutdown.
        repeat(2) begin tick(); check(state==1 && !req_ready,"busy drain blocks new work"); end
        tick(); check(done && done_id==11 && completed==1,"work completes in DRAIN");
        tick(); check(state==2 && idle,"isolation follows completion");
        tick(); check(sleeping && accepted==1,"sleep with no rejected work accepted");
        repeat(3) begin tick(); check(!done && accepted==1 && completed==1,"sleep freezes work"); end
        @(negedge clk); wake=1; ready=0;
        tick(); check(state==4 && !req_ready,"wake waits for clock readiness");
        @(negedge clk); wake=0;
        tick(); check(accepted==1,"no admission during START");
        @(negedge clk); ready=1;
        tick(); check(state==5 && !req_ready,"no admission during RELEASE");
        tick(); check(active && accepted==1,"RUN restored before admission");
        tick(); check(accepted==2,"held offer accepted after wake");
        @(negedge clk); valid=0;
        repeat(3) tick(); check(idle && completed==2 && done_id==99,"post-wake work completes");

        boot(); submit(21,3,1);
        wake=1; tick(); check(active && !idle && !fault,"wake abort preserves pending work");
        @(negedge clk); wake=0;
        repeat(2) tick(); check(done && done_id==21 && completed==1,"aborted entry finishes work");

        boot(); submit(31,7,1);
        repeat(4) tick(); check(active && fault && !idle,"drain timeout resumes pending work");
        repeat(3) tick(); check(done && done_id==31 && completed==1,"timeout loses no transaction");
        @(negedge clk); sleep_req=0; tick();
        @(negedge clk); sleep_req=1;
        tick(); tick(); tick(); check(sleeping && fault,"rearmed sleep after drain fault");

        boot(); submit(41,7,0);
        boot(); check(accepted==0 && completed==0,"reset cancels pending work and clears counts");
        submit(42,1,0); tick(); check(done && done_id==42,"new reset epoch completes correctly");
        check(accepted==completed && idle,"final workload is empty");
        scoreboard.check_empty();
        $display("PASS: workload 4 scenarios, %0d explicit checks",checks);
        $finish;
    end
    initial begin #10000; $fatal(1,"workload watchdog expired"); end
endmodule
