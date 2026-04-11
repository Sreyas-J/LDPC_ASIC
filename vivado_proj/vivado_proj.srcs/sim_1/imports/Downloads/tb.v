`timescale 1ns / 1ps

// ============================================================
//  LDPC Decoder - Testbench (AXI4-Stream I/O, parameterized)
//
//  The testbench acts as:
//    - AXI Stream Master: sends qv_flat LLRs to the DUT
//    - AXI Stream Slave:  receives cv_list from the DUT
//
//  Data is transferred in DATA_WIDTH-bit beats.
// ============================================================

module tb_gen;

    // ---- Parameters (match top/gen defaults) ----
    parameter N          = 672;
    parameter M          = 126;
    parameter MAX_DC     = 15;
    parameter MAX_DV     = 3;
    parameter MAX_ITER   = 5;
    parameter DATA_WIDTH = 256;

    localparam QV_BITS       = N * 5;
    localparam NUM_IN_BEATS  = (QV_BITS + DATA_WIDTH - 1) / DATA_WIDTH;
    localparam QV_PAD_BITS   = NUM_IN_BEATS * DATA_WIDTH;
    localparam NUM_OUT_BEATS = (N + DATA_WIDTH - 1) / DATA_WIDTH;
    localparam CV_PAD_BITS   = NUM_OUT_BEATS * DATA_WIDTH;

    reg                    clk, rst;

    // AXI Stream Master signals (TB -> DUT input)
    reg  [DATA_WIDTH-1:0]  s_axis_tdata;
    reg                    s_axis_tvalid;
    wire                   s_axis_tready;
    reg                    s_axis_tlast;

    // AXI Stream Slave signals (DUT -> TB output)
    wire [DATA_WIDTH-1:0]  m_axis_tdata;
    wire                   m_axis_tvalid;
    reg                    m_axis_tready;
    wire                   m_axis_tlast;

    // Reconstructed cv_list from output stream
    reg  [N-1:0]           cv_list_received;

    top #(
        .N(N), .M(M), .MAX_DC(MAX_DC), .MAX_DV(MAX_DV),
        .MAX_ITER(MAX_ITER), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

    integer idx;
    initial begin
        clk = 0;
        $dumpfile("/tmp/ldpc_sim.vcd");
        $dumpvars(0, clk);
        $dumpvars(0, rst);
        $dumpvars(0, s_axis_tdata);
        $dumpvars(0, s_axis_tvalid);
        $dumpvars(0, s_axis_tready);
        $dumpvars(0, s_axis_tlast);
        $dumpvars(0, m_axis_tdata);
        $dumpvars(0, m_axis_tvalid);
        $dumpvars(0, m_axis_tready);
        $dumpvars(0, m_axis_tlast);
        $dumpvars(0, cv_list_received);
        // Dump unpacked mcv_t array
        for (idx = 0; idx < N; idx = idx + 1) begin
            $dumpvars(0, tb_gen.dut.gen_core.mcv_t[idx]);
        end
        for (idx = 0; idx < N; idx = idx + 1) begin
            $dumpvars(0, tb_gen.dut.gen_core.Lvc_out[idx]);
        end
        forever #5 clk = ~clk;
    end

    // ---- helpers ------------------------------------------------
    integer pass_count, fail_count;
    initial begin pass_count = 0; fail_count = 0; end

    // Padded internal qv_flat register
    reg [QV_PAD_BITS-1:0] qv_flat_padded;

    // Build qv_flat from codeword + introduced error.
    task build_qv;
        input [N-1:0] codeword;
        input integer error_pe;
        integer k;
        reg [4:0] val;
        begin
            qv_flat_padded = {QV_PAD_BITS{1'b0}};
            for (k = 0; k < N; k = k + 1) begin
                if (codeword[k])
                    val = 5'h17;       // bit=1 -> -7
                else
                    val = 5'h07;       // bit=0 -> +7
                if (k == error_pe)
                    val = val ^ 5'h10; // flip sign bit to simulate channel error
                qv_flat_padded[5*k +: 5] = val;
            end
        end
    endtask

    // Send qv_flat data over AXI Stream to DUT.
    // Uses proper TVALID/TREADY handshake.
    task send_axis_input;
        integer beat;
        begin
            for (beat = 0; beat < NUM_IN_BEATS; beat = beat + 1) begin
                // Drive data and valid before the clock edge
                @(posedge clk); #1;
                s_axis_tdata  = qv_flat_padded[beat*DATA_WIDTH +: DATA_WIDTH];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (beat == NUM_IN_BEATS - 1) ? 1'b1 : 1'b0;
                // Wait until handshake completes (both valid and ready high at posedge)
                begin : wait_handshake_in
                    forever begin
                        @(posedge clk);
                        if (s_axis_tready) begin
                            #1;
                            // Deassert valid immediately to prevent double-acceptance
                            s_axis_tvalid = 1'b0;
                            s_axis_tlast  = 1'b0;
                            disable wait_handshake_in;
                        end
                    end
                end
            end
            // Ensure clean deassert
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = {DATA_WIDTH{1'b0}};
        end
    endtask

    // Receive cv_list from AXI Stream output.
    task receive_axis_output;
        integer beat;
        reg [CV_PAD_BITS-1:0] cv_padded;
        begin
            cv_padded = {CV_PAD_BITS{1'b0}};
            m_axis_tready = 1'b1;
            beat = 0;
            begin : wait_output
                forever begin
                    @(posedge clk);
                    if (m_axis_tvalid && m_axis_tready) begin
                        cv_padded[beat*DATA_WIDTH +: DATA_WIDTH] = m_axis_tdata;
                        if (m_axis_tlast || beat == NUM_OUT_BEATS - 1) begin
                            disable wait_output;
                        end
                        beat = beat + 1;
                    end
                end
            end
            #1;
            m_axis_tready = 1'b0;
            cv_list_received = cv_padded[N-1:0];
        end
    endtask

    // Run one complete test case.
    task run_test;
        input [N-1:0] codeword;
        input integer error_pe;
        reg [N-1:0] naive;
        begin
            naive = codeword ^ ({{(N-1){1'b0}}, 1'b1} << error_pe);
            $display("  Codeword: %3h | Error at PE%0d | Naive: %3h",
                     codeword, error_pe, naive);

            build_qv(codeword, error_pe);
            send_axis_input;
            receive_axis_output;

            if (cv_list_received == codeword) begin
                $display("    -> PASS  (cv_list = %3h)", cv_list_received);
                pass_count = pass_count + 1;
            end else begin
                $display("    -> FAIL  (cv_list = %3h, want %3h)", cv_list_received, codeword);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ---- main test sequence ------------------------------------
    initial begin
        rst = 1;
        s_axis_tdata  = {DATA_WIDTH{1'b0}};
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b0;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        $display("");
        $display("============================================================");
        $display("  LDPC DECODER - MULTI-CASE VERIFICATION (N=%0d, M=%0d)", N, M);
        $display("  AXI Stream I/O (DATA_WIDTH=%0d)", DATA_WIDTH);
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
