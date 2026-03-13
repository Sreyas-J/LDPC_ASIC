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
    // LDPC (3,4)-regular code: 12 variable nodes, 9 check nodes
    // Each VN has degree 3 (2 active + 1 bypassed)
    // Each CN has degree 3-4
    //
    // Architecture: centralised FLOODING min-sum decoder
    //   - Lvc stored per PE (in Lvc_mem inside PE)
    //   - CN summaries computed centrally in gen.v from all PEs' Lvc
    //   - Each PE does VN_Update using the complete CN summary
    // ---------------------------------------------------------------

    wire [26:0] mcv_t [0:11];      // CN summaries per PE (from central computation)
    wire [11:0] cv_comb;

    // ---------------------------------------------------------------
    // Graph configuration
    // ---------------------------------------------------------------
    // Check node membership: which PEs are connected to each CN (by layer)
    //
    // Layer 0: CN0={PE1,PE3,PE11} + PE6*   CN1={PE2,PE4,PE9} + PE7*   CN2={PE0,PE5,PE10} + PE8*
    //          (* = bypassed: PE6 in CN0, PE7 in CN1, PE8 in CN2)
    // Layer 1: CN3={PE5,PE6,PE9} + PE0*    CN4={PE3,PE7,PE10} + PE1*  CN5={PE4,PE8,PE11} + PE2*
    //          (* = bypassed: PE0 in CN3, PE1 in CN4, PE2 in CN5)
    // Layer 2: CN6={PE1,PE3,PE8,PE10}      CN7={PE2,PE4,PE6,PE11}     CN8={PE0,PE5,PE7,PE9}
    //          (no bypasses in layer 2)
    //
    // Bypass: PE0=layer1, PE1=layer1, PE2=layer1
    //         PE6=layer0, PE7=layer0, PE8=layer0
    //         (PEs 3,4,5,9,10,11 = no bypass)
    
    reg [2:0]  bypass [0:11];
    reg [11:0] edgelist [0:11];      // CN routing: used for both CN accum and VN lookup
    reg [3:0]  bypass_list [0:11];

    // Unpack the flat qv_flat input into per-PE wires
    // PE k occupies bits [5*k+4 : 5*k] of qv_flat
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
    // Check node summary registers: 9 bits per CN per layer
    // Each CN stores {sign_xor, min1[3:0], min2[3:0]}
    // ---------------------------------------------------------------
    reg [8:0] cn_summary [0:8];       // 9 check nodes
    
    initial begin
        edgelist[0]  = 12'ha99;
        edgelist[1]  = 12'hbaa;
        edgelist[2]  = 12'h9bb;
        edgelist[3]  = 12'h111;
        edgelist[4]  = 12'h222;
        edgelist[5]  = 12'h000;
        edgelist[6]  = 12'h354;
        edgelist[7]  = 12'h435;
        edgelist[8]  = 12'h543;
        edgelist[9]  = 12'h767;
        edgelist[10] = 12'h878;
        edgelist[11] = 12'h686;
    
        bypass_list[0]  = 4'h3;
        bypass_list[1]  = 4'h4;
        bypass_list[2]  = 4'h5;
        bypass_list[3]  = 4'hF;
        bypass_list[4]  = 4'hF;
        bypass_list[5]  = 4'hF;
        bypass_list[6]  = 4'h0;
        bypass_list[7]  = 4'h1;
        bypass_list[8]  = 4'h2;
        bypass_list[9]  = 4'hF;
        bypass_list[10] = 4'hF;
        bypass_list[11] = 4'hF;
    
    end
    
    // ---------------------------------------------------------------
    // Bypass computation
    // ---------------------------------------------------------------
    integer a;
    always @(*) begin
        for (a = 0; a < 12; a = a + 1) begin
            if (bypass_list[a] == edgelist[a][11:8]) bypass[a] = 3'b100;
            else if (bypass_list[a] == edgelist[a][7:4]) bypass[a] = 3'b010;
            else if (bypass_list[a] == edgelist[a][3:0]) bypass[a] = 3'b001;
            else bypass[a] = 3'b000;
        end
    end

    // ---------------------------------------------------------------
    // CENTRAL CHECK NODE COMPUTATION (combinational)
    //
    // For each of 9 check nodes, compute the min-sum summary:
    //   sign_xor = XOR of all connected VN signs
    //   min1     = minimum magnitude across all connected VNs
    //   min2     = second minimum magnitude
    //
    // The check nodes are identified by (layer, chain_index):
    //   CN0 (layer0): PEs {1,3,6*,11}  — PE6 bypassed
    //   CN1 (layer0): PEs {2,4,7*,9}   — PE7 bypassed
    //   CN2 (layer0): PEs {0,5,8*,10}  — PE8 bypassed
    //   CN3 (layer1): PEs {0*,5,6,9}   — PE0 bypassed
    //   CN4 (layer1): PEs {1*,3,7,10}  — PE1 bypassed
    //   CN5 (layer1): PEs {2*,4,8,11}  — PE2 bypassed
    //   CN6 (layer2): PEs {1,3,8,10}   — all active
    //   CN7 (layer2): PEs {2,4,6,11}   — all active
    //   CN8 (layer2): PEs {0,5,7,9}    — all active
    //
    // Each PE's Lvc for layer L is at Lvc_muxed[PE][5*L +: 5]
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
    // Compute cn_summary_comb combinationally, register into cn_summary on cn_sel
    reg [8:0] cn_summary_comb [0:8];

    // Helper task: accumulate one edge into a running CN summary
    // Uses procedural variables within always @* block
    reg        cn_sc;
    reg [3:0]  cn_min1, cn_min2;
    reg [3:0]  cn_lvc_mag_tmp;
    reg        cn_lvc_sign_tmp;

    always @(*) begin
        // ------ CN0 (layer 0): PEs 1, 3, 11 (PE6 bypassed) ------
        cn_sc = lvc_sign[1][0];
        cn_min1 = lvc_mag[1][0];
        cn_min2 = 4'hF;
        // Accumulate PE3
        cn_lvc_sign_tmp = lvc_sign[3][0];
        cn_lvc_mag_tmp = lvc_mag[3][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        // Accumulate PE11
        cn_lvc_sign_tmp = lvc_sign[11][0];
        cn_lvc_mag_tmp = lvc_mag[11][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[0] = {cn_sc, cn_min1, cn_min2};

        // ------ CN1 (layer 0): PEs 2, 4, 9 (PE7 bypassed) ------
        cn_sc = lvc_sign[2][0];
        cn_min1 = lvc_mag[2][0];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[4][0]; cn_lvc_mag_tmp = lvc_mag[4][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[9][0]; cn_lvc_mag_tmp = lvc_mag[9][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[1] = {cn_sc, cn_min1, cn_min2};

        // ------ CN2 (layer 0): PEs 0, 5, 10 (PE8 bypassed) ------
        cn_sc = lvc_sign[0][0];
        cn_min1 = lvc_mag[0][0];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[5][0]; cn_lvc_mag_tmp = lvc_mag[5][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[10][0]; cn_lvc_mag_tmp = lvc_mag[10][0];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[2] = {cn_sc, cn_min1, cn_min2};

        // ------ CN3 (layer 1): PEs 5, 6, 9 (PE0 bypassed) ------
        cn_sc = lvc_sign[5][1];
        cn_min1 = lvc_mag[5][1];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[6][1]; cn_lvc_mag_tmp = lvc_mag[6][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[9][1]; cn_lvc_mag_tmp = lvc_mag[9][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[3] = {cn_sc, cn_min1, cn_min2};

        // ------ CN4 (layer 1): PEs 3, 7, 10 (PE1 bypassed) ------
        cn_sc = lvc_sign[3][1];
        cn_min1 = lvc_mag[3][1];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[7][1]; cn_lvc_mag_tmp = lvc_mag[7][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[10][1]; cn_lvc_mag_tmp = lvc_mag[10][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[4] = {cn_sc, cn_min1, cn_min2};

        // ------ CN5 (layer 1): PEs 4, 8, 11 (PE2 bypassed) ------
        cn_sc = lvc_sign[4][1];
        cn_min1 = lvc_mag[4][1];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[8][1]; cn_lvc_mag_tmp = lvc_mag[8][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[11][1]; cn_lvc_mag_tmp = lvc_mag[11][1];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[5] = {cn_sc, cn_min1, cn_min2};

        // ------ CN6 (layer 2): PEs 1, 3, 8, 10 — all active ------
        cn_sc = lvc_sign[1][2];
        cn_min1 = lvc_mag[1][2];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[3][2]; cn_lvc_mag_tmp = lvc_mag[3][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[8][2]; cn_lvc_mag_tmp = lvc_mag[8][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[10][2]; cn_lvc_mag_tmp = lvc_mag[10][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[6] = {cn_sc, cn_min1, cn_min2};

        // ------ CN7 (layer 2): PEs 2, 4, 6, 11 — all active ------
        cn_sc = lvc_sign[2][2];
        cn_min1 = lvc_mag[2][2];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[4][2]; cn_lvc_mag_tmp = lvc_mag[4][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[6][2]; cn_lvc_mag_tmp = lvc_mag[6][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[11][2]; cn_lvc_mag_tmp = lvc_mag[11][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_summary_comb[7] = {cn_sc, cn_min1, cn_min2};

        // ------ CN8 (layer 2): PEs 0, 5, 7, 9 — all active ------
        cn_sc = lvc_sign[0][2];
        cn_min1 = lvc_mag[0][2];
        cn_min2 = 4'hF;
        cn_lvc_sign_tmp = lvc_sign[5][2]; cn_lvc_mag_tmp = lvc_mag[5][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
        cn_lvc_sign_tmp = lvc_sign[7][2]; cn_lvc_mag_tmp = lvc_mag[7][2];
        cn_sc = cn_sc ^ cn_lvc_sign_tmp;
        if (cn_lvc_mag_tmp < cn_min1) begin cn_min2 = cn_min1; cn_min1 = cn_lvc_mag_tmp; end
        else if (cn_lvc_mag_tmp < cn_min2) begin cn_min2 = cn_lvc_mag_tmp; end
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
    // For each PE, mcv_t[pe] = {cn_summary_for_layer2, cn_summary_for_layer1, cn_summary_for_layer0}
    //
    // PE-to-CN mapping:
    //   PE  | Layer0 | Layer1 | Layer2
    //   0   | CN2    | CN3*   | CN8      (* = bypassed)
    //   1   | CN0    | CN4*   | CN6
    //   2   | CN1    | CN5*   | CN7
    //   3   | CN0    | CN4    | CN6
    //   4   | CN1    | CN5    | CN7
    //   5   | CN2    | CN3    | CN8
    //   6   | CN0*   | CN3    | CN7
    //   7   | CN1*   | CN4    | CN8
    //   8   | CN2*   | CN5    | CN6
    //   9   | CN1    | CN3    | CN8
    //   10  | CN2    | CN4    | CN6
    //   11  | CN0    | CN5    | CN7
    // ---------------------------------------------------------------
    assign mcv_t[0]  = {cn_summary[8], cn_summary[3], cn_summary[2]};
    assign mcv_t[1]  = {cn_summary[6], cn_summary[4], cn_summary[0]};
    assign mcv_t[2]  = {cn_summary[7], cn_summary[5], cn_summary[1]};
    assign mcv_t[3]  = {cn_summary[6], cn_summary[4], cn_summary[0]};
    assign mcv_t[4]  = {cn_summary[7], cn_summary[5], cn_summary[1]};
    assign mcv_t[5]  = {cn_summary[8], cn_summary[3], cn_summary[2]};
    assign mcv_t[6]  = {cn_summary[7], cn_summary[3], cn_summary[0]};
    assign mcv_t[7]  = {cn_summary[8], cn_summary[4], cn_summary[1]};
    assign mcv_t[8]  = {cn_summary[6], cn_summary[5], cn_summary[2]};
    assign mcv_t[9]  = {cn_summary[8], cn_summary[3], cn_summary[1]};
    assign mcv_t[10] = {cn_summary[6], cn_summary[4], cn_summary[2]};
    assign mcv_t[11] = {cn_summary[7], cn_summary[5], cn_summary[0]};

    // ---------------------------------------------------------------
    // Pipeline: simple 2-phase (cn_sel → vn_sel)
    // No staggering needed — all PEs process simultaneously
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