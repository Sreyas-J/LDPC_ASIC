`timescale 1ns / 1ps

module VN_Update_tb;

    // Inputs
    reg clk;
    reg vn_ena;
    reg [8:0] mcv_tprev;
    reg [4:0] Lvc_tprev;
    reg [6:0] Lv;

    // Outputs
    wire [4:0] Lvc;
    wire [4:0] mcv;

    // Instantiate the Unit Under Test (UUT)
    VN_Update uut (
        .clk(clk), 
        .vn_ena(vn_ena), 
        .mcv_tprev(mcv_tprev), 
        .Lvc_tprev(Lvc_tprev), 
        .Lv(Lv), 
        .Lvc(Lvc), 
        .mcv(mcv)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    initial begin
        // Initialize Inputs
        vn_ena = 0;
        mcv_tprev = 0;
        Lvc_tprev = 0;
        Lv = 0;

        // Wait 20 ns for global reset to finish
        #20;
        
        // --- Test Case 1: vn_ena is LOW ---
        // mcv should remain in its initial/previous state
        vn_ena = 0;
        mcv_tprev = 9'b0_0110_0011; // sign=0, min1=6, min2=3
        Lvc_tprev = 5'b0_0110;      // 6
        Lv = 7'd10;
        #10;

        // --- Test Case 2: vn_ena is HIGH, Positive Result ---
        vn_ena = 1;
        // Logic: if Lvc_tprev == min1, mcv_mag = min2. 
        // Lvc_tprev(6) == min1(6), so mcv_mag = 3.
        // mcv_sign = Lvc_t_sign(0) ^ sc_tprev(0) = 0.
        // mcv = 5'b00011 (3 in sign-mag)
        // Lvc_reg = Lv(10) - mcv(3) = 7.
        // Lvc = 7 in sign-mag -> 5'b00111
        #10;
//        $display("TC2: Lv=%d, mcv=%b, Lvc=%b (Expected 5'b00111)", Lv, mcv, Lvc);

        // --- Test Case 3: Negative Result (Checking our 2's comp to Sign-Mag line) ---
        Lv = 7'd2;
        // mcv is still 3 from logic above.
        // Lvc_reg = 2 - 3 = -1 (5'b11111 in 2's comp)
        // Lvc sign bit = 1. Magnitude of -1 is 1.
        // Expected Lvc = 5'b10001
        #10;
//        $display("TC3: Lv=%d, mcv=%b, Lvc=%b (Expected 5'b10001)", Lv, mcv, Lvc);

        // --- Test Case 4: Sign flip on mcv ---
        mcv_tprev = 9'b1_0110_0011; // sc_tprev = 1
        Lvc_tprev = 5'b0_1000;      // 8 (does not match min1)
        // mcv_mag = min1 = 6.
        // mcv_sign = 0 ^ 1 = 1.
        // mcv = sign-mag for -6... 
        // NOTE: Your module's mcv logic uses ~{1'b0, mag+1} for negative.
        #10;
//        $display("TC4: mcv=%b, Lvc=%b", mcv, Lvc);

        #50;
        $finish;
    end
      
endmodule