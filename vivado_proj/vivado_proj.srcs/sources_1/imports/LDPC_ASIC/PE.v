module PE #(
    parameter MAX_DV = 3,
    parameter LV_BITS = 7
)(
    input                        clk,
    input                        rst,
    input                        iter_flag,
    input                        vn_sel,
    input  [MAX_DV-1:0]          bypass,
    input  [9*MAX_DV-1:0]        mcv_tprev,
    input  [4:0]                 Qv,
    output                       Cv,
    output [5*MAX_DV-1:0]        Lvc_out,
    output [5*MAX_DV-1:0]        Lvc_muxed_out
);

    wire [5*MAX_DV-1:0] mcv;
    wire [5*MAX_DV-1:0] Lvc_tprev;
    reg w_ena;
    wire [5*MAX_DV-1:0] Lvc;
    wire [5*MAX_DV-1:0] Lvc_muxed;

    wire signed [LV_BITS-1:0] Lv;

    Lvc_mem #(.MAX_DV(MAX_DV)) Lvc_cache(
        .clk(clk), .rst(rst), .din(Lvc), .w_ena(w_ena), .dout(Lvc_tprev)
    );

    assign Lvc_out = Lvc_tprev;
    assign Lvc_muxed_out = Lvc_muxed;

    genvar i;
    generate
        for(i = 0; i < MAX_DV; i = i + 1)
        begin : layer_gen
            assign Lvc_muxed[5*i +: 5] = (iter_flag) ? Qv : Lvc_tprev[5*i +: 5];

            VN_Update #(.LV_BITS(LV_BITS)) layeri_vn (
                .clk(clk),
                .rst(rst),
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

    always @(posedge clk or posedge rst)
    begin
        if (rst)
            w_ena <= 1'b0;
        else
            w_ena <= vn_sel;
    end

    // Qv sign-magnitude to 2's complement conversion
    wire signed [LV_BITS-1:0] Qv_2scomp;
    assign Qv_2scomp = Qv[4]
        ? -$signed({{(LV_BITS-4){1'b0}}, Qv[3:0]})
        :  $signed({{(LV_BITS-4){1'b0}}, Qv[3:0]});

    // Total LLR = sum of all extrinsic messages + channel LLR
    reg signed [LV_BITS-1:0] Lv_sum;
    integer k;
    always @(*) begin
        Lv_sum = Qv_2scomp;
        for (k = 0; k < MAX_DV; k = k + 1)
            Lv_sum = Lv_sum + $signed(mcv[5*k +: 5]);
    end
    assign Lv = Lv_sum;

    // Hard decision: Cv=1 if Lv<=0, Cv=0 if Lv>0
    assign Cv = (Lv > 0) ? 1'b0 : 1'b1;

endmodule
