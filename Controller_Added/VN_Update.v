module VN_Update(
    input clk,
    input vn_ena,
    input bypass,
    input [8:0] mcv_tprev,
    input [4:0] Lvc_tprev,
    input signed [6:0] Lv,
    output signed [4:0] Lvc,
    output [4:0] mcv
);

    wire sc_tprev, Lvc_tprev_sign;
    wire [3:0] min1c_tprev, min2c_tprev, Lvc_tprev_mag;

    reg signed [4:0] Lvc_reg;   // internal 2's-complement LLR (-15..+15)
    reg signed [4:0] Lvc_abs;   // absolute value helper

    wire mcv_sign;
    reg [3:0] mcv_mag;

    reg [4:0] mcv_latch;
    reg [4:0] Lvc_latch;

    initial begin
        mcv_latch = 5'b0;
        Lvc_latch = 5'b0;
        Lvc_reg   = 5'b0;
    end

    // Input slicing
    assign sc_tprev        = mcv_tprev[8];
    assign min1c_tprev     = mcv_tprev[7:4];
    assign min2c_tprev     = mcv_tprev[3:0];
    assign Lvc_tprev_sign  = Lvc_tprev[4];
    assign Lvc_tprev_mag   = Lvc_tprev[3:0];

    // mcv_mag selection (magnitudes only)
    always @(*) begin
        if (min1c_tprev == Lvc_tprev_mag) mcv_mag = min2c_tprev;
        else                               mcv_mag = min1c_tprev;
    end

    assign mcv_sign = Lvc_tprev_sign ^ sc_tprev;

    // mcv latch (2's-complement extrinsic)
    always @(*) begin
        if (bypass)
            mcv_latch = 5'b0;
        else if (vn_ena)
            mcv_latch = (mcv_sign) ? -{1'b0, mcv_mag} : {1'b0, mcv_mag};
    end
    assign mcv = mcv_latch;

    // Saturation (Lv - mcv can be ±78 → clamp to 5-bit range)
    wire signed [6:0] Lvc_full;
    assign Lvc_full = Lv - $signed({{2{mcv[4]}}, mcv});

    always @(posedge clk) begin
        if      (Lvc_full >  7'sd15) Lvc_reg <=  5'sd15;
        else if (Lvc_full < -7'sd15) Lvc_reg <= -5'sd15;
        else                         Lvc_reg <= Lvc_full[4:0];
    end

    // Absolute value for correct sign-magnitude output
    always @(*) begin
        Lvc_abs = Lvc_reg[4] ? -Lvc_reg : Lvc_reg;
    end

    always @(*) begin
        if (vn_ena)
            Lvc_latch = {Lvc_reg[4], Lvc_abs[3:0]};
    end
    assign Lvc = Lvc_latch;

endmodule
