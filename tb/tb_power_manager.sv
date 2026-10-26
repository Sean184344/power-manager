`timescale 1ns/1ps
module tb_power_manager;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, sleep_req=0, wake=0, idle=0, ready=1;
    wire block_work, isolate, clk_en, sleeping, active, fault;
    wire [2:0] state;
    integer checks=0, cases=0, k;
    power_manager #(.TIMEOUT_CYCLES(4)) dut(
        .clk_i(clk), .rst_ni(rst_n), .sleep_req_i(sleep_req), .wake_i(wake),
        .idle_i(idle), .clock_ready_i(ready), .block_work_o(block_work),
        .isolate_o(isolate), .clk_en_o(clk_en), .sleeping_o(sleeping),
        .active_o(active), .fault_o(fault), .state_o(state));
    task tick; begin @(posedge clk); #1; end endtask
    task check(input reg ok, input string label_text);
        begin
            checks=checks+1;
            if (ok !== 1'b1) $fatal(1,"FAIL: %s state=%0d",label_text,state);
        end
    endtask
    task reset_dut;
        begin
            @(negedge clk); rst_n=0; sleep_req=0; wake=0; idle=0; ready=1;
            tick(); @(negedge clk); rst_n=1;
            tick(); tick(); check(active,"boot reaches RUN");
        end
    endtask
    task begin_sleep;
        begin @(negedge clk); sleep_req=1; idle=0; tick(); check(state==1,"enter DRAIN"); end
    endtask
    task reach_sleep;
        begin
            begin_sleep(); @(negedge clk); idle=1;
            tick(); check(state==2 && clk_en && isolate,"isolate before stopping clock");
            tick(); check(sleeping && !clk_en,"reach SLEEP");
        end
    endtask
    // Interface safety properties sampled after sequential updates.
    always @(posedge clk) begin
        #2;
        if (rst_n) begin
            if (!clk_en && (!isolate || !block_work)) $fatal(1,"unsafe clock shutdown");
            if (!block_work && (!clk_en || isolate || !active)) $fatal(1,"unsafe work release");
            if (sleeping && clk_en) $fatal(1,"sleep clock request asserted");
        end
    end
    initial begin
        $dumpfile("build/power_manager.vcd"); $dumpvars(0,tb_power_manager);
        reset_dut(); reach_sleep();
        @(negedge clk); ready=0; wake=1; tick(); check(state==4 && clk_en && isolate,"wake starts clock");
        @(negedge clk); wake=0; tick(); check(state==4,"wait for ready");
        @(negedge clk); ready=1; tick(); check(state==5 && isolate,"release guard");
        tick(); check(active && !fault,"normal wake completes"); cases=cases+1;
        // Holding sleep high must not immediately put us back to sleep.
        repeat(6) begin tick(); check(active,"held sleep request is not retriggered"); end
        @(negedge clk); sleep_req=0; tick(); begin_sleep(); cases=cases+1;

        reset_dut(); @(negedge clk); sleep_req=1; wake=1; tick();
        check(active,"wake wins simultaneous sleep"); cases=cases+1;
        reset_dut(); begin_sleep(); @(negedge clk); idle=1; wake=1; tick();
        check(active && !fault,"wake wins idle completion"); cases=cases+1;
        reset_dut(); begin_sleep(); @(negedge clk); idle=1; tick();
        @(negedge clk); wake=1; tick(); check(state==5 && clk_en,"wake in isolation cancels shutdown");
        @(negedge clk); wake=0; tick(); check(active,"isolation abort resumes"); cases=cases+1;

        reset_dut(); begin_sleep(); repeat(3) tick(); check(state==1,"no premature drain timeout");
        tick(); check(active && fault,"drain timeout aborts safely");
        repeat(3) tick(); check(active && fault,"timeout fault is sticky"); cases=cases+1;
        reset_dut(); begin_sleep(); repeat(3) tick();
        @(negedge clk); wake=1; tick(); check(active && !fault,"wake wins drain deadline"); cases=cases+1;
        reset_dut(); begin_sleep(); repeat(3) tick();
        @(negedge clk); idle=1; tick(); check(state==2 && !fault,"idle wins drain deadline"); cases=cases+1;

        reset_dut(); reach_sleep(); @(negedge clk); ready=0; wake=1; tick();
        @(negedge clk); wake=0; repeat(3) tick(); check(state==4,"no premature start timeout");
        tick(); check(state==6 && fault && isolate && block_work,"clock timeout fails closed");
        @(negedge clk); ready=1; repeat(2) tick(); check(state==6,"FAULT requires reset"); cases=cases+1;
        reset_dut(); reach_sleep(); @(negedge clk); ready=0; wake=1; tick();
        @(negedge clk); wake=0; repeat(3) tick(); @(negedge clk); ready=1; tick();
        check(state==5 && !fault,"clock ready wins deadline"); tick(); check(active,"deadline wake completes"); cases=cases+1;

        // Assert reset in every reachable operating state (0..5).
        for (k=0;k<6;k=k+1) begin
            reset_dut();
            if (k>=1) begin_sleep();
            if (k>=2) begin @(negedge clk); idle=1; tick(); end
            if (k>=3) tick();
            if (k>=4) begin @(negedge clk); wake=1; tick(); end
            if (k>=5) tick();
            check(state==k,"reset test reached target state");
            @(negedge clk); rst_n=0; #1;
            check(state==4 && isolate && block_work && clk_en && !fault,"reset safe outputs");
            cases=cases+1;
        end
        reset_dut(); check(active && !fault,"reset clears fault and recovers");
        $display("PASS: %0d scenarios, %0d explicit checks plus continuous safety monitors",cases,checks);
        $finish;
    end
    initial begin #20000; $fatal(1,"global test watchdog expired"); end
endmodule
