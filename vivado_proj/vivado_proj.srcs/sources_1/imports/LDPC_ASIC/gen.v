module gen #(
    parameter N      = 12,   // Number of variable nodes (PEs)
    parameter M      = 9,    // Number of check nodes
    parameter MAX_DC = 4,    // Maximum check node degree
    parameter MAX_DV = 3     // Maximum variable node degree (layers per PE)
)(
    input clk,
    input iter_flag,
    input cn_reset,
    input cn_sel,
    input vn_sel,
    input [N*5-1:0] qv_flat,
    output reg [N-1:0] cv_list
);

    // =================================================================
    // H-MATRIX LOOKUP TABLES
    // To change the H matrix, only update the three tables below.
    // =================================================================

    // Table 1: Bypass per PE
    //   bit[layer]=1 means that layer is bypassed
    reg [MAX_DV-1:0] bypass_tbl [0:N-1];

    // Table 2: CN member list
    //   cn_pe_tbl[c*MAX_DC+d] = PE index of d-th member of CN c
    //   cn_ly_tbl[c*MAX_DC+d] = layer index of that member
    //   Sentinel: PE index = N (unused slot when degree < MAX_DC)
    reg [3:0] cn_pe_tbl [0:M*MAX_DC-1];
    reg [1:0] cn_ly_tbl [0:M*MAX_DC-1];

    // Table 3: mcv_t routing (PE layer -> CN summary)
    //   mcv_cn_tbl[p*MAX_DV+l] = CN index whose summary feeds PE p, layer l
    //   Sentinel: CN index = M (bypassed layer)
    reg [3:0] mcv_cn_tbl [0:N*MAX_DV-1];

    // -----------------------------------------------------------------
    // Default tables for the 9x12 quasi-cyclic H matrix:
    //   CN0:{1,3,11}    CN1:{2,4,9}      CN2:{0,5,10}
    //   CN3:{5,6,9}     CN4:{3,7,10}     CN5:{4,8,11}
    //   CN6:{1,3,8,10}  CN7:{2,4,6,11}   CN8:{0,5,7,9}
    // Layer grouping: L0=CN0-2, L1=CN3-5, L2=CN6-8
    // -----------------------------------------------------------------
    initial begin
        // ----- Bypass table -----
        bypass_tbl[0]  = 3'b010; bypass_tbl[1]  = 3'b010; bypass_tbl[2]  = 3'b010;
        bypass_tbl[3]  = 3'b000; bypass_tbl[4]  = 3'b000; bypass_tbl[5]  = 3'b000;
        bypass_tbl[6]  = 3'b001; bypass_tbl[7]  = 3'b001; bypass_tbl[8]  = 3'b001;
        bypass_tbl[9]  = 3'b000; bypass_tbl[10] = 3'b000; bypass_tbl[11] = 3'b000;

        // ----- CN member table (cn_pe_tbl / cn_ly_tbl) -----
        // CN0: PE1(L0), PE3(L0), PE11(L0)
        cn_pe_tbl[0]=1;  cn_ly_tbl[0]=0;  cn_pe_tbl[1]=3;   cn_ly_tbl[1]=0;
        cn_pe_tbl[2]=11; cn_ly_tbl[2]=0;  cn_pe_tbl[3]=N;   cn_ly_tbl[3]=0;
        // CN1: PE2(L0), PE4(L0), PE9(L0)
        cn_pe_tbl[4]=2;  cn_ly_tbl[4]=0;  cn_pe_tbl[5]=4;   cn_ly_tbl[5]=0;
        cn_pe_tbl[6]=9;  cn_ly_tbl[6]=0;  cn_pe_tbl[7]=N;   cn_ly_tbl[7]=0;
        // CN2: PE0(L0), PE5(L0), PE10(L0)
        cn_pe_tbl[8]=0;  cn_ly_tbl[8]=0;  cn_pe_tbl[9]=5;   cn_ly_tbl[9]=0;
        cn_pe_tbl[10]=10; cn_ly_tbl[10]=0; cn_pe_tbl[11]=N;  cn_ly_tbl[11]=0;
        // CN3: PE5(L1), PE6(L1), PE9(L1)
        cn_pe_tbl[12]=5;  cn_ly_tbl[12]=1; cn_pe_tbl[13]=6;  cn_ly_tbl[13]=1;
        cn_pe_tbl[14]=9;  cn_ly_tbl[14]=1; cn_pe_tbl[15]=N;  cn_ly_tbl[15]=0;
        // CN4: PE3(L1), PE7(L1), PE10(L1)
        cn_pe_tbl[16]=3;  cn_ly_tbl[16]=1; cn_pe_tbl[17]=7;  cn_ly_tbl[17]=1;
        cn_pe_tbl[18]=10; cn_ly_tbl[18]=1; cn_pe_tbl[19]=N;  cn_ly_tbl[19]=0;
        // CN5: PE4(L1), PE8(L1), PE11(L1)
        cn_pe_tbl[20]=4;  cn_ly_tbl[20]=1; cn_pe_tbl[21]=8;  cn_ly_tbl[21]=1;
        cn_pe_tbl[22]=11; cn_ly_tbl[22]=1; cn_pe_tbl[23]=N;  cn_ly_tbl[23]=0;
        // CN6: PE1(L2), PE3(L2), PE8(L2), PE10(L2)
        cn_pe_tbl[24]=1;  cn_ly_tbl[24]=2; cn_pe_tbl[25]=3;  cn_ly_tbl[25]=2;
        cn_pe_tbl[26]=8;  cn_ly_tbl[26]=2; cn_pe_tbl[27]=10; cn_ly_tbl[27]=2;
        // CN7: PE2(L2), PE4(L2), PE6(L2), PE11(L2)
        cn_pe_tbl[28]=2;  cn_ly_tbl[28]=2; cn_pe_tbl[29]=4;  cn_ly_tbl[29]=2;
        cn_pe_tbl[30]=6;  cn_ly_tbl[30]=2; cn_pe_tbl[31]=11; cn_ly_tbl[31]=2;
        // CN8: PE0(L2), PE5(L2), PE7(L2), PE9(L2)
        cn_pe_tbl[32]=0;  cn_ly_tbl[32]=2; cn_pe_tbl[33]=5;  cn_ly_tbl[33]=2;
        cn_pe_tbl[34]=7;  cn_ly_tbl[34]=2; cn_pe_tbl[35]=9;  cn_ly_tbl[35]=2;

        // ----- MCV routing table -----
        // PE0:  L0=CN2,   L1=bypass, L2=CN8
        mcv_cn_tbl[0]=2;   mcv_cn_tbl[1]=M;   mcv_cn_tbl[2]=8;
        // PE1:  L0=CN0,   L1=bypass, L2=CN6
        mcv_cn_tbl[3]=0;   mcv_cn_tbl[4]=M;   mcv_cn_tbl[5]=6;
        // PE2:  L0=CN1,   L1=bypass, L2=CN7
        mcv_cn_tbl[6]=1;   mcv_cn_tbl[7]=M;   mcv_cn_tbl[8]=7;
        // PE3:  L0=CN0,   L1=CN4,    L2=CN6
        mcv_cn_tbl[9]=0;   mcv_cn_tbl[10]=4;  mcv_cn_tbl[11]=6;
        // PE4:  L0=CN1,   L1=CN5,    L2=CN7
        mcv_cn_tbl[12]=1;  mcv_cn_tbl[13]=5;  mcv_cn_tbl[14]=7;
        // PE5:  L0=CN2,   L1=CN3,    L2=CN8
        mcv_cn_tbl[15]=2;  mcv_cn_tbl[16]=3;  mcv_cn_tbl[17]=8;
        // PE6:  L0=bypass, L1=CN3,   L2=CN7
        mcv_cn_tbl[18]=M;  mcv_cn_tbl[19]=3;  mcv_cn_tbl[20]=7;
        // PE7:  L0=bypass, L1=CN4,   L2=CN8
        mcv_cn_tbl[21]=M;  mcv_cn_tbl[22]=4;  mcv_cn_tbl[23]=8;
        // PE8:  L0=bypass, L1=CN5,   L2=CN6
        mcv_cn_tbl[24]=M;  mcv_cn_tbl[25]=5;  mcv_cn_tbl[26]=6;
        // PE9:  L0=CN1,   L1=CN3,    L2=CN8
        mcv_cn_tbl[27]=1;  mcv_cn_tbl[28]=3;  mcv_cn_tbl[29]=8;
        // PE10: L0=CN2,   L1=CN4,    L2=CN6
        mcv_cn_tbl[30]=2;  mcv_cn_tbl[31]=4;  mcv_cn_tbl[32]=6;
        // PE11: L0=CN0,   L1=CN5,    L2=CN7
        mcv_cn_tbl[33]=0;  mcv_cn_tbl[34]=5;  mcv_cn_tbl[35]=7;
    end

    // =================================================================
    // INTERNAL SIGNALS
    // =================================================================
    reg [9*MAX_DV-1:0] mcv_t [0:N-1];
    wire [N-1:0] cv_comb;

    // Unpack qv_flat into per-PE wires
    wire [4:0] qv_list [0:N-1];
    genvar qv_i;
    generate
        for (qv_i = 0; qv_i < N; qv_i = qv_i + 1) begin : qv_unpack
            assign qv_list[qv_i] = qv_flat[5*qv_i +: 5];
        end
    endgenerate

    // Lvc wires from each PE
    wire [5*MAX_DV-1:0] Lvc_out   [0:N-1];
    wire [5*MAX_DV-1:0] Lvc_muxed [0:N-1];

    // CN summary registers
    reg [8:0] cn_summary [0:M-1];

    // =================================================================
    // LVC EXTRACTION: flatten sign/magnitude for CN computation
    // =================================================================
    wire       lvc_sign_flat [0:N*MAX_DV-1];
    wire [3:0] lvc_mag_flat  [0:N*MAX_DV-1];

    genvar ei, el;
    generate
        for (ei = 0; ei < N; ei = ei + 1) begin : lvc_ext
            for (el = 0; el < MAX_DV; el = el + 1) begin : lvc_lay
                assign lvc_sign_flat[ei*MAX_DV+el] = Lvc_muxed[ei][5*el + 4];
                assign lvc_mag_flat[ei*MAX_DV+el]  = Lvc_muxed[ei][5*el +: 4];
            end
        end
    endgenerate

    // =================================================================
    // CN COMPUTATION (combinational min-sum via for-loops)
    // =================================================================
    reg [8:0] cn_summary_comb [0:M-1];
    reg        cn_sc;
    reg [3:0]  cn_min1, cn_min2;
    reg [3:0]  cn_lvc_mag_tmp;
    reg        cn_lvc_sign_tmp;

    integer c, d, flat_idx;
    always @(*) begin
        for (c = 0; c < M; c = c + 1) begin
            cn_sc   = 1'b0;
            cn_min1 = 4'hF;
            cn_min2 = 4'hF;
            for (d = 0; d < MAX_DC; d = d + 1) begin
                if (cn_pe_tbl[c*MAX_DC+d] < N) begin
                    flat_idx = cn_pe_tbl[c*MAX_DC+d] * MAX_DV
                             + cn_ly_tbl[c*MAX_DC+d];
                    cn_lvc_sign_tmp = lvc_sign_flat[flat_idx];
                    cn_lvc_mag_tmp  = lvc_mag_flat[flat_idx];
                    cn_sc = cn_sc ^ cn_lvc_sign_tmp;
                    if (cn_lvc_mag_tmp < cn_min1) begin
                        cn_min2 = cn_min1;
                        cn_min1 = cn_lvc_mag_tmp;
                    end else if (cn_lvc_mag_tmp < cn_min2) begin
                        cn_min2 = cn_lvc_mag_tmp;
                    end
                end
            end
            cn_summary_comb[c] = {cn_sc, cn_min1, cn_min2};
        end
    end

    // =================================================================
    // REGISTER CN SUMMARIES
    // =================================================================
    integer s;
    initial begin
        for (s = 0; s < M; s = s + 1) cn_summary[s] = 9'h0FF;
    end

    always @(posedge clk) begin
        if (cn_sel) begin
            for (s = 0; s < M; s = s + 1)
                cn_summary[s] <= cn_summary_comb[s];
        end
    end

    // =================================================================
    // MCV_T ROUTING: map CN summaries back to PE layers
    // =================================================================
    integer p, l;
    always @(*) begin
        for (p = 0; p < N; p = p + 1) begin
            for (l = 0; l < MAX_DV; l = l + 1) begin
                if (mcv_cn_tbl[p*MAX_DV+l] >= M)
                    mcv_t[p][9*l +: 9] = 9'h1FF;
                else
                    mcv_t[p][9*l +: 9] = cn_summary[mcv_cn_tbl[p*MAX_DV+l]];
            end
        end
    end

    // =================================================================
    // PIPELINE: simple 2-phase (cn_sel -> vn_sel)
    // =================================================================
    reg vn_sel_d;
    initial begin
        vn_sel_d = 1'b0;
        cv_list  = {N{1'b0}};
    end

    always @(posedge clk) begin
        vn_sel_d <= vn_sel;
    end

    always @(posedge clk) begin
        if (vn_sel_d)
            cv_list <= cv_comb;
    end

    // =================================================================
    // PE INSTANTIATION: all N PEs via generate
    // =================================================================
    genvar j;
    generate
    for (j = 0; j < N; j = j + 1) begin : pe_inst
        PE pe(
            .clk(clk),
            .iter_flag(iter_flag),
            .vn_sel(vn_sel),
            .bypass(bypass_tbl[j]),
            .mcv_tprev(mcv_t[j]),
            .Qv(qv_list[j]),
            .Cv(cv_comb[j]),
            .Lvc_out(Lvc_out[j]),
            .Lvc_muxed_out(Lvc_muxed[j])
        );
    end
    endgenerate

endmodule
