`timescale 1ns / 1ps

module tb_gen;

    parameter SIZE     = 3;
    parameter M_B      = 3;
    parameter N_B      = 4;
    parameter MAX_ITER = 5;

    localparam N = N_B * SIZE;
    localparam M = M_B * SIZE;

    reg                clk, rst, start;
    reg  [N*5-1:0]     qv_flat;
    wire [N-1:0]       cv_list;
    wire               done;

    top #(
        .SIZE(SIZE), .M_B(M_B), .N_B(N_B), .MAX_ITER(MAX_ITER)
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .start  (start),
        .qv_flat(qv_flat),
        .cv_list(cv_list),
        .done   (done)
    );

    initial begin
        clk = 0;
        $dumpfile("/tmp/ldpc_sim.vcd");
        $dumpvars(0, tb_gen);
        forever #5 clk = ~clk;
    end

    integer pass_count, fail_count;
    initial begin pass_count = 0; fail_count = 0; end

    task load_qv;
        input [N-1:0] codeword;
        input integer error_pe;
        integer k;
        reg [4:0] val;
        begin
            qv_flat = {(N*5){1'b0}};
            for (k = 0; k < N; k = k + 1) begin
                if (codeword[k])
                    val = 5'h17;
                else
                    val = 5'h07;
                if (k == error_pe)
                    val = val ^ 5'h10;
                qv_flat[5*k +: 5] = val;
            end
        end
    endtask

    task run_test;
        input [N-1:0] codeword;
        input integer error_pe;
        begin
            $display("  Error at PE%0d", error_pe);
            load_qv(codeword, error_pe);

            @(posedge clk); #1;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;

            @(posedge done);

            if (cv_list == codeword) begin
                $display("    -> PASS");
                pass_count = pass_count + 1;
            end else begin
                $display("    -> FAIL");
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        rst = 1; start = 0; qv_flat = {(N*5){1'b0}};
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        $display("");
        $display("============================================================");
        $display("  LDPC DECODER (N=%0d, M=%0d) - VERIFICATION", N, M);
        $display("============================================================");

        $display("--- All-zeros codeword, single-bit errors ---");
        run_test(12'hbad, 0);
        run_test({N{1'b0}}, 5);
        run_test({N{1'b0}}, 42);
        run_test({N{1'b0}}, 100);
        run_test({N{1'b0}}, 200);
        run_test({N{1'b0}}, 400);
        run_test({N{1'b0}}, 671);

        $display("");
        $display("============================================================");
        $display("  RESULTS:  %0d / %0d tests PASSED", pass_count, pass_count + fail_count);
        $display("============================================================");

        $finish;
    end

endmodule
