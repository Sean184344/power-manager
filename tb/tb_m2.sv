`timescale 1ns/1ps
module tb_m2;
    parameter integer TIMEOUT=8;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, sleep_req=0, wake=0, valid=0;
    reg [31:0] id=0;
    integer latency=1, clock_delay=1;
    wire block_work, isolate, clk_en, sleeping, active, fault, ready;
    wire idle, req_ready, done;
    wire [31:0] done_id;
    wire [2:0] state;
    wire signed [31:0] accepted, completed, chosen_delay;
    wire usable_clock=clk_en && ready;
    integer checks=0, run_index, delay_used, seed=1;
    reg [31:0] rng;
    integer coverage_file, phase_age=0, observed_state=-1;
    string coverage_path, wave_path;
    function automatic integer choose(input integer limit);
        begin
            rng=rng ^ (rng << 13); rng=rng ^ (rng >> 17); rng=rng ^ (rng << 5);
            choose=rng % limit;
        end
    endfunction
    // Coverage observes pre-edge events, not stimulus task invocations.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin phase_age=0; observed_state=-1; end
        else begin
            if (state==observed_state) phase_age=phase_age+1;
            else phase_age=1;
            observed_state=state;
            if (state==4 && phase_age==1)
                $fdisplay(coverage_file,"clock.delay.%0d",chosen_delay);
            if (wake) begin
                case (state)
                    0: $fdisplay(coverage_file,"wake.RUN.%s",idle ? "idle" : "busy");
                    1: $fdisplay(coverage_file,"wake.DRAIN.%s.%s",idle ? "idle" : "busy",
                        phase_age==TIMEOUT ? "deadline" : "early");
                    2: $fdisplay(coverage_file,"wake.ISOLATE.idle");
                    3: $fdisplay(coverage_file,"wake.SLEEP.idle");
                    4: $fdisplay(coverage_file,"wake.START.%s.%s",ready ? "ready" : "waiting",
                        phase_age==TIMEOUT ? "deadline" : "early");
                    5: $fdisplay(coverage_file,"wake.RELEASE.idle");
                    6: $fdisplay(coverage_file,"wake.FAULT.idle");
                endcase
            end
            if (state==1 && !wake) begin
                if (idle) $fdisplay(coverage_file,"idle.DRAIN.%s",phase_age==TIMEOUT ? "deadline" : "early");
                else if (phase_age==TIMEOUT) $fdisplay(coverage_file,"timeout.DRAIN");
            end
            if (state==4) begin
                if (ready) $fdisplay(coverage_file,"ready.START.%s",phase_age==TIMEOUT ? "deadline" : "early");
                else if (phase_age==TIMEOUT) $fdisplay(coverage_file,"timeout.START");
            end
        end
    end
    // Output contract is checked after every state update.
    always @(posedge clk) begin
        #2;
        if (rst_n) begin
            if (active !== (state==0) || sleeping !== (state==3) ||
                block_work !== (state!=0) || isolate !== (state!=0 && state!=1) ||
                clk_en !== (state!=3)) $fatal(1,"M2: state/output contract violated");
            if (active && !ready) $fatal(1,"M2: RUN without usable clock");
        end
    end
`ifdef USE_DEFAULT_TIMEOUT
    power_manager dut(
`else
    power_manager #(.TIMEOUT_CYCLES(TIMEOUT)) dut(
`endif
        .clk_i(clk), .rst_ni(rst_n), .sleep_req_i(sleep_req), .wake_i(wake),
        .idle_i(idle), .clock_ready_i(ready), .block_work_o(block_work),
        .isolate_o(isolate), .clk_en_o(clk_en), .sleeping_o(sleeping),
        .active_o(active), .fault_o(fault), .state_o(state));
    clock_controller #(.MAX_DELAY(TIMEOUT+2)) clock_model(
        .clk_i(clk), .rst_ni(rst_n), .enable_i(clk_en), .delay_i(clock_delay),
        .ready_o(ready), .chosen_delay_o(chosen_delay));
    managed_workload worker(
        .clk_i(clk), .rst_ni(rst_n), .clk_en_i(usable_clock), .block_work_i(block_work),
        .req_valid_i(valid), .req_id_i(id), .req_cycles_i(latency),
        .req_ready_o(req_ready), .idle_o(idle), .done_o(done), .done_id_o(done_id),
        .accepted_o(accepted), .completed_o(completed));
    transaction_scoreboard scoreboard(
        .clk_i(clk), .rst_ni(rst_n), .clk_en_i(usable_clock), .block_work_i(block_work),
        .isolate_i(isolate), .active_i(active), .req_valid_i(valid),
        .req_ready_i(req_ready), .idle_i(idle), .done_i(done), .req_id_i(id),
        .done_id_i(done_id), .req_cycles_i(latency),
        .accepted_i(accepted), .completed_i(completed));
    task tick; begin @(posedge clk); #3; end endtask
    task drive; begin @(negedge clk); #1; end endtask
    task check(input reg ok, input string label_text);
        begin
            checks=checks+1;
            if (ok !== 1'b1) $fatal(1,"M2: %s state=%0d timeout=%0d",label_text,state,TIMEOUT);
        end
    endtask
    task boot;
        begin
            drive(); rst_n=0; valid=0; sleep_req=0; wake=0; clock_delay=1;
            tick(); rst_n=1; // before the falling edge where readiness is modeled
            tick(); check(state==5,"reset readiness accepted");
            tick(); check(active && idle && !fault,"boot RUN");
        end
    endtask
    task sleep_empty;
        begin
            drive(); sleep_req=1; tick(); check(state==1,"empty DRAIN");
            tick(); check(state==2,"empty ISOLATE");
            tick(); check(sleeping,"empty SLEEP");
            drive(); sleep_req=0; // also let the clock model clear stale ready
        end
    endtask
    task restart(input integer delay_setting);
        integer edge_index;
        begin
            clock_delay=delay_setting; wake=1;
            tick(); check(state==4,"sampled wake leaves SLEEP");
            drive(); wake=0; delay_used=chosen_delay;
            check(delay_used>=1 && delay_used<=TIMEOUT+2,"clock delay range");
            if (delay_setting>0) check(delay_used==delay_setting,"directed clock delay honored");
            for (edge_index=1; edge_index<=TIMEOUT && edge_index<delay_used; edge_index=edge_index+1) begin
                tick();
                if (edge_index==TIMEOUT) check(state==6 && fault,"late ready faults");
                else check(state==4 && !req_ready,"waiting for usable clock");
            end
            if (delay_used<=TIMEOUT) begin
                tick(); check(state==5 && ready && !fault,"ready wins including deadline");
                tick(); check(active,"release completes");
            end else begin
                repeat(3) tick(); check(state==6 && fault && block_work && isolate,"late ready cannot exit FAULT");
            end
        end
    endtask
    task entry(input integer cycles);
        begin
            drive(); sleep_req=1; valid=(cycles>0); latency=cycles; id=id+1;
            tick(); check(state==1,"entry reaches DRAIN");
            drive(); valid=0;
        end
    endtask
    task finish_work;
        integer guard;
        begin
            guard=0;
            while (!idle && guard<TIMEOUT+8) begin tick(); guard=guard+1; end
            check(idle,"all accepted work finishes");
            check(accepted==completed,"epoch has no transaction loss");
        end
    endtask
    task drain_wake(input integer cycles, input integer arrival);
        begin
            boot(); entry(cycles);
            repeat(arrival-1) tick();
            // entry() already leaves inputs at a falling edge; otherwise move there.
            if (arrival>1) drive();
            wake=1; tick(); check(active && !fault,"wake wins DRAIN arbitration");
            drive(); wake=0; finish_work();
            repeat(2) tick(); check(active,"held sleep request cannot retrigger abort");
        end
    endtask
    task start_wake(input integer ack_delay, input integer arrival);
        begin
            boot(); sleep_empty(); clock_delay=ack_delay; wake=1;
            tick(); check(state==4,"wake enters START");
            drive(); wake=0;
            repeat(arrival-1) tick();
            if (arrival>1) drive();
            wake=1; tick();
            if (ack_delay<=arrival) check(state==5 && !fault,"ready beats START timeout and wake");
            else if (arrival==TIMEOUT) check(state==6 && fault,"wake cannot override START timeout");
            else check(state==4,"wake retained while clock starts");
            drive(); wake=0;
            repeat(TIMEOUT+3) tick();
            if (ack_delay<=TIMEOUT) check(active && !fault,"START wake resumes RUN");
            else begin
                check(state==6 && fault,"FAULT remains locked");
                drive(); wake=1; sleep_req=1; tick(); check(state==6,"FAULT ignores requests");
            end
        end
    endtask
    integer sample_latency, arrival, do_wake;
    initial begin
        if ($value$plusargs("SEED=%d",seed)) begin end
        rng=seed; if (rng==0) rng=1;
        coverage_path="build/m2-events.csv";
        if ($value$plusargs("COVERAGE=%s",coverage_path)) begin end
        coverage_file=$fopen(coverage_path,"w");
        if (!coverage_file) $fatal(1,"cannot open coverage output");
        $fdisplay(coverage_file,"bin");
        if ($value$plusargs("VCD=%s",wave_path)) begin
            $dumpfile(wave_path); $dumpvars(0,tb_m2);
        end
        $display("M2 replay: TIMEOUT=%0d SEED=%0d",TIMEOUT,seed);

        // RUN wake crossed with idle/busy. Busy wake suppresses simultaneous sleep.
        boot(); drive(); wake=1; sleep_req=1; tick(); check(active,"RUN idle wake priority");
        boot(); drive(); valid=1; id=id+1; latency=3; tick();
        drive(); valid=0; wake=1; sleep_req=1; tick(); check(active && !idle,"RUN busy wake priority");
        drive(); wake=0; sleep_req=0; finish_work();

        // Empty/occupied DRAIN, before/on its deadline. L=N-1 finishes just
        // before the deadline; L=N completes on the same edge as the wake.
        drain_wake(0,1);
        drain_wake(TIMEOUT+2,1);
        drain_wake(TIMEOUT-1,TIMEOUT);
        drain_wake(TIMEOUT+2,TIMEOUT);
        drain_wake(TIMEOUT,TIMEOUT);
        boot(); entry(TIMEOUT-1); repeat(TIMEOUT) tick();
        check(state==2 && !fault,"idle wins DRAIN deadline");
        tick(); check(sleeping,"deadline drain sleeps");
        boot(); entry(TIMEOUT+2); repeat(TIMEOUT) tick();
        check(active && fault,"busy DRAIN timeout"); finish_work();

        boot(); entry(0); tick(); check(state==2,"reach ISOLATE");
        drive(); wake=1; tick(); check(state==5 && clk_en,"wake cancels clock shutdown");
        drive(); wake=0; tick(); check(active,"isolation wake recovers");

        // START wake crosses readiness and deadline position.
        start_wake(1,1);
        start_wake(TIMEOUT+1,1);
        start_wake(TIMEOUT,TIMEOUT);
        start_wake(TIMEOUT+1,TIMEOUT);
        boot(); sleep_empty(); clock_delay=1; wake=1;
        tick(); drive(); wake=0; tick(); check(state==5,"reach RELEASE");
        drive(); wake=1; tick(); check(active,"wake during RELEASE");

        // Every legal clock delay plus two late delays is guaranteed to run.
        for (run_index=1;run_index<=TIMEOUT+2;run_index=run_index+1) begin
            boot(); sleep_empty(); restart(run_index);
        end
        // Seeded clock latency regression.
        for (run_index=0;run_index<32;run_index=run_index+1) begin
            boot(); sleep_empty(); restart(0);
        end
        // Seeded workload latency and wake arrival regression. Each episode
        // settles all work before reset, so a reset cannot hide transaction loss.
        for (run_index=0;run_index<100;run_index=run_index+1) begin
            boot(); sample_latency=1+choose(TIMEOUT+3);
            arrival=1+choose(TIMEOUT); do_wake=choose(2);
            entry(sample_latency);
            repeat(arrival-1) tick();
            if (arrival>1) drive();
            wake=do_wake; tick(); drive(); wake=0;
            while (state==1) tick();
            finish_work();
            if (state==2) tick();
            if (sleeping) begin drive(); sleep_req=0; restart(0); end
            else begin
                while (state==4 || state==5) tick();
                check(active,"drain abort or timeout stays active");
            end
        end
        finish_work();
        scoreboard.check_empty();
        $fclose(coverage_file);
        $display("PASS: M2 timeout=%0d seed=%0d checks=%0d accepted=%0d completed=%0d",
            TIMEOUT,seed,checks,scoreboard.total_accepted,scoreboard.total_completed);
        $finish;
    end
    initial begin #1000000; $fatal(1,"M2 watchdog expired"); end
endmodule
