

module PE(
    
    input clk,
    input iter_flag,
    input reset,
    input cn_sel,
    input vn_sel,
    input [2:0] bypass, 
    input [26:0] mcv_tprev,
    input [4:0] Qv,
    output reg [26:0] mcv_t,
    output Cv
    );
    
    wire [14:0] mcv;
    wire [14:0] Lvc_tprev;
    reg w_ena;
    wire [14:0] Lvc;
    wire [14:0] Lvc_muxed;
    wire [6:0] Lv;
    wire [26:0] mcv_temp;
    
    Lvc_mem Lvc_cache(.clk(clk), .din(Lvc), .w_ena(w_ena), .dout(Lvc_tprev));
    
    genvar i;
    
    generate
    
        for(i = 0; i < 3; i = i + 1) 
            begin
            
                assign Lvc_muxed[5*i +: 5] = (iter_flag) ? Qv : Lvc_tprev[5*i +: 5];
    
    
                CN_Update layeri_cn (
                    .cn_ena(cn_sel),
                    .reset(reset),
                    .bypass(bypass[i]),
                    .mcv_tprev(mcv_tprev[9*i +: 9]),
                    .Lvc_tprev(Lvc_muxed[5*i +: 5]),
                    .iter_flag(iter_flag),
                    .mcv_t(mcv_temp[9*i +: 9])
                );
                
                
                VN_Update layeri_vn (
                     .clk(clk),
                    .vn_ena(vn_sel),
                    .bypass(bypass[i]), 
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
        w_ena <= vn_sel;
    end
    
    assign Lv = mcv[4:0] + mcv[9:5] + mcv[14:10] + Qv;
    assign Cv = (Lv > 0) ? 1'b0 : 1'b1;
    
    always @(posedge clk)
    begin
    
        if((vn_sel) || (cn_sel))
        begin
            mcv_t <= mcv_temp;
        end
        else
        begin
            mcv_t <= mcv_tprev;
        end
    
    end
    
    
    
    
endmodule