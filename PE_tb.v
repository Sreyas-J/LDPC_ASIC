`timescale 1ns / 1ps

module tb_PE;

    // Inputs
    reg clk;
    reg iter_flag;
    reg reset;
    reg cn_vn_sel;
    reg [26:0] mcv_tprev;
    reg [4:0] Qv;

    // Outputs
    wire [26:0] mcv_t;
    wire Cv;

    // Instantiate the Unit Under Test (UUT)
    PE uut (
        .clk(clk), 
        .iter_flag(iter_flag), 
        .reset(reset), 
        .cn_vn_sel(cn_vn_sel), 
        .mcv_tprev(mcv_tprev), 
        .Qv(Qv), 
        .mcv_t(mcv_t), 
        .Cv(Cv)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // Test Sequence
    initial begin
        // Initialize Inputs
        iter_flag = 1;
        reset = 1;
        cn_vn_sel = 0;
        mcv_tprev = 0;
        Qv = 0;

        // Monitor signals
//        $monitor("Time=%0t | Sel=%b | Iter=%b | Qv=%d | mcv_tprev=%h | mcv_t=%h | CV=%b", 
//                 $time, cn_vn_sel, iter_flag, Qv, mcv_tprev, mcv_t, Cv);

        // --- RESET PHASE ---
        #20;
        reset = 0;
        $display("--- Reset Complete ---");

        // --- CYCLE 1: Initialization / VN Update ---
        // iter_flag = 1 selects Qv as the initial Lvc value
        // cn_vn_sel = 1 enables VN_Update
        #10;
        iter_flag = 0;
        cn_vn_sel = 1; 
        Qv = 5'd10; // Input LLR/Value
        // 27 bits split into 3 chunks of 9. Setting random data for test.
        mcv_tprev = 27'b000000001_000000010_000000100; 
        
        #15; // Wait for clock edge

        // --- CYCLE 2: CN Update ---
        // cn_vn_sel = 0 enables CN_Update
        // iter_flag = 0 selects Lvc_tprev (from memory)
        #10;
        iter_flag = 0;
        cn_vn_sel = 0;
        // Keep inputs or change them if pipeline requires
        mcv_tprev = 27'h7FFFFFF; // Max value test

//        #10;

//        // --- CYCLE 3: VN Update (Iteration 2) ---
//        #10;
//        cn_vn_sel = 1;
//        mcv_tprev = 27'h1234567;
        
        #10;
        
        // --- End Simulation ---
        #50;
        $finish;
    end
      
endmodule