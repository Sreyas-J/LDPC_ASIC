
module VN_Update(

    input clk,
    input [8:0] mcv_tprev,
    input [4:0] Lvc_tprev,
    input [6:0] Lv,
    output signed [4:0] Lvc,
    output [4:0] mcv

    );
    
    // Input fields
    wire sc_tprev, Lvc_tprev_sign;
    wire [3:0] min1c_tprev, min2c_tprev, Lvc_tprev_mag;
    
    // temp vars
    reg [4:0] Lvc_reg;
    
    // output fields
   reg Lvc_sign; 
   wire mcv_sign;
   reg [3:0] Lvc_mag, mcv_mag;
    
    // Input slicing
    assign sc_tprev = mcv_tprev[8];
    assign min1c_tprev = mcv_tprev[7:4];
    assign min2c_tprev = mcv_tprev[3:0];
    assign Lvc_tprev_sign = Lvc_tprev[4];
    assign Lvc_tprev_mag = Lvc_tprev[3:0];
    
    
    // Comb logic
    
    always @(*)
    begin
        if(min1c_tprev == Lvc_tprev) mcv_mag = min2c_tprev;
        else mcv_mag = min1c_tprev;
        
    end
    
    assign  mcv_sign = Lvc_tprev_sign ^ sc_tprev;
    assign mcv = (mcv_sign) ? ~{1'b0, (mcv_mag + 1'b1)} : {1'b0,mcv_mag};
    
    // Sequential block
    always @(posedge clk)
    begin
        Lvc_reg <= Lv - mcv;
    end
    
    
//    assign Lvc = (Lvc_reg[4]) ? ~{1'b0, (Lvc_reg[3:0] + 1'b1)} : Lvc_reg;
      assign Lvc = Lvc_reg;    
    
    
endmodule
