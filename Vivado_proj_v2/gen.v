module gen(

input clk,
input iter_flag,
input cn_reset,
input cn_sel,
input vn_sel,
// -------------------------------------------------------------------
// CHANGED LINE 1: cv_list is now a registered output (reg, not wire).
// Previously it was a wire driven directly by 12 combinational Cv
// outputs from the PE instances.  Because the 4 pipeline groups use
// vn_sel_1..4 (staggered 1 cycle apart), each group's Cv updated on a
// DIFFERENT clock cycle — producing 4 separate cv_list transitions per
// iteration (and XXX states between them).  Making it a reg lets us
// capture all 12 bits atomically at a single clock edge.
// -------------------------------------------------------------------
output reg [11:0] cv_list
    );

    reg [3:0] addr;
    reg [2:0] bypass [0:11];
    wire flag_edgelist;
    wire [3:0] addr_edgelist; 
    
    reg [26:0] mcv_tprev[0:11];
    reg generate_flag;
    wire [26:0] mcv_t[0:11];

    // -------------------------------------------------------------------
    // CHANGED LINE 2: Introduce cv_comb[11:0] as the internal wire that
    // collects the raw combinational Cv outputs from all 12 PE instances.
    // The PE generate blocks below are reconnected to cv_comb instead of
    // cv_list.  cv_list is now only written from a clocked always block.
    // -------------------------------------------------------------------
    wire [11:0] cv_comb;

    reg [11:0] edgelist [0:11];
    reg [3:0]  bypass_list [0:11];
    reg [4:0]  qv_list [0:11];

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
    
        qv_list[0]  = 5'h07;
        qv_list[1]  = 5'h1A;
        qv_list[2]  = 5'h02;
        qv_list[3]  = 5'h1F;
        qv_list[4]  = 5'h0C;
        qv_list[5]  = 5'h14;
        qv_list[6]  = 5'h00;
        qv_list[7]  = 5'h0E;
        qv_list[8]  = 5'h11;
        qv_list[9]  = 5'h05;
        qv_list[10] = 5'h18;
        qv_list[11] = 5'h09;
    end
    
    
    integer a;

    always @(*) begin
        for (a = 0; a < 12; a = a + 1) begin
            if (bypass_list[a] == edgelist[a][11:8]) bypass[a] = 3'b100;
            else if (bypass_list[a] == edgelist[a][7:4]) bypass[a] = 3'b010;
            else if (bypass_list[a] == edgelist[a][3:0]) bypass[a] = 3'b001;
            else bypass[a] = 3'b000;

            mcv_tprev[a] = {
                mcv_t[ edgelist[a][11:8] ][26:18],
                mcv_t[ edgelist[a][7:4]  ][17:9],
                mcv_t[ edgelist[a][3:0]  ][8:0]
            };
        end
    end    


    // ------------------------------------------------------------------
    // FIX 3: Initialise pipeline registers to zero.
    //
    // ORIGINAL: cn_sel_N, vn_sel_N, cn_reset_N all start as X.
    //   On the first posedge they capture X from their inputs (also X
    //   before the testbench #1 initialisation).  These X values
    //   propagate into cn_sel and vn_sel ports of each PE group and
    //   trigger X on w_ena, CN_Update enable, and VN_Update enable
    //   before any valid stimulus arrives.
    //
    // FIX: initialise all pipeline stage regs to 0 at t=0.
    // ------------------------------------------------------------------
    reg cn_sel_1, cn_sel_2, cn_sel_3, cn_sel_4;
    reg vn_sel_1, vn_sel_2, vn_sel_3, vn_sel_4;
    // -------------------------------------------------------------------
    // CHANGED LINE 4: Declare vn_sel_5 — a 5th pipeline stage of vn_sel.
    //
    // WHY 5 STAGES AND NOT 4:
    //   vn_sel_4 fires exactly when group j4 (PE 9-11) is ENTERING its
    //   VN phase — at that moment the mcv latch in VN_Update is still
    //   TRANSPARENT (vn_ena=1), so Cv for PE 9-11 is still in flux.
    //   Sampling cv_comb at vn_sel_4=1 would capture an unstable value
    //   for bits [11:9].
    //
    //   vn_sel_5 fires ONE cycle later.  By then:
    //     • Groups j1 (PE 0-2) : latch closed 4 cycles ago → Cv stable
    //     • Groups j2 (PE 3-5) : latch closed 3 cycles ago → Cv stable
    //     • Groups j3 (PE 6-8) : latch closed 2 cycles ago → Cv stable
    //     • Groups j4 (PE 9-11): latch closed 1 cycle  ago → Cv stable
    //   ALL 12 bits of cv_comb are now stable → safe to register them.
    // -------------------------------------------------------------------
    reg vn_sel_5;
    reg cn_reset_1, cn_reset_2, cn_reset_3, cn_reset_4;

    initial begin
        cn_sel_1 = 1'b0; cn_sel_2 = 1'b0; cn_sel_3 = 1'b0; cn_sel_4 = 1'b0;
        vn_sel_1 = 1'b0; vn_sel_2 = 1'b0; vn_sel_3 = 1'b0; vn_sel_4 = 1'b0;
        cn_reset_1 = 1'b0; cn_reset_2 = 1'b0; cn_reset_3 = 1'b0; cn_reset_4 = 1'b0;
        // -------------------------------------------------------------------
        // CHANGED LINE 3: Initialise vn_sel_5 and cv_list to zero.
        // Without this, cv_list (now a reg) starts as X and stays X until
        // the first vn_sel_5 capture pulse, which is 5 cycles into the
        // first iteration — producing X on cv_list for those early cycles.
        // -------------------------------------------------------------------
        vn_sel_5   = 1'b0;
        cv_list    = 12'b0;
    end

    always @(posedge clk)
    begin
        cn_sel_1 <= cn_sel;
        cn_sel_2 <= cn_sel_1;
        cn_sel_3 <= cn_sel_2;
        cn_sel_4 <= cn_sel_3;
    end
    
    always @(posedge clk)
    begin
        vn_sel_1 <= vn_sel;
        vn_sel_2 <= vn_sel_1;
        vn_sel_3 <= vn_sel_2;
        vn_sel_4 <= vn_sel_3;
        // -------------------------------------------------------------------
        // CHANGED LINE 5: Extend the vn_sel pipeline to a 5th stage.
        // This is the enable used to capture cv_list (see below).
        // -------------------------------------------------------------------
        vn_sel_5 <= vn_sel_4;
    end

    // -------------------------------------------------------------------
    // CHANGED LINE 6: Register cv_list, updated ONLY when vn_sel_5=1.
    //
    // This is the core fix.  Previously cv_list was a wire connected
    // directly to 12 combinational Cv outputs.  Those outputs update on
    // 4 different clock cycles (one per pipeline group), causing:
    //   • 4 separate transitions on cv_list per iteration
    //   • Bits from different groups settling at different times → XXX
    //
    // With this register:
    //   • cv_list only changes at the single posedge when vn_sel_5=1
    //   • At that moment ALL groups' mcv latches are closed and stable
    //   • cv_list then holds that value for a full 8-cycle iteration
    //   • Exactly ONE clean update every 8 cycles (once per iteration)
    //   • The 4-cycle window from vn_sel_1 through vn_sel_4 is entirely
    //     absorbed inside the pipeline — cv_list never sees the glitches
    // -------------------------------------------------------------------
    always @(posedge clk)
    begin
        if (vn_sel_5)
            cv_list <= cv_comb;
    end

    // ------------------------------------------------------------------
    // FIX 4: Pipeline cn_reset to match each group's cn_sel delay.
    //
    // ORIGINAL: cn_reset was routed with 0-cycle delay to all PE groups
    //   while cn_sel_N has an N-cycle pipeline delay. CN_Update only
    //   initialises its latches when BOTH cn_ena=1 AND reset=1 are true
    //   at the same moment. For groups j2/j3/j4, cn_reset falls back to
    //   0 long before cn_sel_2/3/4 rises → the coincidence never occurs
    //   → min1c_t and sc_t latches stay X → mcv_t = XXf on those groups.
    //
    // FIX: Register cn_reset through the same pipeline depth as cn_sel
    //   so the reset pulse and enable pulse reach each group together.
    // ------------------------------------------------------------------
    always @(posedge clk)
    begin
        cn_reset_1 <= cn_reset;
        cn_reset_2 <= cn_reset_1;
        cn_reset_3 <= cn_reset_2;
        cn_reset_4 <= cn_reset_3;
    end


    genvar j1;
    generate
    for(j1 = 0; j1 < 3; j1 = j1 + 1)
    begin
        // CHANGED LINE 7: PE output connected to cv_comb[j1], not cv_list[j1]
        PE pe(clk, iter_flag, cn_reset_1, cn_sel_1, vn_sel_1,
              bypass[j1], mcv_tprev[j1], qv_list[j1], mcv_t[j1], cv_comb[j1]);
    end
    endgenerate
    
    genvar j2;
    generate
    for(j2 = 3; j2 < 6; j2 = j2 + 1)
    begin
        // CHANGED LINE 8: PE output connected to cv_comb[j2], not cv_list[j2]
        PE pe(clk, iter_flag, cn_reset_2, cn_sel_2, vn_sel_2,
              bypass[j2], mcv_tprev[j2], qv_list[j2], mcv_t[j2], cv_comb[j2]);
    end
    endgenerate
    
    genvar j3;
    generate
    for(j3 = 6; j3 < 9; j3 = j3 + 1)
    begin
        // CHANGED LINE 9: PE output connected to cv_comb[j3], not cv_list[j3]
        PE pe(clk, iter_flag, cn_reset_3, cn_sel_3, vn_sel_3,
              bypass[j3], mcv_tprev[j3], qv_list[j3], mcv_t[j3], cv_comb[j3]);
    end
    endgenerate
    
    genvar j4;
    generate
    for(j4 = 9; j4 < 12; j4 = j4 + 1)
    begin
        // CHANGED LINE 10: PE output connected to cv_comb[j4], not cv_list[j4]
        PE pe(clk, iter_flag, cn_reset_4, cn_sel_4, vn_sel_4,
              bypass[j4], mcv_tprev[j4], qv_list[j4], mcv_t[j4], cv_comb[j4]);
    end
    endgenerate
    
endmodule
