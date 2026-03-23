module gen #(
    parameter SIZE = 3,
    parameter M_B  = 3,
    parameter N_B  = 4
)(
    input clk,
    input rst,
    input iter_flag,
    input cn_reset,
    input cn_sel,
    input vn_sel,
    input [N_B*SIZE*5-1:0] qv_flat,
    output reg [N_B*SIZE-1:0] cv_list
);

    localparam N      = N_B * SIZE;
    localparam M      = M_B * SIZE;
    localparam MAX_DV = M_B;

    // =================================================================
    // SHIFT MATRIX FUNCTION
    // To change the H matrix, only update this function.
    // =================================================================
    function signed [7:0] get_shift;
        input integer idx;
        begin
            case (idx)
                0: get_shift = 1;
                1: get_shift = 0;
                2: get_shift = -8'sd1;
                3: get_shift = 2;
                4: get_shift = -8'sd1;
                5: get_shift = 2;
                6: get_shift = 0;
                7: get_shift = 0;
                8: get_shift = 1;
                9: get_shift = 0;
                10: get_shift = 2;
                11: get_shift = 1;
                default: get_shift = -8'sd1;
            endcase
        end
    endfunction

    // =================================================================
    // INTERNAL SIGNALS
    // =================================================================
    reg [9*MAX_DV-1:0] mcv_t [0:N-1];
    wire [N-1:0] cv_comb;

    wire [4:0] qv_list [0:N-1];
    genvar qv_i;
    generate
        for (qv_i = 0; qv_i < N; qv_i = qv_i + 1) begin : qv_unpack
            assign qv_list[qv_i] = qv_flat[5*qv_i +: 5];
        end
    endgenerate

    wire [5*MAX_DV-1:0] Lvc_out   [0:N-1];
    wire [5*MAX_DV-1:0] Lvc_muxed [0:N-1];

    reg [8:0] cn_summary [0:M-1];

    // =================================================================
    // BYPASS COMPUTATION (from shift matrix)
    // =================================================================
    wire [MAX_DV-1:0] bypass_wire [0:N-1];
    genvar bp_i, bp_l;
    generate
        for (bp_i = 0; bp_i < N; bp_i = bp_i + 1) begin : bp_gen
            for (bp_l = 0; bp_l < MAX_DV; bp_l = bp_l + 1) begin : bp_lay
                assign bypass_wire[bp_i][bp_l] =
                    (get_shift(bp_l * N_B + bp_i / SIZE) < 0) ? 1'b1 : 1'b0;
            end
        end
    endgenerate

    // =================================================================
    // LVC EXTRACTION: flatten sign/magnitude
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
    // CN COMPUTATION (on-the-fly from shift matrix)
    // =================================================================
    reg [8:0] cn_summary_comb [0:M-1];
    reg        cn_sc;
    reg [3:0]  cn_min1, cn_min2;
    reg [3:0]  cn_lvc_mag_tmp;
    reg        cn_lvc_sign_tmp;

    integer c, j_mc, pe_idx, flat_idx;
    integer i_mr, c_off;
    reg signed [7:0] shift_val;

    always @(*) begin
        for (c = 0; c < M; c = c + 1) begin
            cn_sc   = 1'b0;
            cn_min1 = 4'hF;
            cn_min2 = 4'hF;
            i_mr  = c / SIZE;
            c_off = c % SIZE;
            for (j_mc = 0; j_mc < N_B; j_mc = j_mc + 1) begin
                shift_val = get_shift(i_mr * N_B + j_mc);
                if (shift_val >= 0) begin
                    pe_idx   = j_mc * SIZE + ((c_off + shift_val) % SIZE);
                    flat_idx = pe_idx * MAX_DV + i_mr;
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
    // REGISTER CN SUMMARIES (synchronous reset)
    // =================================================================
    integer s;
    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < M; s = s + 1)
                cn_summary[s] <= 9'h0FF;
        end else if (cn_sel) begin
            for (s = 0; s < M; s = s + 1)
                cn_summary[s] <= cn_summary_comb[s];
        end
    end

    // =================================================================
    // MCV_T ROUTING (on-the-fly from shift matrix)
    // =================================================================
    integer p, l, mc, co, cn_idx;
    reg signed [7:0] shift_mcv;

    always @(*) begin
        for (p = 0; p < N; p = p + 1) begin
            mc = p / SIZE;
            co = p % SIZE;
            for (l = 0; l < MAX_DV; l = l + 1) begin
                shift_mcv = get_shift(l * N_B + mc);
                if (shift_mcv < 0)
                    mcv_t[p][9*l +: 9] = 9'h1FF;
                else begin
                    cn_idx = l * SIZE + ((co - shift_mcv + SIZE) % SIZE);
                    mcv_t[p][9*l +: 9] = cn_summary[cn_idx];
                end
            end
        end
    end

    // =================================================================
    // PIPELINE (synchronous reset)
    // =================================================================
    reg vn_sel_d;

    always @(posedge clk) begin
        if (rst) begin
            vn_sel_d <= 1'b0;
            cv_list  <= {N{1'b0}};
        end else begin
            vn_sel_d <= vn_sel;
            if (vn_sel_d)
                cv_list <= cv_comb;
        end
    end

    // =================================================================
    // PE INSTANTIATION
    // =================================================================
    genvar gi;
    generate
    for (gi = 0; gi < N; gi = gi + 1) begin : pe_inst
        PE #(.MAX_DV(MAX_DV)) pe(
            .clk(clk),
            .rst(rst),
            .iter_flag(iter_flag),
            .vn_sel(vn_sel),
            .bypass(bypass_wire[gi]),
            .mcv_tprev(mcv_t[gi]),
            .Qv(qv_list[gi]),
            .Cv(cv_comb[gi]),
            .Lvc_out(Lvc_out[gi]),
            .Lvc_muxed_out(Lvc_muxed[gi])
        );
    end
    endgenerate

endmodule
