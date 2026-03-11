`timescale 1ns / 1ps

module tb_gen;

    reg clk;
    reg iter_flag;
    reg cn_reset;
    reg cn_sel;
    reg vn_sel;

    integer i = 0;
    
    wire [11:0] cv_list;

    gen dut (
        .clk(clk),
        .iter_flag(iter_flag),
        .cn_reset(cn_reset),
        .cn_sel(cn_sel),
        .vn_sel(vn_sel),
        .cv_list(cv_list)
    );

    // Clock: 100 MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // Print cv_list on every cn_reset pulse
    always @(posedge clk) begin
        if (cn_reset) begin
            $display("------------- ITERATION -------------");
            for (i = 0; i < 12; i = i + 1)
                $write("%0d ", dut.cv_list[i]);
            $display("\n");
        end
    end

    // ------------------------------------------------------------------
    // Iteration task
    // Cycle 0 : cn_sel=1, cn_reset=1  — CN phase, reset pulse
    // Cycle 1-3: cn_sel=0             — CN phase (accumulate)
    // Cycle 4 : vn_sel=1              — VN phase
    // Cycle 5-7: idle
    // ------------------------------------------------------------------
    task one_iteration;
        input in_iter_flag;
        begin
            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 1; vn_sel = 0; cn_reset = 1;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 0; cn_reset = 0;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 0; cn_reset = 0;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 0; cn_reset = 0;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 1; cn_reset = 0;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 0; cn_reset = 0;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 0; cn_reset = 0;

            @(posedge clk); #1;
            iter_flag = in_iter_flag; cn_sel = 0; vn_sel = 0; cn_reset = 0;
        end
    endtask

    initial begin
        $display("Starting LDPC CU Simulation...");

        // ------------------------------------------------------------------
        // FIX: Initialise all control signals BEFORE the first clock edge.
        //
        // ORIGINAL: All regs start as X in simulation. The task uses
        //   @(posedge clk) THEN assigns — so on the very first posedge
        //   all signals are still X. Pipeline FFs cn_sel_1..4, vn_sel_1..4,
        //   cn_reset_1..4, and w_ena in PE all capture X on that cycle and
        //   propagate it through every downstream register.
        //
        // FIX 1: Drive all signals to 0 before the first edge.
        // FIX 2: Add #1 after @(posedge clk) in the task so assignments
        //   settle AFTER the clock edge (clean setup-time margin) rather
        //   than at the exact edge moment (race condition in some tools).
        // ------------------------------------------------------------------
        iter_flag = 1'b0;
        cn_sel    = 1'b0;
        vn_sel    = 1'b0;
        cn_reset  = 1'b0;
        // Wait past first posedge (t=5ns) with known-zero values
        @(posedge clk); #1;

        one_iteration(1'b1);   // iter 0: iter_flag=1 forces Qv into Lvc

        one_iteration(1'b0);   // iter 1
        one_iteration(1'b0);   // iter 2
        one_iteration(1'b0);   // iter 3
        one_iteration(1'b0);   // iter 4
        one_iteration(1'b0);   // iter 5
        one_iteration(1'b0);   // iter 6
        one_iteration(1'b0);   // iter 7
        one_iteration(1'b0);   // iter 8
        one_iteration(1'b0);   // iter 9

        $display("Simulation Finished");
        $finish;
    end

endmodule
