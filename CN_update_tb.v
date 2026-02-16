`timescale 1ns/1ps

module tb_CN_Update;

    reg reset;
    reg [8:0] mcv_tprev;
    reg [4:0] Lvc;
    wire [8:0] mcv_t;

    // Instantiate DUT
    CN_Update dut (
        .reset(reset),
        .mcv_tprev(mcv_tprev),
        .Lvc(Lvc),
        .mcv_t(mcv_t)
    );

    // Dump waveform
//    initial begin
//        $dumpfile("cn_update_tb.vcd");
//        $dumpvars(0, tb_CN_Update);
//    end

    initial begin

        // Test 1: Reset active
        reset = 1;
        mcv_tprev = 9'b000000000;
        Lvc = 5'b1_0011;   // sign=1, mag=3
        #10;

        // Test 2: Normal operation
        reset = 0;
        mcv_tprev = 9'b0_0100_1000;  // sc=0, min1=4, min2=8
        Lvc = 5'b1_0010;             // sign=1, mag=2
        #10;

        // Test 3
        mcv_tprev = mcv_t;
        Lvc = 5'b0_0111;             // sign=0, mag=7
        #10;

        // Test 4
        mcv_tprev = mcv_t;
        Lvc = 5'b1_0001;             // sign=1, mag=1
        #10;
//        #10;
        $finish;
    end

endmodule
