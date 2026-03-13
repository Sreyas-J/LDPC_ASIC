module gen(

input clk,
input iter_flag,
input cn_reset,
input cn_sel,
input vn_sel,
input [59:0] qv_flat,          // Channel LLRs: 12 PEs x 5 bits, PE0 at [4:0]
output reg [11:0] cv_list
    );

    // ---------------------------------------------------------------
    // LDPC code: 12 variable nodes, 9 check nodes
    // H matrix:
    //   CN0: {1,3,11}       CN1: {2,4,9}        CN2: {0,5,10}
    //   CN3: {5,6,9}        CN4: {3,7,10}        CN5: {4,8,11}
    //   CN6: {1,3,8,10}     CN7: {2,4,6,11}      CN8: {0,5,7,9}
    //
    // PE degrees: PE0=2, PE1=2, PE2=2, PE3=3, PE4=3, PE5=3,
    //             PE6=2, PE7=2, PE8=2, PE9=3, PE10=3, PE11=3
    // Max degree = 3 → 3 layers per PE
    //
    // PE-to-layer assignment:
    //   PE0:  L0=CN2, L1=bypass, L2=CN8     bypass=3'b010
    //   PE1:  L0=CN0, L1=bypass, L2=CN6     bypass=3'b010
    //   PE2:  L0=CN1, L1=bypass, L2=CN7     bypass=3'b010
    //   PE3:  L0=CN0, L1=CN4, L2=CN6        bypass=3'b000
    //   PE4:  L0=CN1, L1=CN5, L2=CN7        bypass=3'b000
    //   PE5:  L0=CN2, L1=CN3, L2=CN8        bypass=3'b000
    //   PE6:  L0=bypass, L1=CN3, L2=CN7     bypass=3'b001
    //   PE7:  L0=bypass, L1=CN4, L2=CN8     bypass=3'b001
    //   PE8:  L0=bypass, L1=CN5, L2=CN6     bypass=3'b001
    //   PE9:  L0=CN1, L1=CN3, L2=CN8        bypass=3'b000
    //   PE10: L0=CN2, L1=CN4, L2=CN6        bypass=3'b000
    //   PE11: L0=CN0, L1=CN5, L2=CN7        bypass=3'b000
    // ---------------------------------------------------------------

    wire [26:0] mcv_t [0:11];      // CN summaries per PE (3 layers x 9 bits)
    wire [11:0] cv_comb;

    // Bypass per PE (3 bits each)
    wire [2:0] bypass [0:11];
    assign bypass[0]  = 3'b010;
    assign bypass[1]  = 3'b010;
    assign bypass[2]  = 3'b010;
    assign bypass[3]  = 3'b000;
    assign bypass[4]  = 3'b000;
    assign bypass[5]  = 3'b000;
    assign bypass[6]  = 3'b001;
    assign bypass[7]  = 3'b001;
    assign bypass[8]  = 3'b001;
    assign bypass[9]  = 3'b000;
    assign bypass[10] = 3'b000;
    assign bypass[11] = 3'b000;

    // Unpack the flat qv_flat input into per-PE wires
    wire [4:0] qv_list [0:11];
    genvar qv_i;
    generate
        for (qv_i = 0; qv_i < 12; qv_i = qv_i + 1) begin : qv_unpack
            assign qv_list[qv_i] = qv_flat[5*qv_i +: 5];
        end
    endgenerate

    // ---------------------------------------------------------------
    // Lvc wires: variable-to-check messages from each PE, 3 layers x 5 bits
    // ---------------------------------------------------------------
    wire [14:0] Lvc_out [0:11];       // Lvc output from each PE's Lvc_mem
    wire [14:0] Lvc_muxed [0:11];     // Lvc or Qv (depending on iter_flag)

    // ---------------------------------------------------------------
    // Check node summary registers: 9 bits per CN
    // Each CN stores {sign_xor, min1[3:0], min2[3:0]}
    // ---------------------------------------------------------------
    reg [8:0] cn_summary [0:8];

    // ---------------------------------------------------------------
    // CENTRAL CHECK NODE COMPUTATION (combinational)
    //
    // CN-to-PE-layer mapping:
    //   CN0: PE1(L0), PE3(L0), PE11(L0)
    //   CN1: PE2(L0), PE4(L0), PE9(L0)
    //   CN2: PE0(L0), PE5(L0), PE10(L0)
    //   CN3: PE5(L1), PE6(L1), PE9(L1)
    //   CN4: PE3(L1), PE7(L1), PE10(L1)
    //   CN5: PE4(L1), PE8(L1), PE11(L1)
    //   CN6: PE1(L2), PE3(L2), PE8(L2), PE10(L2)
    //   CN7: PE2(L2), PE4(L2), PE6(L2), PE11(L2)
    //   CN8: PE0(L2), PE5(L2), PE7(L2), PE9(L2)
    // ---------------------------------------------------------------

    // Extract sign and magnitude from each PE's Lvc for each layer
    wire [3:0] lvc_mag [0:11][0:2];   // [pe][layer]
    wire       lvc_sign [0:11][0:2];

    genvar gi, gl;
    generate
        for (gi = 0; gi < 12; gi = gi + 1) begin : lvc_extract
            for (gl = 0; gl < 3; gl = gl + 1) begin : lvc_layer
                assign lvc_sign[gi][gl] = Lvc_muxed[gi][5*gl + 4];
                assign lvc_mag[gi][gl]  = Lvc_muxed[gi][5*gl +: 4];
            end
        end
    endgenerate

    // CN computation: combinational min-sum for each check node
    reg [8:0] cn_summary_comb [0:8];

    reg        cn_sc;
    reg [3:0]  cn_min1, cn_min2;
    reg [3:0]  cn_lvc_mag_tmp;
    reg        cn_lvc_sign_tmp;

    always @(*) begin
        // ------ CN0: PE1(L0), PE3(L0), PE11(L0) ------
        cn_sc = lvc_sign[1][0];
        cn_min1 = lvc_mag[1][0];
        cn_min2 = 4'hF;
        // PE3
        cn_lvc_sign_tmp = lvc_sign[3][0]; cn_lvc_mag_tmp = lvc_mag[3][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE11
        cn_lvc_sign_tmp = lvc_sign[11][0]; cn_lvc_mag_tmp = lvc_mag[11][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[0] = {cn_sc, cn_min1, cn_min2};

        // ------ CN1: PE2(L0), PE4(L0), PE9(L0) ------
        cn_sc = lvc_sign[2][0];
        cn_min1 = lvc_mag[2][0];
        cn_min2 = 4'hF;
        // PE4
        cn_lvc_sign_tmp = lvc_sign[4][0]; cn_lvc_mag_tmp = lvc_mag[4][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE9
        cn_lvc_sign_tmp = lvc_sign[9][0]; cn_lvc_mag_tmp = lvc_mag[9][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[1] = {cn_sc, cn_min1, cn_min2};

        // ------ CN2: PE0(L0), PE5(L0), PE10(L0) ------
        cn_sc = lvc_sign[0][0];
        cn_min1 = lvc_mag[0][0];
        cn_min2 = 4'hF;
        // PE5
        cn_lvc_sign_tmp = lvc_sign[5][0]; cn_lvc_mag_tmp = lvc_mag[5][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE10
        cn_lvc_sign_tmp = lvc_sign[10][0]; cn_lvc_mag_tmp = lvc_mag[10][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[2] = {cn_sc, cn_min1, cn_min2};

        // ------ CN3: PE5(L1), PE6(L1), PE9(L1) ------
        cn_sc = lvc_sign[5][1];
        cn_min1 = lvc_mag[5][1];
        cn_min2 = 4'hF;
        // PE6
        cn_lvc_sign_tmp = lvc_sign[6][1]; cn_lvc_mag_tmp = lvc_mag[6][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE9
        cn_lvc_sign_tmp = lvc_sign[9][1]; cn_lvc_mag_tmp = lvc_mag[9][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[3] = {cn_sc, cn_min1, cn_min2};

        // ------ CN4: PE3(L1), PE7(L1), PE10(L1) ------
        cn_sc = lvc_sign[3][1];
        cn_min1 = lvc_mag[3][1];
        cn_min2 = 4'hF;
        // PE7
        cn_lvc_sign_tmp = lvc_sign[7][1]; cn_lvc_mag_tmp = lvc_mag[7][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE10
        cn_lvc_sign_tmp = lvc_sign[10][1]; cn_lvc_mag_tmp = lvc_mag[10][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[4] = {cn_sc, cn_min1, cn_min2};

        // ------ CN5: PE4(L1), PE8(L1), PE11(L1) ------
        cn_sc = lvc_sign[4][1];
        cn_min1 = lvc_mag[4][1];
        cn_min2 = 4'hF;
        // PE8
        cn_lvc_sign_tmp = lvc_sign[8][1]; cn_lvc_mag_tmp = lvc_mag[8][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE11
        cn_lvc_sign_tmp = lvc_sign[11][1]; cn_lvc_mag_tmp = lvc_mag[11][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[5] = {cn_sc, cn_min1, cn_min2};

        // ------ CN6: PE1(L2), PE3(L2), PE8(L2), PE10(L2) ------
        cn_sc = lvc_sign[1][2];
        cn_min1 = lvc_mag[1][2];
        cn_min2 = 4'hF;
        // PE3
        cn_lvc_sign_tmp = lvc_sign[3][2]; cn_lvc_mag_tmp = lvc_mag[3][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE8
        cn_lvc_sign_tmp = lvc_sign[8][2]; cn_lvc_mag_tmp = lvc_mag[8][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE10
        cn_lvc_sign_tmp = lvc_sign[10][2]; cn_lvc_mag_tmp = lvc_mag[10][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[6] = {cn_sc, cn_min1, cn_min2};

        // ------ CN7: PE2(L2), PE4(L2), PE6(L2), PE11(L2) ------
        cn_sc = lvc_sign[2][2];
        cn_min1 = lvc_mag[2][2];
        cn_min2 = 4'hF;
        // PE4
        cn_lvc_sign_tmp = lvc_sign[4][2]; cn_lvc_mag_tmp = lvc_mag[4][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE6
        cn_lvc_sign_tmp = lvc_sign[6][2]; cn_lvc_mag_tmp = lvc_mag[6][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE11
        cn_lvc_sign_tmp = lvc_sign[11][2]; cn_lvc_mag_tmp = lvc_mag[11][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[7] = {cn_sc, cn_min1, cn_min2};

        // ------ CN8: PE0(L2), PE5(L2), PE7(L2), PE9(L2) ------
        cn_sc = lvc_sign[0][2];
        cn_min1 = lvc_mag[0][2];
        cn_min2 = 4'hF;
        // PE5
            cn_lvc_sign_tmp = lvc_sign[5][2]; cn_lvc_mag_tmp = lvc_mag[5][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE7
        cn_lvc_sign_tmp = lvc_sign[7][2]; cn_lvc_mag_tmp = lvc_mag[7][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // PE9
        cn_lvc_sign_tmp = lvc_sign[9][2]; cn_lvc_mag_tmp = lvc_mag[9][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[8] = {cn_sc, cn_min1, cn_min2};
    end

    // ---------------------------------------------------------------
    // Register CN summaries on cn_sel edge
    // ---------------------------------------------------------------
    integer s;
    initial begin
        for (s = 0; s < 9; s = s + 1) cn_summary[s] = 9'h0FF;
    end

    always @(posedge clk) begin
        if (cn_sel) begin
            for (s = 0; s < 9; s = s + 1)
                cn_summary[s] <= cn_summary_comb[s];
        end
    end

    // ---------------------------------------------------------------
    // Map CN summaries back to per-PE mcv_t format
    //
    // mcv_t[pe] = {L2_cn_summary, L1_cn_summary, L0_cn_summary}
    // Bypassed layers get 9'h1FF
    //
    // PE  | L0   | L1   | L2
    //  0  | CN2  | byp  | CN8
    //  1  | CN0  | byp  | CN6
    //  2  | CN1  | byp  | CN7
    //  3  | CN0  | CN4  | CN6
    //  4  | CN1  | CN5  | CN7
    //  5  | CN2  | CN3  | CN8
    //  6  | byp  | CN3  | CN7
    //  7  | byp  | CN4  | CN8
    //  8  | byp  | CN5  | CN6
    //  9  | CN1  | CN3  | CN8
    // 10  | CN2  | CN4  | CN6
    // 11  | CN0  | CN5  | CN7
    // ---------------------------------------------------------------
    assign mcv_t[0]  = {cn_summary[8], 9'h1FF, cn_summary[2]};
    assign mcv_t[1]  = {cn_summary[6], 9'h1FF, cn_summary[0]};
    assign mcv_t[2]  = {cn_summary[7], 9'h1FF, cn_summary[1]};
    assign mcv_t[3]  = {cn_summary[6], cn_summary[4], cn_summary[0]};
    assign mcv_t[4]  = {cn_summary[7], cn_summary[5], cn_summary[1]};
    assign mcv_t[5]  = {cn_summary[8], cn_summary[3], cn_summary[2]};
    assign mcv_t[6]  = {cn_summary[7], cn_summary[3], 9'h1FF};
    assign mcv_t[7]  = {cn_summary[8], cn_summary[4], 9'h1FF};
    assign mcv_t[8]  = {cn_summary[6], cn_summary[5], 9'h1FF};
    assign mcv_t[9]  = {cn_summary[8], cn_summary[3], cn_summary[1]};
    assign mcv_t[10] = {cn_summary[6], cn_summary[4], cn_summary[2]};
    assign mcv_t[11] = {cn_summary[7], cn_summary[5], cn_summary[0]};

    // ---------------------------------------------------------------
    // Pipeline: simple 2-phase (cn_sel → vn_sel)
    // ---------------------------------------------------------------
    reg vn_sel_d;
    initial begin
        vn_sel_d = 1'b0;
        cv_list  = 12'b0;
    end

    always @(posedge clk) begin
        vn_sel_d <= vn_sel;
    end

    always @(posedge clk) begin
        if (vn_sel_d)
            cv_list <= cv_comb;
    end

    // ---------------------------------------------------------------
    // PE instantiation: all 12 PEs run simultaneously
    // ---------------------------------------------------------------
    genvar j;
    generate
    for (j = 0; j < 12; j = j + 1) begin : pe_inst
        PE pe(
            .clk(clk),
            .iter_flag(iter_flag),
            .vn_sel(vn_sel),
            .bypass(bypass[j]),
            .mcv_tprev(mcv_t[j]),
            .Qv(qv_list[j]),
            .Cv(cv_comb[j]),
            .Lvc_out(Lvc_out[j]),
            .Lvc_muxed_out(Lvc_muxed[j])
        );
    end
    endgenerate

endmodule
