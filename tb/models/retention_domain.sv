`timescale 1ns/1ps
// TESTBENCH ONLY. Saved bank survives domain reset and modeled power loss.
module retention_domain(
    input wire clk_i, arst_ni, domain_rst_ni, power_good_i, block_i, isolate_i,
    input wire save_req_i, restore_req_i, req_valid_i,
    input wire [31:0] req_data_i,
    input integer work_cycles_i, save_delay_i, restore_delay_i,
    input wire missing_save_i, missing_restore_i, stuck_save_i, stuck_restore_i,
    input wire corrupt_restore_i,
    output wire req_ready_o, idle_o,
    output reg done_o=0,
    output reg save_ack_o=0, restore_ack_o=0,
    output wire [31:0] raw_o, clamped_o
);
    reg busy_q=0;
    reg [31:0] pending_q=0, volatile_q=0, retained_q=0;
    reg retained_valid_q=0;
    integer remaining_q=0, save_count=0, restore_count=0;
    assign req_ready_o=domain_rst_ni && power_good_i && !block_i && !busy_q;
    assign idle_o=!busy_q;
    assign raw_o=power_good_i ? volatile_q : 32'hxxxxxxxx;
    assign clamped_o=isolate_i ? 32'b0 : raw_o;

    // A held ack marks an atomic completed copy. Drop ack only after request low.
    always @(posedge clk_i or negedge arst_ni or negedge domain_rst_ni) begin
        if (!arst_ni) begin
            retained_q<=0; retained_valid_q<=0;
            save_ack_o<=0; restore_ack_o<=0; save_count<=0; restore_count<=0;
        end else if (!domain_rst_ni) begin
            save_ack_o<=0; restore_ack_o<=0; save_count<=0; restore_count<=0;
        end else begin
            if (!save_req_i) begin
                save_count<=0;
                if (!stuck_save_i) save_ack_o<=0;
            end else if (!save_ack_o && !missing_save_i) begin
                save_count<=save_count+1;
                if (save_count>=save_delay_i-1) begin
                    if (!idle_o || !block_i) $fatal(1,"retention: save without quiescence");
                    retained_q<=volatile_q; retained_valid_q<=1; save_ack_o<=1;
                end
            end
            if (!restore_req_i) begin
                restore_count<=0;
                if (!stuck_restore_i) restore_ack_o<=0;
            end else if (!restore_ack_o && !missing_restore_i) begin
                restore_count<=restore_count+1;
                if (restore_count>=restore_delay_i-1) begin
                    if (!retained_valid_q || !block_i) $fatal(1,"retention: invalid restore");
                    restore_ack_o<=1;
                end
            end
        end
    end

    always @(posedge clk_i or negedge domain_rst_ni or negedge power_good_i) begin
        if (!power_good_i) begin
            volatile_q<=32'hxxxxxxxx; busy_q<=0; done_o<=0; remaining_q<=0;
        end else if (!domain_rst_ni) begin
            volatile_q<=0; busy_q<=0; done_o<=0; remaining_q<=0;
        end else begin
            done_o<=0;
            if (restore_req_i && !restore_ack_o && !missing_restore_i &&
                restore_count>=restore_delay_i-1)
                volatile_q<=corrupt_restore_i ? retained_q ^ 32'h1 : retained_q;
            if (busy_q) begin
                if (remaining_q==1) begin volatile_q<=pending_q; busy_q<=0; done_o<=1; end
                else remaining_q<=remaining_q-1;
            end
            if (req_valid_i && req_ready_o) begin
                if (work_cycles_i<1) $fatal(1,"retention: invalid work latency");
                pending_q<=req_data_i; remaining_q<=work_cycles_i; busy_q<=1;
            end
        end
    end
endmodule
