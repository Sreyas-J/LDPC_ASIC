

module PE(
    
    input clk,
    input iter_flag,
    input reset,
    input cn_vn_sel, // To select CN : 0 or else for VN : 1
    input [26:0] mcv_tprev,
    input [4:0] Qv,
    output [26:0] mcv_t,
    output Cv
    );
    
    wire [14:0] mcv;
    wire [14:0] Lvc_tprev;
    reg w_ena;
    wire [14:0] Lvc;
    wire [14:0] Lvc_muxed;
    wire [6:0] Lv;
    
    Lvc_mem Lvc_cache(.clk(clk), .din(Lvc), .w_ena(w_ena), .dout(Lvc_tprev));
    
    genvar i;
    
    generate
    
        for(i = 0; i < 3; i = i + 1) 
            begin
            
                assign Lvc_muxed[5*i +: 5] = (iter_flag) ? Qv : Lvc_tprev[5*i +: 5];
    
    
                CN_Update layeri_cn (
                    .cn_ena(~cn_vn_sel),
                    .reset(reset),
                    .mcv_tprev(mcv_tprev[9*i +: 9]),
                    .Lvc_tprev(Lvc_muxed[5*i +: 5]),
                    .mcv_t(mcv_t[9*i +: 9])
                );
                
                
                VN_Update layeri_vn (
                     .clk(clk),
                    .vn_ena(cn_vn_sel), 
                    .mcv_tprev(mcv_tprev[9*i +: 9]), 
                    .Lvc_tprev(Lvc_muxed[5*i +: 5]), 
                    .Lv(Lv), // need to edit
                    .Lvc(Lvc[5*i +: 5]),
                    .mcv(mcv[5*i +: 5])
                );
            end
    
    endgenerate
    
    
    always @(posedge clk)
    begin
        w_ena <= cn_vn_sel;
    end
    
    assign Lv = mcv[4:0] + mcv[9:5] + mcv[14:10] + Qv;
    assign Cv = (Lv > 0) ? 1'b0 : 1'b1;
    
    
    
    
endmodule