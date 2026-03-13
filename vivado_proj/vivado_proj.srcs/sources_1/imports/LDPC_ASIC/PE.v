module PE #(
    parameter NUM_LAYERS = 3,
    parameter LLR_BITS   = 5
)(
    input                              clk,
    input                              iter_flag,
    input                              vn_sel,
    input  [NUM_LAYERS-1:0]            bypass, 
    input  [9*NUM_LAYERS-1:0]          mcv_tprev,       // Complete CN summary for this PE's layers
    input  [LLR_BITS-1:0]             Qv,
    output                             Cv,
    output [LLR_BITS*NUM_LAYERS-1:0]   Lvc_out,         // Raw Lvc from memory (for gen.v CN computation)
    output [LLR_BITS*NUM_LAYERS-1:0]   Lvc_muxed_out    // Muxed Lvc (Qv on iter_flag, else Lvc_out)
    );

    localparam LVC_WIDTH = LLR_BITS * NUM_LAYERS;

    wire [LVC_WIDTH-1:0] mcv;
    wire [LVC_WIDTH-1:0] Lvc_tprev;
    reg w_ena;
    wire [LVC_WIDTH-1:0] Lvc;
    wire [LVC_WIDTH-1:0] Lvc_muxed;

    // Lv width: needs to hold sum of NUM_LAYERS sign-extended 5-bit values + Qv
    // Each mcv is 5-bit signed (-15..+15), so sum can be ±(NUM_LAYERS*15 + 15)
    // Use enough bits: ceil(log2(NUM_LAYERS*15+15)) + 1 sign bit
    // For safety, use LLR_BITS + $clog2(NUM_LAYERS+1) bits
    localparam LV_BITS = LLR_BITS + $clog2(NUM_LAYERS + 1) + 1;
    wire signed [LV_BITS-1:0] Lv;

    initial begin
        w_ena = 1'b0;
    end

    Lvc_mem #(.DATA_WIDTH(LVC_WIDTH)) Lvc_cache(
        .clk(clk), .din(Lvc), .w_ena(w_ena), .dout(Lvc_tprev)
    );
    
    assign Lvc_out = Lvc_tprev;
    assign Lvc_muxed_out = Lvc_muxed;
    
    genvar i;
    generate
        for(i = 0; i < NUM_LAYERS; i = i + 1) 
        begin : layer_inst
            assign Lvc_muxed[LLR_BITS*i +: LLR_BITS] = (iter_flag) ? Qv : Lvc_tprev[LLR_BITS*i +: LLR_BITS];

            VN_Update #(.LV_BITS(LV_BITS)) layeri_vn (
                .clk(clk),
                .vn_ena(vn_sel),
                .bypass(bypass[i]), 
                .mcv_tprev(mcv_tprev[9*i +: 9]),
                .Lvc_tprev(Lvc_muxed[LLR_BITS*i +: LLR_BITS]), 
                .Lv(Lv),
                .Lvc(Lvc[LLR_BITS*i +: LLR_BITS]),
                .mcv(mcv[LLR_BITS*i +: LLR_BITS])
            );
        end
    endgenerate
    
    always @(posedge clk)
    begin
        w_ena <= vn_sel;
    end
    
    // Qv sign-magnitude to 2's complement conversion
    wire signed [LV_BITS-1:0] Qv_2scomp;
    assign Qv_2scomp = Qv[LLR_BITS-1] ? -$signed({{(LV_BITS-LLR_BITS+1){1'b0}}, Qv[LLR_BITS-2:0]}) 
                                        : $signed({{(LV_BITS-LLR_BITS+1){1'b0}}, Qv[LLR_BITS-2:0]});

    // Total LLR = sum of all extrinsic messages + channel LLR
    // Parameterized summation over NUM_LAYERS
    reg signed [LV_BITS-1:0] mcv_sum;
    integer k;
    always @(*) begin
        mcv_sum = {LV_BITS{1'b0}};
        for (k = 0; k < NUM_LAYERS; k = k + 1) begin
            mcv_sum = mcv_sum + $signed(mcv[LLR_BITS*k +: LLR_BITS]);
        end
    end

    assign Lv = mcv_sum + Qv_2scomp;

    // Hard decision: Cv=1 if Lv<=0 (bit is 1), Cv=0 if Lv>0 (bit is 0)
    assign Cv = (Lv > 0) ? 1'b0 : 1'b1;
    
endmodule