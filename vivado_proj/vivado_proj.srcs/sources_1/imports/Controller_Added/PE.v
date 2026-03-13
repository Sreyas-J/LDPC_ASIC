module PE(
    input         clk,
    input         iter_flag,
    input         vn_sel,
    input  [2:0]  bypass, 
    input  [26:0] mcv_tprev,       // Complete CN summary for this PE's 3 layers
    input  [4:0]  Qv,
    output        Cv,
    output [14:0] Lvc_out,         // Raw Lvc from memory (for gen.v CN computation)
    output [14:0] Lvc_muxed_out    // Muxed Lvc (Qv on iter_flag, else Lvc_out)
    );
    
    wire [14:0] mcv;
    wire [14:0] Lvc_tprev;
    reg w_ena;
    wire [14:0] Lvc;
    wire [14:0] Lvc_muxed;

    wire signed [6:0] Lv;

    initial begin
        w_ena = 1'b0;
    end

    Lvc_mem Lvc_cache(.clk(clk), .din(Lvc), .w_ena(w_ena), .dout(Lvc_tprev));
    
    assign Lvc_out = Lvc_tprev;
    assign Lvc_muxed_out = Lvc_muxed;
    
    genvar i;
    generate
        for(i = 0; i < 3; i = i + 1) 
        begin
            assign Lvc_muxed[5*i +: 5] = (iter_flag) ? Qv : Lvc_tprev[5*i +: 5];

            VN_Update layeri_vn (
                .clk(clk),
                .vn_ena(vn_sel),
                .bypass(bypass[i]), 
                .mcv_tprev(mcv_tprev[9*i +: 9]),
                .Lvc_tprev(Lvc_muxed[5*i +: 5]), 
                .Lv(Lv),
                .Lvc(Lvc[5*i +: 5]),
                .mcv(mcv[5*i +: 5])
            );
        end
    endgenerate
    
    always @(posedge clk)
    begin
        w_ena <= vn_sel;
    end
    
    // Qv sign-magnitude to 2's complement conversion
    wire signed [6:0] Qv_2scomp;
    assign Qv_2scomp = Qv[4] ? -$signed({3'b000, Qv[3:0]}) : $signed({3'b000, Qv[3:0]});

    // Total LLR = sum of extrinsic messages + channel LLR
    assign Lv = $signed(mcv[4:0]) + $signed(mcv[9:5]) + $signed(mcv[14:10]) + Qv_2scomp;
    // Hard decision: Cv=1 if Lv<=0 (bit is 1), Cv=0 if Lv>0 (bit is 0)
    assign Cv = (Lv > 0) ? 1'b0 : 1'b1;
    
endmodule