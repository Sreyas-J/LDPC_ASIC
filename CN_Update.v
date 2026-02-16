
module CN_Update(

    input reset,
    input [8:0] mcv_tprev,
    input [4:0] Lvc,
    output [8:0] mcv_t
    
    );
    
    // Input fields
    wire sc_tprev, Lvc_sign;
    wire [3:0] min1c_tprev, min2c_tprev, Lvc_mag;
    
    // output fields
    reg sc_t;
    reg [3:0] min1c_t, min2c_t;
    
    // Input slicing
    assign sc_tprev = mcv_tprev[8];
    assign min1c_tprev = mcv_tprev[7:4];
    assign min2c_tprev = mcv_tprev[3:0];
    assign Lvc_sign = Lvc[4];
    assign Lvc_mag = Lvc[3:0];
    
    
    // Logic- Active high reset
    always @(*)
    begin
    
        if(reset) 
        begin
            sc_t = Lvc_sign;
            min1c_t = Lvc_mag;
            min2c_t = 4'b1111;
        end
        else
        begin
        
            sc_t = sc_tprev ^ Lvc_sign;
            if (Lvc_mag < min1c_tprev)
            begin
                min2c_t = min1c_tprev;
                min1c_t = Lvc_mag;
            end
            else if (Lvc_mag < min2c_tprev)
            begin
                min1c_t = min1c_tprev;
                min2c_t = Lvc_mag;
            end
            else
            begin
                min1c_t = min1c_tprev;
                min2c_t = min2c_tprev;
            end
        
        end
    
    
    end
    
    // Output slicing
    assign mcv_t[8] = sc_t;
    assign mcv_t[7:4]  = min1c_t;
    assign mcv_t[3:0] = min2c_t;
    
    
    
    
    
endmodule
