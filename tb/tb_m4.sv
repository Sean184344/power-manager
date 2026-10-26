`timescale 1ns/1ps
module tb_m4;
    parameter integer SOURCE_HALF=3, PHASE=1, RESPONSE_DELAY=2;
    localparam integer TIMEOUT=64;
    reg aon_clk=0, source_clk=0, arst_n=1;
    always #5 aon_clk=~aon_clk;
    initial begin #(PHASE); forever #(SOURCE_HALF) source_clk=~source_clk; end
    reg sleep_req=0, wake_pulse=0, valid=0;
    reg [31:0] data=0;
    integer work_cycles=4, save_delay=RESPONSE_DELAY, restore_delay=RESPONSE_DELAY;
    integer on_delay=RESPONSE_DELAY, off_delay=RESPONSE_DELAY;
    reg missing_on=0, stuck_on=0, drop_power=0, missing_clock=0;
    reg missing_save=0, missing_restore=0, stuck_save=0, stuck_restore=0, corrupt_restore=0;
    wire power_enable, power_good, clock_req, clock_ready, domain_clk, gate_on;
    wire aon_rst_n, domain_rst_n, block_work, isolate, save_req, restore_req;
    wire save_ack, restore_ack, wake_ready, active, sleeping, fault;
    wire idle, req_ready, done;
    wire [31:0] raw_data, clamped_data;
    wire [3:0] state;
    integer checks=0, cov, cycle, wake_in_save=0, wake_in_powerdown=0;
    string coverage_path, wave_path;
    power_manager_retention #(.TIMEOUT_CYCLES(TIMEOUT)) dut(
        .aon_clk_i(aon_clk),.domain_clk_i(domain_clk),.wake_clk_i(source_clk),.arst_ni(arst_n),
        .sleep_req_i(sleep_req),.wake_pulse_i(wake_pulse),.power_good_i(power_good),
        .clock_ready_i(clock_ready),.domain_idle_i(idle),.save_ack_i(save_ack),.restore_ack_i(restore_ack),
        .wake_ready_o(wake_ready),.aon_rst_no(aon_rst_n),.domain_rst_no(domain_rst_n),
        .domain_block_work_o(block_work),.domain_save_req_o(save_req),.domain_restore_req_o(restore_req),
        .power_enable_o(power_enable),.clock_req_o(clock_req),.isolate_o(isolate),
        .active_o(active),.sleeping_o(sleeping),.fault_o(fault),.state_o(state));
    power_supply supply(.clk_i(source_clk),.arst_ni(arst_n),.enable_i(power_enable),
        .missing_on_i(missing_on),.stuck_on_i(stuck_on),.drop_i(drop_power),
        .on_delay_i(on_delay),.off_delay_i(off_delay),.good_o(power_good));
    async_clock_controller #(.RESET_REQUEST(1'b0)) clock_model(.raw_clk_i(source_clk),.arst_ni(arst_n && power_good),
        .request_i(clock_req),.withhold_ready_i(missing_clock),
        .start_delay_i(RESPONSE_DELAY),.stop_delay_i(RESPONSE_DELAY),
        .domain_clk_o(domain_clk),.ready_o(clock_ready),.gate_o(gate_on));
    retention_domain endpoint(.clk_i(domain_clk),.arst_ni(arst_n),.domain_rst_ni(domain_rst_n),
        .power_good_i(power_good),.block_i(block_work),.isolate_i(isolate),
        .save_req_i(save_req),.restore_req_i(restore_req),.req_valid_i(valid),.req_data_i(data),
        .work_cycles_i(work_cycles),.save_delay_i(save_delay),.restore_delay_i(restore_delay),
        .missing_save_i(missing_save),.missing_restore_i(missing_restore),
        .stuck_save_i(stuck_save),.stuck_restore_i(stuck_restore),.corrupt_restore_i(corrupt_restore),
        .req_ready_o(req_ready),.idle_o(idle),.done_o(done),.save_ack_o(save_ack),.restore_ack_o(restore_ack),
        .raw_o(raw_data),.clamped_o(clamped_data));
    retention_scoreboard scoreboard(.aon_clk_i(aon_clk),.domain_clk_i(domain_clk),
        .arst_ni(arst_n),.domain_rst_ni(domain_rst_n),.power_good_i(power_good),
        .power_enable_i(power_enable),.gate_i(gate_on),.clock_req_i(clock_req),
        .isolate_i(isolate),.active_i(active),.fault_i(fault),.block_i(block_work),
        .req_valid_i(valid),.req_ready_i(req_ready),.done_i(done),.save_req_i(save_req),
        .save_ack_i(save_ack),.restore_req_i(restore_req),.restore_ack_i(restore_ack),
        .req_data_i(data),.raw_i(raw_data),.clamped_i(clamped_data),.work_cycles_i(work_cycles));
    task tick; begin @(posedge aon_clk); #3; end endtask
    task drive; begin @(negedge aon_clk); #1; end endtask
    task check(input reg ok, input string label_text);
        begin
            checks=checks+1;
            if (ok !== 1'b1) $fatal(1,"M4: %s state=%0d power=%b clock=%b isolate=%b reset_n=%b",label_text,state,power_enable,clock_req,isolate,domain_rst_n);
        end
    endtask
    task reach(input integer target);
        integer bound;
        begin
            bound=0;
            while (state!=target && bound<1000) begin tick(); bound=bound+1; end
            check(state==target,"bounded state arrival");
        end
    endtask
    task reset_begin;
        begin
            #1; arst_n=0; valid=0; wake_pulse=0; sleep_req=0;
            missing_on=0; stuck_on=0; drop_power=0; missing_clock=0;
            missing_save=0; missing_restore=0; stuck_save=0; stuck_restore=0;
        corrupt_restore=$test$plusargs("CORRUPT_RESTORE"); save_delay=RESPONSE_DELAY; restore_delay=RESPONSE_DELAY;
            on_delay=RESPONSE_DELAY; off_delay=RESPONSE_DELAY;
            #1; check(isolate && !domain_rst_n && !clock_req && !power_enable,"global reset safe");
            repeat(3) tick(); #2; arst_n=1;
        end
    endtask
    task boot;
        begin reset_begin(); reach(8); check(raw_data===32'b0 && !fault,"cold boot value"); end
    endtask
    task write_work(input reg [31:0] value);
        begin
            @(negedge domain_clk); #1; check(req_ready && active,"work admitted in RUN");
            valid=1; data=value;
            @(posedge domain_clk); #2; check(!idle,"work accepted");
            @(negedge domain_clk); #1; valid=0;
        end
    endtask
    task enter_sleep;
        begin drive(); sleep_req=1; reach(1); end
    endtask
    task pulse_wake;
        integer bound;
        begin
            bound=0; @(negedge source_clk); #1;
            while (!wake_ready && bound<200) begin @(negedge source_clk); #1; bound=bound+1; end
            check(wake_ready,"wake producer ready"); wake_pulse=1;
            @(negedge source_clk); #1; wake_pulse=0;
        end
    endtask
    task expect_timeout(input integer wait_state);
        begin
            reach(wait_state);
            repeat(TIMEOUT-1) tick(); check(state==wait_state,"no premature timeout");
            tick(); check(fault && isolate && !domain_rst_n && !clock_req,"deadline fails closed");
            repeat(3) tick(); check(fault,"FAULT requires reset");
        end
    endtask
    always @(posedge aon_clk) begin
        if (aon_rst_n && dut.wake_event) begin
            if (state==10) wake_in_save=wake_in_save+1;
            if (state==14) wake_in_powerdown=wake_in_powerdown+1;
        end
    end
    initial begin
        coverage_path="build/m4-events.csv";
        if ($value$plusargs("COVERAGE=%s",coverage_path)) begin end
        cov=$fopen(coverage_path,"w"); if (!cov) $fatal(1,"cannot open M4 coverage");
        $fdisplay(cov,"bin");
        if ($value$plusargs("VCD=%s",wave_path)) begin $dumpfile(wave_path); $dumpvars(0,tb_m4); end
        boot(); write_work(32'h1234abcd); enter_sleep();
        check(!power_good && !gate_on && !domain_rst_n,"powered off after drain and save");
        check((^raw_data)===1'bx && clamped_data===32'b0,"power loss corrupts raw state but clamps outputs");
        pulse_wake(); reach(8);
        check(raw_data===32'h1234abcd && !isolate,"saved state restored before RUN");
        repeat(10) tick(); check(active,"held sleep request consumed");
        $fdisplay(cov,"retention.normal");
        // Repeated snapshots must replace the old value, not restore stale data.
        for (cycle=1;cycle<=3;cycle=cycle+1) begin
            drive(); sleep_req=0; tick();
            write_work(32'hf0101000+cycle); enter_sleep(); pulse_wake(); reach(8);
            check(raw_data==32'hf0101000+cycle,"latest snapshot restored");
        end
        $fdisplay(cov,"retention.repeated");

        boot(); save_delay=8; restore_delay=9;
        write_work(32'hdeadbeef); enter_sleep(); pulse_wake(); reach(8);
        check(raw_data===32'hdeadbeef,"delayed save/restore preserves data");
        $fdisplay(cov,"retention.delayed");

        boot(); save_delay=12; write_work(32'h76543210);
        drive(); sleep_req=1; reach(10); pulse_wake(); reach(8);
        check(raw_data===32'h76543210 && wake_in_save>0,"wake during save completes full cycle");
        $fdisplay(cov,"wake.during_save");

        boot(); off_delay=12; write_work(32'hbbccddaa);
        drive(); sleep_req=1; reach(14); pulse_wake(); reach(8);
        check(raw_data===32'hbbccddaa && wake_in_powerdown>0,"wake during poweroff preserved");
        $fdisplay(cov,"wake.during_poweroff");

        reset_begin(); missing_on=1; expect_timeout(2);
        check(!power_good,"missing power-good never releases domain");
        missing_on=0; repeat(30) tick(); check(fault,"late power-good stays faulted");
        $fdisplay(cov,"fault.missing_power_good");

        reset_begin(); missing_clock=1; expect_timeout(3);
        $fdisplay(cov,"fault.missing_clock_ready");

        boot(); missing_save=1; write_work(32'h10203040);
        drive(); sleep_req=1; expect_timeout(10);
        check(power_good,"save failure never powered down");
        $fdisplay(cov,"fault.missing_save");

        boot(); stuck_save=1; write_work(32'h55667788);
        drive(); sleep_req=1; expect_timeout(11);
        $fdisplay(cov,"fault.save_ack_stuck");

        boot(); write_work(32'h31415926); enter_sleep(); missing_restore=1;
        pulse_wake(); expect_timeout(5);
        $fdisplay(cov,"fault.missing_restore");

        boot(); write_work(32'h27182818); enter_sleep(); stuck_restore=1;
        pulse_wake(); expect_timeout(6);
        $fdisplay(cov,"fault.restore_ack_stuck");

        boot(); stuck_on=1; write_work(32'hcafebabe);
        drive(); sleep_req=1; expect_timeout(14);
        $fdisplay(cov,"fault.missing_power_off");

        boot(); write_work(32'h12345678); repeat(20) tick();
        drop_power=1; reach(15);
        check(clamped_data===32'b0 && !domain_rst_n,"unexpected supply loss clamps and resets");
        $fdisplay(cov,"fault.unexpected_power_loss");

        boot(); write_work(32'h87654321); enter_sleep(); boot();
        check(raw_data===32'b0,"global reset intentionally discards retained snapshot");
        $fdisplay(cov,"reset.powered_off");

        write_work(32'h98765432); enter_sleep(); restore_delay=12;
        pulse_wake(); reach(5); boot();
        check(raw_data===32'b0,"reset during restore restarts cold");
        $fdisplay(cov,"reset.during_restore");
        scoreboard.check_empty();
        $fclose(cov);
        $display("PASS: M4 period=10:%0d phase=%0d delay=%0d checks=%0d",2*SOURCE_HALF,PHASE,RESPONSE_DELAY,checks);
        $finish;
    end
    initial begin #3000000; $fatal(1,"M4 watchdog"); end
endmodule
