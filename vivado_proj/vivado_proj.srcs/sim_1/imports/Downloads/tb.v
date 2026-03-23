`timescale 1ns / 1ps

// ============================================================
//  LDPC Decoder - Testbench (controller-based, parameterized)
//
//  Instantiates the top module (gen + controller).
//  The testbench only drives: clk, rst, start, qv_flat.
//  It waits for the 'done' pulse, then checks cv_list.
//
//  Valid codewords for the default H matrix (null space over GF(2)):
//    0x000, 0x2ce, 0x595, 0x75b, 0x963, 0xbad, 0xcf6, 0xe38
// ============================================================

module tb_gen;

    // ---- Parameters (match top/gen defaults) ----
    parameter N        = 672;
    parameter M        = 126;
    parameter MAX_DC   = 15;
    parameter MAX_DV   = 3;
    parameter MAX_ITER = 5;

    reg                clk, rst, start;
    reg  [N*5-1:0]     qv_flat;
    wire [N-1:0]       cv_list;
    wire               done;

    top #(
        .N(N), .M(M), .MAX_DC(MAX_DC), .MAX_DV(MAX_DV),
        .MAX_ITER(MAX_ITER)
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

    // ---- helpers ------------------------------------------------
    integer pass_count, fail_count;
    initial begin pass_count = 0; fail_count = 0; end

    // Build qv_flat from codeword + introduced error.
    // PE k's 5-bit LLR occupies qv_flat[5*k +: 5].
    // bit=1 -> -7 (5'h17), bit=0 -> +7 (5'h07). Error PE gets sign flipped.
    task load_qv;
        input [N-1:0] codeword;
        input integer error_pe;
        integer k;
        reg [4:0] val;
        begin
            qv_flat = {(N*5){1'b0}};
            for (k = 0; k < N; k = k + 1) begin
                if (codeword[k])
                    val = 5'h17;       // bit=1 -> -7
                else
                    val = 5'h07;       // bit=0 -> +7
                if (k == error_pe)
                    val = val ^ 5'h10; // flip sign bit to simulate channel error
                qv_flat[5*k +: 5] = val;
            end
        end
    endtask

    // Run one complete test case.
    // Loads LLRs, pulses start, waits for done, checks result.
    task run_test;
        input [N-1:0] codeword;
        input integer error_pe;
        reg [N-1:0] naive;
        begin
            naive = codeword ^ ({{(N-1){1'b0}}, 1'b1} << error_pe);
            $display("  Codeword: %3h | Error at PE%0d | Naive: %3h",
                     codeword, error_pe, naive);

            load_qv(codeword, error_pe);

            // Pulse start for one cycle
            @(posedge clk); #1;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;

            // Wait for the controller's done pulse
            @(posedge done);

            // cv_list was stable before done fired; sample it now
            if (cv_list == codeword) begin
                $display("    -> PASS  (cv_list = %3h)", cv_list);
                pass_count = pass_count + 1;
            end else begin
                $display("    -> FAIL  (cv_list = %3h, want %3h)", cv_list, codeword);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ---- main test sequence ------------------------------------
    initial begin
        rst = 1; start = 0; qv_flat = {(N*5){1'b0}};
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        $display("");
        $display("============================================================");
        $display("  LDPC DECODER - MULTI-CASE VERIFICATION (N=%0d, M=%0d)", N, M);
        $display("============================================================");
        $display("");

        $display("--- Test 1 ---");   run_test(12'h963, 0);
        $display("--- Test 2 ---");   run_test(12'h963, 6);
        $display("--- Test 3 ---");   run_test(12'h963, 11);
        $display("--- Test 4 ---");   run_test(12'hbad, 3);
        $display("--- Test 5 ---");   run_test(12'hbad, 7);
        $display("--- Test 6 ---");   run_test(12'h2ce, 1);
        $display("--- Test 7 ---");   run_test(12'he38, 0);
        $display("--- Test 8 ---");   run_test(12'h595, 4);

        $display("");
        $display("--- TRIVIAL: All-zeros codeword (all LLRs = +7) ---");
        $display("--- Test  9 ---");  run_test(12'h000, 0);
        $display("--- Test 10 ---");  run_test(12'h000, 5);
        $display("--- Test 11 ---");  run_test(12'h000, 9);

        $display("");
        $display("--- Mostly-ones codeword 0xe38 (9 bits set) ---");
        $display("--- Test 12 ---");  run_test(12'he38, 9);
        $display("--- Test 13 ---");  run_test(12'he38, 4);
        $display("--- Test 14 ---");  run_test(12'he38, 1);

        $display("");
        $display("============================================================");
        $display("  RESULTS:  %0d / %0d tests PASSED", pass_count, pass_count + fail_count);
        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
