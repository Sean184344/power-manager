`default_nettype none
module power_manager_formal #(
    parameter integer TIMEOUT=8,
    parameter integer FAIR=0
)(
    input wire clk, rst_n, sleep_req, wake, idle, ready,
    output reg [11:0] reached=0
);
    wire block_work, isolate, clk_en, active, sleeping, fault;
    wire sleep_armed;
    wire [2:0] state;
    localparam integer AW=$clog2(TIMEOUT+4);
    reg valid=0;
    reg [AW-1:0] drain_age=0, start_age=0;
    reg [AW:0] wake_age=0;
    reg wake_wait=0, slept=0, fault_seen=0, request_used=0;
    power_manager #(.TIMEOUT_CYCLES(TIMEOUT)) dut(
        .clk_i(clk),.rst_ni(rst_n),.sleep_req_i(sleep_req),.wake_i(wake),
        .idle_i(idle),.clock_ready_i(ready),.block_work_o(block_work),
        .isolate_o(isolate),.clk_en_o(clk_en),.active_o(active),
        .sleeping_o(sleeping),.fault_o(fault),.state_o(state),.formal_sleep_armed_o(sleep_armed));

    always @(posedge clk) begin
        valid<=1;
        // A real reset is required before reasoning about reachable operation.
        if (!valid) assume(!rst_n);
        if (!rst_n || !sleep_req) request_used<=0;
        else if (valid && state==1 && $past(state)==0) request_used<=1;
        if (!rst_n || state!=1) drain_age<=0;
        else if (drain_age<TIMEOUT+1) drain_age<=drain_age+1;
        if (!rst_n || state!=4) start_age<=0;
        else if (start_age<TIMEOUT+1) start_age<=start_age+1;

        if (!rst_n) begin wake_wait<=0; wake_age<=0; slept<=0; end
        else begin
            if (state==3) slept<=1;
            if (state==3 && wake) begin wake_wait<=1; wake_age<=0; end
            else if (active) begin wake_wait<=0; wake_age<=0; end
            else if (wake_wait && wake_age<TIMEOUT+3) wake_age<=wake_age+1;
        end

        // Only the progress configuration constrains acknowledgement timing.
        // No fairness assumption requires a wake to arrive while asleep.
        if (FAIR && valid && rst_n) begin
            if (state==1 && drain_age==TIMEOUT-1) assume(idle);
            if (state==4 && start_age==TIMEOUT-1) assume(ready);
        end

        if (valid && rst_n && $past(rst_n)) begin
            assert(state<=6);
            assert(active==(state==0));
            assert(sleeping==(state==3));
            assert(clk_en==(state!=3));
            assert(block_work==(state!=0));
            assert(isolate==(state!=0 && state!=1));
            if (!clk_en) assert(isolate && block_work);
            if (!block_work) assert(active && clk_en && !isolate);
            if ($past(fault)) assert(fault);
            if ($past(state)==6) assert(state==6 && fault);
            if (state==3 && $past(state)!=3) assert($past(state)==2);
            if ($past(state)==0 && $past(wake)) assert(state==0);
            if ($past(state)==1 && $past(wake)) assert(state==0);
            if ($past(state)==2 && $past(wake)) assert(state==5);
            if ($past(state)==3 && $past(wake)) assert(state==4);
            if ($past(state)==4 && $past(ready)) assert(state==5);
            if ($past(state)==5) assert(state==0);
            // Inductive strengthening links the observed request history to
            // the implementation latch; it is asserted, never assumed.
            if (request_used) assert(!sleep_armed);
            if ($past(state)==0 && state==1) assert(!request_used);
            // Waits terminate by success, wake-abort, or the specified timeout.
            if (state==1) assert(drain_age<TIMEOUT);
            if (state==4) assert(start_age<TIMEOUT);
            if (FAIR) begin
                assert(!fault);
                if (wake_wait && wake_age>=TIMEOUT+2) assert(active);
            end

            if (state<=6) reached[state]<=1;
            if (slept && active) reached[7]<=1;
            if (state==0 && fault) reached[8]<=1;
            if (state==4 && start_age==TIMEOUT-1 && ready) reached[9]<=1;
            if (state==1 && drain_age==TIMEOUT-1 && wake) reached[10]<=1;
            if (fault_seen && active) reached[11]<=1;
            if (state==6) fault_seen<=1;
        end
    end
    genvar i;
    generate for (i=0;i<12;i=i+1) begin: covers
        always @(posedge clk) cover(reached[i]);
    end endgenerate
endmodule
`default_nettype wire
