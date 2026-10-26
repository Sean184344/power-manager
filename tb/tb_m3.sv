`timescale 1ns/1ps
module tb_m3;
    parameter integer SOURCE_HALF=3, SOURCE_PHASE=0, START_DELAY=1;
    localparam integer TIMEOUT=64;
    reg aon_clk=0, source_clk=0;
    always #5 aon_clk=~aon_clk;
    initial begin #(SOURCE_PHASE); forever #(SOURCE_HALF) source_clk=~source_clk; end
    reg arst_n=1, sleep_req=0, wake_pulse=0, valid=0, idle_allow=1, withhold_ready=0;
    reg [31:0] id=0;
    integer latency=1, start_delay=START_DELAY, stop_delay=1;
    wire domain_clk, gate_on, clock_ready, clock_req;
    wire aon_rst_n, domain_rst_n, wake_rst_n;
    wire domain_block, isolate, active, sleeping, fault, sleep_ready, quiesced;
    wire wake_ready, wake_event, idle, req_ready, done;
    wire [31:0] done_id;
    wire [2:0] state;
    wire signed [31:0] accepted, completed;
    integer checks=0, source_events=0, dest_events=0, total_events=0, delivered_total=0, canceled_events=0;
    integer cov, target, iteration;
    string coverage_path, wave_path;
    power_manager_cdc #(.TIMEOUT_CYCLES(TIMEOUT)) dut(
        .aon_clk_i(aon_clk),.domain_clk_i(domain_clk),.wake_clk_i(source_clk),.arst_ni(arst_n),
        .sleep_req_i(sleep_req),.wake_pulse_i(wake_pulse),.domain_idle_i(idle && idle_allow),
        .clock_ready_i(clock_ready),.wake_ready_o(wake_ready),.wake_event_o(wake_event),
        .aon_rst_no(aon_rst_n),.domain_rst_no(domain_rst_n),.wake_rst_no(wake_rst_n),
        .domain_block_work_o(domain_block),.isolate_o(isolate),.clock_req_o(clock_req),
        .active_o(active),.sleeping_o(sleeping),.fault_o(fault),.sleep_ready_o(sleep_ready),
        .quiesced_o(quiesced),.state_o(state));
    async_clock_controller clock_model(.raw_clk_i(source_clk),.arst_ni(arst_n),
        .request_i(clock_req),.withhold_ready_i(withhold_ready),.start_delay_i(start_delay),
        .stop_delay_i(stop_delay),.domain_clk_o(domain_clk),.ready_o(clock_ready),.gate_o(gate_on));
    managed_workload worker(.clk_i(domain_clk),.rst_ni(domain_rst_n),.clk_en_i(1'b1),
        .block_work_i(domain_block),.req_valid_i(valid),.req_id_i(id),.req_cycles_i(latency),
        .req_ready_o(req_ready),.idle_o(idle),.done_o(done),.done_id_o(done_id),
        .accepted_o(accepted),.completed_o(completed));
    transaction_scoreboard scoreboard(.clk_i(domain_clk),.rst_ni(domain_rst_n),.clk_en_i(1'b1),
        .block_work_i(domain_block),.isolate_i(isolate),.active_i(!domain_block),
        .req_valid_i(valid),.req_ready_i(req_ready),.idle_i(idle),.done_i(done),
        .req_id_i(id),.done_id_i(done_id),.req_cycles_i(latency),
        .accepted_i(accepted),.completed_i(completed));
    task tick; begin @(posedge aon_clk); #3; end endtask
    task drive; begin @(negedge aon_clk); #1; end endtask
    task check(input reg ok, input string label_text);
        begin
            checks=checks+1;
            if (ok !== 1'b1) $fatal(1,"M3: %s state=%0d ratio=10:%0d phase=%0d",label_text,state,2*SOURCE_HALF,SOURCE_PHASE);
        end
    endtask
    task reach(input integer desired);
        integer bound;
        begin
            bound=0;
            while (state!=desired && bound<600) begin tick(); bound=bound+1; end
            check(state==desired,"bounded state arrival");
        end
    endtask
    task admission;
        integer bound;
        begin
            bound=0;
            while (!sleep_ready && bound<600) begin tick(); bound=bound+1; end
            check(sleep_ready && !domain_block && req_ready,"handshake fully released");
        end
    endtask
    task boot;
        begin
            #1; canceled_events=canceled_events+source_events-dest_events;
            arst_n=0; valid=0; wake_pulse=0; sleep_req=0; idle_allow=1;
            withhold_ready=0; start_delay=START_DELAY; stop_delay=1;
            #1; check(state==4 && isolate && domain_block && clock_req,"asynchronous reset safety");
            repeat(3) tick(); #2; arst_n=1;
            reach(0); admission(); check(!fault,"reset recovery");
        end
    endtask
    task submit(input integer cycles);
        begin
            admission(); @(negedge domain_clk); #1;
            check(req_ready,"request ready before acceptance"); valid=1; id=id+1; latency=cycles;
            @(posedge domain_clk); #2; check(!idle,"transaction accepted");
            @(negedge domain_clk); #1; valid=0;
        end
    endtask
    task sleep_begin;
        begin drive(); sleep_req=1; reach(1); end
    endtask
    task wait_stopped;
        integer bound;
        begin
            reach(3); bound=0;
            while (gate_on && bound<100) begin tick(); bound=bound+1; end
            check(!gate_on && !clock_ready && idle,"managed clock stopped after drain");
        end
    endtask
    task sleep_until_stopped;
        begin sleep_begin(); wait_stopped(); end
    endtask
    task pulse_wake;
        integer bound;
        begin
            bound=0;
            @(negedge source_clk); #1;
            while (!wake_ready && bound<200) begin @(negedge source_clk); #1; bound=bound+1; end
            check(wake_ready,"wake source handshake ready"); wake_pulse=1;
            @(negedge source_clk); #1; wake_pulse=0;
        end
    endtask
    task wake_settled;
        integer bound;
        begin
            bound=0;
            while ((!wake_ready || source_events!=dest_events) && bound<200) begin tick(); bound=bound+1; end
            check(wake_ready && source_events==dest_events,"wake delivered exactly once and rearmed");
        end
    endtask
    task finish_work;
        integer bound;
        begin
            bound=0;
            while (!idle && bound<2000) begin tick(); bound=bound+1; end
            check(idle && accepted==completed,"no lost work in epoch");
        end
    endtask
    // Pulse scoreboard is independent of request/ack implementation state.
    always @(posedge source_clk or negedge arst_n) begin
        if (!arst_n) source_events=0;
        else if (wake_rst_n && wake_pulse && wake_ready) begin
            source_events=source_events+1; total_events=total_events+1;
        end
    end
    always @(posedge aon_clk or negedge arst_n) begin
        if (!arst_n) dest_events=0;
        else if (aon_rst_n && wake_event) begin
            dest_events=dest_events+1; delivered_total=delivered_total+1;
            if (dest_events>source_events) $fatal(1,"M3: duplicate or phantom wake event");
        end
    end
    always @(posedge aon_clk) begin
        #2;
        if (arst_n && aon_rst_n && domain_rst_n) begin
            if ((isolate || !clock_req || !gate_on) && scoreboard.pending!=0)
                $fatal(1,"M3: isolation/clock stop with outstanding transaction");
            if (sleeping && (!domain_block || !quiesced || !idle))
                $fatal(1,"M3: sleep without blocked-and-drained acknowledgement");
            if (!domain_block && isolate) $fatal(1,"M3: admission open while isolated");
            if (active && !clock_ready) $fatal(1,"M3: stale clock-ready released work");
        end
    end
    // Check local reset release occurs on exactly the second local edge.
    integer aon_edges=0, domain_edges=0, wake_edges=0;
    time aon_edge_time, domain_edge_time, wake_edge_time;
    always @(posedge aon_clk or negedge arst_n) begin
        if (!arst_n) aon_edges=0;
        else begin aon_edges=aon_edges+1; aon_edge_time=$time; end
    end
    always @(posedge domain_clk or negedge arst_n) begin
        if (!arst_n) domain_edges=0;
        else begin domain_edges=domain_edges+1; domain_edge_time=$time; end
    end
    always @(posedge source_clk or negedge arst_n) begin
        if (!arst_n) wake_edges=0;
        else begin wake_edges=wake_edges+1; wake_edge_time=$time; end
    end
    always @(posedge aon_rst_n) if (aon_edges!=2 || $time!=aon_edge_time) $fatal(1,"AON reset release timing");
    always @(posedge domain_rst_n) if (domain_edges!=2 || $time!=domain_edge_time) $fatal(1,"domain reset release timing");
    always @(posedge wake_rst_n) if (wake_edges!=2 || $time!=wake_edge_time) $fatal(1,"wake reset release timing");

    initial begin
        coverage_path="build/m3-events.csv";
        if ($value$plusargs("COVERAGE=%s",coverage_path)) begin end
        cov=$fopen(coverage_path,"w"); if (!cov) $fatal(1,"cannot open M3 coverage");
        $fdisplay(cov,"bin");
        if ($value$plusargs("VCD=%s",wave_path)) begin $dumpfile(wave_path); $dumpvars(0,tb_m3); end
        boot();
        // Repeated source pulses exercise full return-to-zero handshake reuse.
        for (iteration=0;iteration<8;iteration=iteration+1) begin pulse_wake(); wake_settled(); end
        check(dest_events==8,"eight source pulses delivered"); $fdisplay(cov,"wake.repeated");
        submit(8); sleep_until_stopped(); finish_work();
        $fdisplay(cov,"sleep.busy");
        pulse_wake(); reach(0); admission(); wake_settled();
        repeat(20) tick(); check(active,"held sleep request does not retrigger");
        $fdisplay(cov,"sleep.held_request");
        drive(); sleep_req=0; tick();
        sleep_until_stopped(); pulse_wake(); reach(0); admission(); wake_settled();
        $fdisplay(cov,"sleep.rearmed");
        finish_work();

        // Admission may remain open during outbound synchronization. That
        // late transaction must be included in the eventual quiesce ack.
        boot(); sleep_begin();
        @(negedge domain_clk); #1; check(req_ready,"admission still open during crossing");
        valid=1; id=id+1; latency=3;
        @(posedge domain_clk); #2; check(state==1 && !idle,"DRAIN transit accepts local work");
        @(negedge domain_clk); #1; valid=0;
        wait_stopped(); finish_work(); $fdisplay(cov,"work.accepted_during_drain");

        // Withhold a conservative idle acknowledgement, then allow it through.
        boot(); idle_allow=0; sleep_begin(); repeat(15) tick();
        check(state==1 && domain_block && !quiesced,"delayed quiesce ack cannot stop clock");
        @(negedge domain_clk); #1; idle_allow=1; wait_stopped();
        $fdisplay(cov,"ack.delayed_quiesce");
        pulse_wake(); reach(0); admission(); wake_settled();

        // Abort and immediately rearm while old request/ack is still retiring.
        boot(); submit(20); sleep_begin(); pulse_wake(); reach(0);
        drive(); sleep_req=0; tick(); drive(); sleep_req=1; tick();
        check(active && !sleep_ready,"new sleep waits for old handshake cleanup");
        reach(1); wait_stopped(); finish_work(); wake_settled();
        $fdisplay(cov,"wake.drain_abort_rearm");

        // Timeout is safe but admission remains blocked until handshake cleanup.
        boot(); idle_allow=0; sleep_begin(); repeat(TIMEOUT) tick();
        check(active && fault && domain_block && !sleep_ready,"drain timeout preserves handshake");
        @(negedge domain_clk); #1; idle_allow=1; admission();
        check(fault,"drain fault remains sticky after cleanup");
        drive(); sleep_req=0; tick(); sleep_until_stopped();
        $fdisplay(cov,"timeout.drain");

        // Delayed OFF acknowledgement leaves stale ready high across quick wake.
        boot(); stop_delay=12; start_delay=1; sleep_begin(); reach(3);
        pulse_wake(); reach(4);
        check(clock_ready && !clock_req && isolate,"stale ready cannot satisfy new START");
        while (clock_ready) begin tick(); check(state==4,"wait for OFF acknowledgement"); end
        reach(0); admission(); wake_settled(); check(!fault,"fresh readiness completes restart");
        $fdisplay(cov,"clock.stale_ready");

        boot(); sleep_until_stopped(); withhold_ready=1;
        pulse_wake(); reach(6); check(fault && isolate && domain_block,"missing ready fails closed");
        withhold_ready=0; repeat(20) tick(); check(state==6,"late ready cannot escape fault");
        wake_settled(); $fdisplay(cov,"timeout.start");

        // Reset in every core phase, including FAULT; RUN/DRAIN carry pending work.
        for (target=0;target<=6;target=target+1) begin
            boot();
            if (target<=1) submit(80);
            if (target==1) sleep_begin();
            if (target==2) begin sleep_begin(); reach(2); end
            if (target>=3) sleep_until_stopped();
            if (target>=4) begin
                if (target!=5) withhold_ready=1;
                pulse_wake(); reach(target);
            end
            check(state==target,"reset target observed");
            $fdisplay(cov,"reset.state%0d",state);
            boot(); repeat(10) tick(); check(active && !fault && source_events==dest_events,"post-reset recovery has no phantom event");
        end
        check(scoreboard.total_canceled==2,"reset explicitly cancels two pending transactions");

        // Cancel a source-captured pulse before it can reach AON.
        boot(); @(negedge source_clk); #1; check(wake_ready,"source ready before reset race");
        wake_pulse=1; @(posedge source_clk); #1;
        check(source_events==1 && dest_events==0,"wake pending at reset");
        boot(); repeat(20) tick();
        check(dest_events==0 && wake_ready,"reset discarded pending wake without phantom delivery");
        pulse_wake(); wake_settled(); check(dest_events==1,"wake bridge reusable after cancellation");
        $fdisplay(cov,"reset.pending_wake");
        finish_work(); scoreboard.check_empty();
        check(canceled_events==1 && total_events==delivered_total+canceled_events,
            "all wake events delivered or explicitly reset-canceled");
        $display("PASS: M3 accounting work=%0d completed=%0d canceled=%0d wake=%0d delivered=%0d wake_canceled=%0d",
            scoreboard.total_accepted,scoreboard.total_completed,scoreboard.total_canceled,
            total_events,delivered_total,canceled_events);
        $fclose(cov);
        $display("PASS: M3 period=10:%0d phase=%0d start_delay=%0d checks=%0d wake_events=%0d",
            2*SOURCE_HALF,SOURCE_PHASE,START_DELAY,checks,total_events);
        $finish;
    end
    initial begin #2000000; $fatal(1,"M3 global watchdog"); end
endmodule
