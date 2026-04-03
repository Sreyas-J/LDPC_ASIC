`timescale 1ns / 1ps

module tb_gen;

    parameter SIZE     = 3;
    parameter M_B      = 3;
    parameter N_B      = 4;
    parameter MAX_ITER = 5;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;

    localparam N = N_B * SIZE;
    localparam M = M_B * SIZE;
    localparam QV_TOTAL_BITS = N * 5;
    localparam NUM_WORDS = (QV_TOTAL_BITS + DATA_WIDTH - 1) / DATA_WIDTH;

    reg                clk, rst, start;
    wire [N-1:0]       cv_list;
    wire               done;
    wire               qv_loaded;

    // AXI4-Lite Write signals
    reg  [ADDR_WIDTH-1:0]   axi_awaddr;
    reg                     axi_awvalid;
    wire                    axi_awready;

    reg  [DATA_WIDTH-1:0]   axi_wdata;
    reg  [DATA_WIDTH/8-1:0] axi_wstrb;
    reg                     axi_wvalid;
    wire                    axi_wready;

    wire [1:0]              axi_bresp;
    wire                    axi_bvalid;
    reg                     axi_bready;

    top #(
        .SIZE(SIZE), .M_B(M_B), .N_B(N_B), .MAX_ITER(MAX_ITER),
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .S_AXI_AWADDR  (axi_awaddr),
        .S_AXI_AWVALID (axi_awvalid),
        .S_AXI_AWREADY (axi_awready),
        .S_AXI_WDATA   (axi_wdata),
        .S_AXI_WSTRB   (axi_wstrb),
        .S_AXI_WVALID  (axi_wvalid),
        .S_AXI_WREADY  (axi_wready),
        .S_AXI_BRESP   (axi_bresp),
        .S_AXI_BVALID  (axi_bvalid),
        .S_AXI_BREADY  (axi_bready),
        .qv_loaded     (qv_loaded),
        .cv_list       (cv_list),
        .done          (done)
    );

    // Clock generation
    initial begin
        clk = 0;
        $dumpfile("/tmp/ldpc_sim.vcd");
        $dumpvars(0, tb_gen);
        forever #5 clk = ~clk;
    end

    integer pass_count, fail_count;
    initial begin pass_count = 0; fail_count = 0; end

    // -----------------------------------------------------------------
    // AXI4-Lite single write transaction task
    // -----------------------------------------------------------------
    task axi_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        begin
            // Drive AW and W channels simultaneously
            @(posedge clk); #1;
            axi_awaddr  = addr;
            axi_awvalid = 1'b1;
            axi_wdata   = data;
            axi_wstrb   = {(DATA_WIDTH/8){1'b1}};
            axi_wvalid  = 1'b1;
            axi_bready  = 1'b1;

            // Wait for both AW and W handshakes
            @(posedge clk);
            while (!(axi_awready && axi_awvalid) || !(axi_wready && axi_wvalid)) begin
                @(posedge clk);
            end
            #1;
            axi_awvalid = 1'b0;
            axi_wvalid  = 1'b0;

            // Wait for write response
            @(posedge clk);
            while (!axi_bvalid) begin
                @(posedge clk);
            end
            #1;
            axi_bready = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------
    // Load qv_flat via AXI writes
    // -----------------------------------------------------------------
    task load_qv;
        input [N-1:0] codeword;
        input integer error_pe;
        integer k, w;
        reg [4:0] val;
        reg [QV_TOTAL_BITS-1:0] qv_tmp;
        reg [DATA_WIDTH-1:0] word_data;
        begin
            // Build the full qv_flat in a temporary variable
            qv_tmp = {QV_TOTAL_BITS{1'b0}};
            for (k = 0; k < N; k = k + 1) begin
                if (codeword[k])
                    val = 5'h17;
                else
                    val = 5'h07;
                if (k == error_pe)
                    val = val ^ 5'h10;
                qv_tmp[5*k +: 5] = val;
            end

            // Send over AXI, word by word
            for (w = 0; w < NUM_WORDS; w = w + 1) begin
                // Extract 32-bit chunk
                begin : extract_word
                    integer b;
                    word_data = {DATA_WIDTH{1'b0}};
                    for (b = 0; b < DATA_WIDTH; b = b + 1) begin
                        if (w * DATA_WIDTH + b < QV_TOTAL_BITS)
                            word_data[b] = qv_tmp[w * DATA_WIDTH + b];
                    end
                end
                axi_write(w * 4, word_data);  // byte-addressed
            end

            // Wait a cycle after loading completes
            @(posedge clk); #1;
        end
    endtask

    // -----------------------------------------------------------------
    // Run a single test
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------
    initial begin
        rst = 1; start = 0;
        axi_awaddr  = 0; axi_awvalid = 0;
        axi_wdata   = 0; axi_wstrb   = 0;
        axi_wvalid  = 0; axi_bready  = 0;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        $display("");
        $display("============================================================");
        $display("  LDPC DECODER (N=%0d, M=%0d) AXI - VERIFICATION", N, M);
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
