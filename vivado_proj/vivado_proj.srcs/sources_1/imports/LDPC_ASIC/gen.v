module gen #(
    parameter NUM_PE        = 12,   // Number of PEs (variable nodes)
    parameter NUM_CN        = 9,    // Number of check nodes
    parameter NUM_LAYERS    = 3,    // Layers per PE (VN degree = # of CNs each VN connects to)
    parameter MAX_CN_DEGREE = 4,    // Maximum degree of any check node
    parameter LLR_BITS      = 5,    // Bits per LLR (sign-magnitude)
    parameter CN_INDEX_BITS = 4     // Bits used per CN index in edgeList nibbles
)(
    input clk,
    input iter_flag,
    input cn_reset,
    input cn_sel,
    input vn_sel,
    input [NUM_PE*LLR_BITS-1:0] qv_flat,   // Channel LLRs: NUM_PE PEs x LLR_BITS bits
    output reg [NUM_PE-1:0] cv_list
);

    // ---------------------------------------------------------------
    // Parameterised LDPC flooding min-sum decoder
    //
    // Architecture: centralised FLOODING min-sum decoder
    //   - Lvc stored per PE (in Lvc_mem inside PE)
    //   - CN summaries computed centrally in gen.v from all PEs' Lvc
    //   - Each PE does VN_Update using the complete CN summary
    //
    // To use a different H matrix, modify:
    //   1. The parameters above (NUM_PE, NUM_CN, NUM_LAYERS, MAX_CN_DEGREE)
    //   2. edgeList[pe]       — which CN each PE connects to per layer
    //   3. bypass_list[pe]    — which CN (if any) this PE bypasses
    //   4. cn_pe_table[cn][slot] — which PEs connect to each CN
    //   5. cn_layer_table[cn][slot] — which layer each PE uses for that CN
    //   6. cn_degree[cn]      — number of active (non-bypassed) PEs per CN
    // ---------------------------------------------------------------

    localparam LV_BITS   = LLR_BITS + $clog2(NUM_LAYERS + 1) + 1;
    localparam LVC_WIDTH = LLR_BITS * NUM_LAYERS;
    localparam EDGE_WIDTH = CN_INDEX_BITS * NUM_LAYERS;

    wire [9*NUM_LAYERS-1:0] mcv_t [0:NUM_PE-1];  // CN summaries per PE
    wire [NUM_PE-1:0] cv_comb;

    // ---------------------------------------------------------------
    // Graph configuration — USER MODIFIES THESE FOR NEW H MATRIX
    // ---------------------------------------------------------------
    reg [NUM_LAYERS-1:0] bypass [0:NUM_PE-1];
    reg [EDGE_WIDTH-1:0] edgelist [0:NUM_PE-1];
    reg [CN_INDEX_BITS-1:0] bypass_list [0:NUM_PE-1];

    // CN membership tables: for each CN, list the PE indices and their layers
    // cn_pe_table[cn][slot]    = PE index (8-bit, supports up to 256 PEs)
    // cn_layer_table[cn][slot] = layer index (4-bit)
    // cn_degree[cn]            = number of active PEs in this CN
    reg [7:0] cn_pe_table    [0:NUM_CN-1][0:MAX_CN_DEGREE-1];
    reg [3:0] cn_layer_table [0:NUM_CN-1][0:MAX_CN_DEGREE-1];
    reg [3:0] cn_degree      [0:NUM_CN-1];

    // Unpack the flat qv_flat input into per-PE wires
    wire [LLR_BITS-1:0] qv_list [0:NUM_PE-1];
    genvar qv_i;
    generate
        for (qv_i = 0; qv_i < NUM_PE; qv_i = qv_i + 1) begin : qv_unpack
            assign qv_list[qv_i] = qv_flat[LLR_BITS*qv_i +: LLR_BITS];
        end
    endgenerate

    // ---------------------------------------------------------------
    // Lvc wires: variable-to-check messages from each PE
    // ---------------------------------------------------------------
    wire [LVC_WIDTH-1:0] Lvc_out [0:NUM_PE-1];
    wire [LVC_WIDTH-1:0] Lvc_muxed [0:NUM_PE-1];
    
    // ---------------------------------------------------------------
    // Check node summary registers: 9 bits per CN {sign_xor, min1[3:0], min2[3:0]}
    // ---------------------------------------------------------------
    reg [8:0] cn_summary [0:NUM_CN-1];

    // ---------------------------------------------------------------
    // EDGE LIST CONFIGURATION — modify for your H matrix
    // ---------------------------------------------------------------
    // Format: edgelist[pe] has CN_INDEX_BITS bits per layer, MSB = highest layer
    // bypass_list[pe] = CN index that this PE bypasses, or all-1s (4'hF) for no bypass
    //
    // Example below is for the (3,4)-regular LDPC code:
    //   12 VNs, 9 CNs, 3 layers
    //   Layer 0: CN0={PE1,PE3,PE11}+PE6*  CN1={PE2,PE4,PE9}+PE7*  CN2={PE0,PE5,PE10}+PE8*
    //   Layer 1: CN3={PE5,PE6,PE9}+PE0*   CN4={PE3,PE7,PE10}+PE1* CN5={PE4,PE8,PE11}+PE2*
    //   Layer 2: CN6={PE1,PE3,PE8,PE10}   CN7={PE2,PE4,PE6,PE11}  CN8={PE0,PE5,PE7,PE9}
    initial begin
        // edgelist[pe] = {CN_for_layerN-1, ..., CN_for_layer1, CN_for_layer0}
        // Each nibble is a CN index. Used for bypass detection and mcv_t mapping.
        edgelist[0]  = 12'ha99;  // PE0:  L0→CN2, L1→CN3, L2→CN8
        edgelist[1]  = 12'hbaa;  // PE1:  L0→CN0, L1→CN4, L2→CN6
        edgelist[2]  = 12'h9bb;  // PE2:  L0→CN1, L1→CN5, L2→CN7
        edgelist[3]  = 12'h111;  // PE3:  L0→CN0, L1→CN4, L2→CN6
        edgelist[4]  = 12'h222;  // PE4:  L0→CN1, L1→CN5, L2→CN7
        edgelist[5]  = 12'h000;  // PE5:  L0→CN2, L1→CN3, L2→CN8
        edgelist[6]  = 12'h354;  // PE6:  L0→CN0, L1→CN3, L2→CN7
        edgelist[7]  = 12'h435;  // PE7:  L0→CN1, L1→CN4, L2→CN8
        edgelist[8]  = 12'h543;  // PE8:  L0→CN2, L1→CN5, L2→CN6
        edgelist[9]  = 12'h767;  // PE9:  L0→CN1, L1→CN3, L2→CN8
        edgelist[10] = 12'h878;  // PE10: L0→CN2, L1→CN4, L2→CN6
        edgelist[11] = 12'h686;  // PE11: L0→CN0, L1→CN5, L2→CN7

        bypass_list[0]  = 4'h9;
        bypass_list[1]  = 4'ha;
        bypass_list[2]  = 4'hb;
        bypass_list[3]  = 4'hF;
        bypass_list[4]  = 4'hF;
        bypass_list[5]  = 4'hF;
        bypass_list[6]  = 4'h3;
        bypass_list[7]  = 4'h4;
        bypass_list[8]  = 4'h5;
        bypass_list[9]  = 4'hF;
        bypass_list[10] = 4'hF;
        bypass_list[11] = 4'hF;

            // CN membership tables — inverse of edgelist
            // CN0 (layer 0): PEs 1, 3, 11 active (PE6 bypassed)
            cn_pe_table[0][0] = 8'd1;  cn_layer_table[0][0] = 4'd0;
        cn_pe_table[0][1] = 8'd3;  cn_layer_table[0][1] = 4'd0;
        cn_pe_table[0][2] = 8'd11; cn_layer_table[0][2] = 4'd0;
        cn_degree[0] = 4'd3;

        // CN1 (layer 0): PEs 2, 4, 9 active (PE7 bypassed)
        cn_pe_table[1][0] = 8'd2;  cn_layer_table[1][0] = 4'd0;
        cn_pe_table[1][1] = 8'd4;  cn_layer_table[1][1] = 4'd0;
        cn_pe_table[1][2] = 8'd9;  cn_layer_table[1][2] = 4'd0;
        cn_degree[1] = 4'd3;

        // CN2 (layer 0): PEs 0, 5, 10 active (PE8 bypassed)
        cn_pe_table[2][0] = 8'd0;  cn_layer_table[2][0] = 4'd0;
        cn_pe_table[2][1] = 8'd5;  cn_layer_table[2][1] = 4'd0;
        cn_pe_table[2][2] = 8'd10; cn_layer_table[2][2] = 4'd0;
        cn_degree[2] = 4'd3;

        // CN3 (layer 1): PEs 5, 6, 9 active (PE0 bypassed)
        cn_pe_table[3][0] = 8'd5;  cn_layer_table[3][0] = 4'd1;
        cn_pe_table[3][1] = 8'd6;  cn_layer_table[3][1] = 4'd1;
        cn_pe_table[3][2] = 8'd9;  cn_layer_table[3][2] = 4'd1;
        cn_degree[3] = 4'd3;

        // CN4 (layer 1): PEs 3, 7, 10 active (PE1 bypassed)
        cn_pe_table[4][0] = 8'd3;  cn_layer_table[4][0] = 4'd1;
        cn_pe_table[4][1] = 8'd7;  cn_layer_table[4][1] = 4'd1;
        cn_pe_table[4][2] = 8'd10; cn_layer_table[4][2] = 4'd1;
        cn_degree[4] = 4'd3;

        // CN5 (layer 1): PEs 4, 8, 11 active (PE2 bypassed)
        cn_pe_table[5][0] = 8'd4;  cn_layer_table[5][0] = 4'd1;
        cn_pe_table[5][1] = 8'd8;  cn_layer_table[5][1] = 4'd1;
        cn_pe_table[5][2] = 8'd11; cn_layer_table[5][2] = 4'd1;
        cn_degree[5] = 4'd3;

        // CN6 (layer 2): PEs 1, 3, 8, 10 — all active
        cn_pe_table[6][0] = 8'd1;  cn_layer_table[6][0] = 4'd2;
        cn_pe_table[6][1] = 8'd3;  cn_layer_table[6][1] = 4'd2;
        cn_pe_table[6][2] = 8'd8;  cn_layer_table[6][2] = 4'd2;
        cn_pe_table[6][3] = 8'd10; cn_layer_table[6][3] = 4'd2;
        cn_degree[6] = 4'd4;

        // CN7 (layer 2): PEs 2, 4, 6, 11 — all active
        cn_pe_table[7][0] = 8'd2;  cn_layer_table[7][0] = 4'd2;
        cn_pe_table[7][1] = 8'd4;  cn_layer_table[7][1] = 4'd2;
        cn_pe_table[7][2] = 8'd6;  cn_layer_table[7][2] = 4'd2;
        cn_pe_table[7][3] = 8'd11; cn_layer_table[7][3] = 4'd2;
        cn_degree[7] = 4'd4;

        // CN8 (layer 2): PEs 0, 5, 7, 9 — all active
        cn_pe_table[8][0] = 8'd0;  cn_layer_table[8][0] = 4'd2;
        cn_pe_table[8][1] = 8'd5;  cn_layer_table[8][1] = 4'd2;
        cn_pe_table[8][2] = 8'd7;  cn_layer_table[8][2] = 4'd2;
        cn_pe_table[8][3] = 8'd9;  cn_layer_table[8][3] = 4'd2;
        cn_degree[8] = 4'd4;
    end

    // ---------------------------------------------------------------
    // Bypass computation
    // ---------------------------------------------------------------
    integer a;
    always @(*) begin
        for (a = 0; a < NUM_PE; a = a + 1) begin
            bypass[a] = {NUM_LAYERS{1'b0}};
            if (bypass_list[a] != {CN_INDEX_BITS{1'b1}}) begin
                // This PE has a bypass — find which layer it's on
                bypass[a] = {NUM_LAYERS{1'b0}};
                begin : bypass_search
                    integer bl;
                    for (bl = 0; bl < NUM_LAYERS; bl = bl + 1) begin
                        if (bypass_list[a] == edgelist[a][CN_INDEX_BITS*bl +: CN_INDEX_BITS])
                            bypass[a][bl] = 1'b1;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // CENTRAL CHECK NODE COMPUTATION (combinational)
    //
    // For each CN, compute the min-sum summary from its member PEs:
    //   sign_xor = XOR of all connected VN signs
    //   min1     = minimum magnitude across all connected VNs
    //   min2     = second minimum magnitude
    // ---------------------------------------------------------------

    // Extract sign and magnitude from each PE's Lvc for each layer
    wire [3:0] lvc_mag  [0:NUM_PE-1][0:NUM_LAYERS-1];
    wire       lvc_sign [0:NUM_PE-1][0:NUM_LAYERS-1];

    genvar gi, gl;
    generate
        for (gi = 0; gi < NUM_PE; gi = gi + 1) begin : lvc_extract
            for (gl = 0; gl < NUM_LAYERS; gl = gl + 1) begin : lvc_layer
                assign lvc_sign[gi][gl] = Lvc_muxed[gi][LLR_BITS*gl + (LLR_BITS-1)];
                assign lvc_mag[gi][gl]  = Lvc_muxed[gi][LLR_BITS*gl +: (LLR_BITS-1)];
            end
        end
    endgenerate

    // CN computation: combinational min-sum for each check node
    reg [8:0] cn_summary_comb [0:NUM_CN-1];

    // Helper variables for CN accumulation
    reg        cn_sc;
    reg [3:0]  cn_min1, cn_min2;
    reg [3:0]  cn_lvc_mag_tmp;
    reg        cn_lvc_sign_tmp;

    integer cn_idx, slot_idx;
    reg [7:0] pe_idx;
    reg [3:0] layer_idx;

    always @(*) begin
        for (cn_idx = 0; cn_idx < NUM_CN; cn_idx = cn_idx + 1) begin
            // Initialize with first member
            pe_idx    = cn_pe_table[cn_idx][0];
            layer_idx = cn_layer_table[cn_idx][0];
            cn_sc     = lvc_sign[pe_idx][layer_idx];
            cn_min1   = lvc_mag[pe_idx][layer_idx];
            cn_min2   = 4'hF;

            // Accumulate remaining members
            for (slot_idx = 1; slot_idx < MAX_CN_DEGREE; slot_idx = slot_idx + 1) begin
                if (slot_idx < cn_degree[cn_idx]) begin
                    pe_idx    = cn_pe_table[cn_idx][slot_idx];
                    layer_idx = cn_layer_table[cn_idx][slot_idx];
                    cn_lvc_sign_tmp = lvc_sign[pe_idx][layer_idx];
                    cn_lvc_mag_tmp  = lvc_mag[pe_idx][layer_idx];
                    cn_sc = cn_sc ^ cn_lvc_sign_tmp;
                    if (cn_lvc_mag_tmp < cn_min1) begin
                        cn_min2 = cn_min1;
                        cn_min1 = cn_lvc_mag_tmp;
                    end else if (cn_lvc_mag_tmp < cn_min2) begin
                        cn_min2 = cn_lvc_mag_tmp;
                    end
                end
            end
            cn_summary_comb[cn_idx] = {cn_sc, cn_min1, cn_min2};
        end
    end

    // ---------------------------------------------------------------
    // Register CN summaries on cn_sel edge
    // ---------------------------------------------------------------
    integer s;
    initial begin
        for (s = 0; s < NUM_CN; s = s + 1) cn_summary[s] = 9'h0FF;
    end

    always @(posedge clk) begin
        if (cn_sel) begin
            for (s = 0; s < NUM_CN; s = s + 1)
                cn_summary[s] <= cn_summary_comb[s];
        end
    end

    // ---------------------------------------------------------------
    // Map CN summaries back to per-PE mcv_t format
    //
    // For each PE, mcv_t[pe] = {cn_summary for layer NUM_LAYERS-1, ..., cn_summary for layer 0}
    // The CN index for PE p at layer L = edgelist[p][CN_INDEX_BITS*L +: CN_INDEX_BITS]
    // ---------------------------------------------------------------

    // Combinational mcv_t mapping (needs to index cn_summary with a variable)
    reg [9*NUM_LAYERS-1:0] mcv_t_reg [0:NUM_PE-1];
    integer mp_i, ml_i;
    reg [CN_INDEX_BITS-1:0] cn_sel_idx;

    always @(*) begin
        for (mp_i = 0; mp_i < NUM_PE; mp_i = mp_i + 1) begin
            for (ml_i = 0; ml_i < NUM_LAYERS; ml_i = ml_i + 1) begin
                cn_sel_idx = edgelist[mp_i][CN_INDEX_BITS*ml_i +: CN_INDEX_BITS];
                mcv_t_reg[mp_i][9*ml_i +: 9] = cn_summary[cn_sel_idx];
            end
        end
    end

    // Drive the wire version from the reg
    genvar mcv_gi;
    generate
        for (mcv_gi = 0; mcv_gi < NUM_PE; mcv_gi = mcv_gi + 1) begin : mcv_drive
            assign mcv_t[mcv_gi] = mcv_t_reg[mcv_gi];
        end
    endgenerate

    // ---------------------------------------------------------------
    // Pipeline: simple 2-phase (cn_sel → vn_sel)
    // ---------------------------------------------------------------
    reg vn_sel_d;
    initial begin
        vn_sel_d = 1'b0;
        cv_list  = {NUM_PE{1'b0}};
    end

    always @(posedge clk) begin
        vn_sel_d <= vn_sel;
    end

    always @(posedge clk) begin
        if (vn_sel_d)
            cv_list <= cv_comb;
    end

    // ---------------------------------------------------------------
    // PE instantiation: all NUM_PE PEs run simultaneously
    // ---------------------------------------------------------------
    genvar j;
    generate
    for (j = 0; j < NUM_PE; j = j + 1) begin : pe_inst
        PE #(
            .NUM_LAYERS(NUM_LAYERS),
            .LLR_BITS(LLR_BITS)
        ) pe(
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