`timescale 1ns / 1ps

module tb_gen;

    // Inputs
    reg clk;
    reg reset;
    
    // CU outputs to DUT
    reg iter_flag;
    reg cn_reset;
    reg cn_sel;
    reg vn_sel;
    
    // Control Unit FSM variables
    reg [2:0] count; // 8 cycles per iteration
    reg [4:0] iter;  // up to 15 iterations

    integer i=0;
    
//    wire cv_list[0:11];
    wire [11:0]cv_list;
    // Instantiate the Device Under Test (DUT)
    gen dut (
        .clk(clk),
        .reset(reset),
        .iter_flag(iter_flag),
        .cn_reset(cn_reset),
        .cn_sel(cn_sel),
        .vn_sel(vn_sel),
        .cv_list(cv_list)
    );

    //////////////////////////////////////////////////////
    // Clock Generation (100MHz)
    //////////////////////////////////////////////////////

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end


    //////////////////////////////////////////////////////
    // Control Unit Logic
    //////////////////////////////////////////////////////

    always @(posedge clk) begin
    
//        reset_delay <= reset;
        if (reset) begin
            count <= 3'd0;
            iter <= 5'd0;
            cn_sel <= 1;
            vn_sel <= 0;
            cn_reset <= 1;
            iter_flag <= 1;
            
        end 
        
        else begin

            /////////////////////////////////////////
            // Counter (8 cycles per iteration)
            /////////////////////////////////////////

            if (count == 3'd7) begin
                count <= 3'd0;
//                iter <= iter + 1;
            end
//            else if(count == 3'd6) begin
//                iter <= iter+1;
//            end
            else begin
                count <= count + 1;
            end
            
            if(count == 3'd6) begin
                iter<=iter+1;
            end


            /////////////////////////////////////////
            // iter_flag (only first iteration)
            /////////////////////////////////////////

            if (iter == 0)
                iter_flag <= 1;
            else
                iter_flag <= 0;


            /////////////////////////////////////////
            // CN reset (only at very start)
            /////////////////////////////////////////

            if (count == 3'd7)
                cn_reset <= 1;
            else
                cn_reset <= 0;


            /////////////////////////////////////////
            // Phase control
            /////////////////////////////////////////

            // cycles 0-3 → CN phase
            // cycles 4-7 → VN phase

            if (count < 3'd3 || count == 3'd7) begin
                cn_sel <= 1;
                vn_sel <= 0;
            end
//            else if(count ==3'd7)
//            begin
//                cn_sel <= 1;
//                vn_sel <= 0;
//            end 
            else begin
                cn_sel <= 0;
                vn_sel <= 1;
            end
        $display("Time=%0t | iter=%d | count=%d | cn_sel=%b | vn_sel=%b | iter_flag=%b | cn_reset=%b", 
                 $time, iter, count, cn_sel, vn_sel, iter_flag,cn_reset);
        end
    end


    //////////////////////////////////////////////////////
    // Print VN decisions each iteration
    //////////////////////////////////////////////////////

    always @(posedge clk) begin
        if(count == 3'd7) begin

            $display("------------- ITERATION %0d -------------", iter);

            for(i=0;i<12;i=i+1)
                $write("%0d ", dut.cv_list[i]);

            $display("\n");

        end
    end
    
    always@(posedge clk) begin
        
        if(iter=='d10) begin
            $display("Simulation Finished");
            $finish;
        end
        
    end

    //////////////////////////////////////////////////////
    // Simulation Sequence
    //////////////////////////////////////////////////////

    initial begin
        $display("Starting LDPC CU Simulation...");

//        $monitor("Time=%0t | iter=%d | count=%d | cn_sel=%b | vn_sel=%b | iter_flag=%b", 
//                 $time, iter, count, cn_sel, vn_sel, iter_flag);

        // Global Reset Phase
        reset = 1;
        #25; 
        reset = 0;

        // Run long enough for 15 iterations
        // 15 iterations × 8 cycles × 10ns = 1200ns

        #1300;

        $display("Simulation complete. Reached 15 iterations.");
        $finish;
    end

endmodule

