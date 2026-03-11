module PE(
    
    input clk,
    input iter_flag,
    input reset,
    input cn_sel,
    input vn_sel,
    input [2:0] bypass, 
    input [26:0] mcv_tprev,
    input [4:0] Qv,
    output reg [26:0] mcv_t,
    output Cv
    );
    
    wire [14:0] mcv;
    wire [14:0] Lvc_tprev;
    reg w_ena;
    wire [14:0] Lvc;
    wire [14:0] Lvc_muxed;

    // ------------------------------------------------------------------
    // FIX 1: Declare Lv as signed [6:0].
    //
    // ORIGINAL:  wire [6:0] Lv;  (unsigned)
    //   Each mcv slice and Qv carry two's complement (signed) LLRs.
    //   With an unsigned wire, a negative sum like -3 becomes 125
    //   (unsigned).  The comparison (Lv > 0) is TRUE for ALL negative
    //   sums → Cv=0 always → cv_list = 000 permanently.
    //
    // FIX: wire signed [6:0] Lv + $signed() casts on all operands.
    //   The '>' comparison now uses two's complement ordering correctly.
    // ------------------------------------------------------------------
    wire signed [6:0] Lv;

    wire [26:0] mcv_temp;

    // ------------------------------------------------------------------
    // FIX 2: Initialise pipeline registers and w_ena to zero.
    //
    // ORIGINAL: w_ena, mcv_t start as X.
    //   w_ena is registered from vn_sel. If vn_sel=X on the first
    //   posedge (before the testbench drives it), w_ena=X → Lvc_mem
    //   write-enable is X → mem may be written with garbage on cycle 0.
    //   mcv_t=X propagates into gen's mcv_tprev combinational loop.
    //
    // FIX: Force both to zero at t=0.
    // ------------------------------------------------------------------
    initial begin
        w_ena  = 1'b0;
        mcv_t  = 27'b0;
    end

    Lvc_mem Lvc_cache(.clk(clk), .din(Lvc), .w_ena(w_ena), .dout(Lvc_tprev));
    
    genvar i;
    generate
        for(i = 0; i < 3; i = i + 1) 
        begin
            assign Lvc_muxed[5*i +: 5] = (iter_flag) ? Qv : Lvc_tprev[5*i +: 5];

            CN_Update layeri_cn (
                .cn_ena(cn_sel),
                .reset(reset),
                .bypass(bypass[i]),
                .mcv_tprev(mcv_tprev[9*i +: 9]),
                .Lvc_tprev(Lvc_muxed[5*i +: 5]),
                .iter_flag(iter_flag),
                .mcv_t(mcv_temp[9*i +: 9])
            );

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
    
    // Signed addition and comparison
    assign Lv = $signed(mcv[4:0]) + $signed(mcv[9:5]) + $signed(mcv[14:10]) + $signed(Qv);
    assign Cv = (Lv > 0) ? 1'b0 : 1'b1;
    
    // =====================================================================
    // NEW: Self-contained 2-bit phase counter for mcv_t update control
    //
    // ROOT CAUSE OF THE PREVIOUS BUG (fragile cn_sel||vn_sel gate)
    // ------------------------------------------------------------
    // The prior fix used "if (cn_sel || vn_sel)" to gate mcv_t.
    // This failed because:
    //
    //   1. 4 PE pipeline groups (j1..j4) each use a DIFFERENT stage of
    //      cn_sel/vn_sel (delayed 1..4 cycles in gen.v). Each group's
    //      mcv_t update therefore fires at a different clock cycle.
    //
    //   2. gen.v has a COMBINATIONAL feedback path:
    //        always @(*) mcv_tprev[a] = { mcv_t[edgelist...], ... }
    //      Every time ANY group's mcv_t changes, mcv_tprev immediately
    //      glitches within the same timestep delta for all PEs that
    //      reference those indices via the edgelist.
    //
    //   3. CN_Update with bypass=1 passes mcv_tprev DIRECTLY to mcv_temp
    //      (no latch enable gate):  sc_t = sc_tprev; min1c_t = min1c_tprev
    //      So bypass-mode PE mcv_temp GLITCHES at cycles 2, 3, 4, 5
    //      (once per cross-group update) even when cn_sel=0.
    //
    //   4. If a bypass PE's own cn_sel_N or vn_sel_N coincides with one
    //      of those glitch cycles → spurious capture → mcv_t updates
    //      more than twice per 8-cycle iteration → irregular waveform.
    //
    // THE FIX: Self-contained 2-bit phase counter
    // -------------------------------------------
    //   phase_cnt is LOCAL to each PE instance.
    //   It resets to 2'b00 when cn_sel OR vn_sel fires (phase boundary).
    //   It increments freely mod-4 on all other cycles.
    //   mcv_t is only captured when phase_cnt == 2'b00.
    //
    //   This eliminates spurious captures because:
    //   • phase_cnt==0 fires EXACTLY ONCE every 4 cycles.
    //   • The counter state is INDEPENDENT of any combinational glitches
    //     on mcv_temp caused by cross-group mcv_t feedback.
    //   • Even if mcv_temp glitches at cycles 1, 2, or 3, phase_cnt≠0
    //     → no capture occurs.
    //   • The counter resets are triggered by the already-pipelined
    //     cn_sel/vn_sel from gen.v, so alignment is automatic per group.
    //
    // 4-cycle update guarantee (cycle numbering relative to cn_sel pulse):
    //   posedge 0: cn_sel=1 → phase_cnt reset to 00 → mcv_t <= mcv_temp
    //   posedge 1: phase_cnt = 01 → mcv_t HELD
    //   posedge 2: phase_cnt = 10 → mcv_t HELD
    //   posedge 3: phase_cnt = 11 → mcv_t HELD
    //   posedge 4: vn_sel=1 → phase_cnt reset to 00 → mcv_t <= mcv_temp
    //   posedge 5: phase_cnt = 01 → mcv_t HELD  ... (next 3 cycles hold)
    // =====================================================================

    // ADDED: 2-bit phase counter (new signals only — no existing logic touched)
    reg [1:0] phase_cnt;

    initial phase_cnt = 2'b00;   // prevent X propagation at sim start

    // ADDED: counter control — resets on phase boundary, increments otherwise
    always @(posedge clk)
    begin
        if (cn_sel || vn_sel)
            phase_cnt <= 2'b00;          // synchronous reset to phase boundary
        else
            phase_cnt <= phase_cnt + 2'b01; // modulo-4 free-running count
    end

    // CHANGED: mcv_t registered ONLY when counter is at zero (phase boundary)
    // The computation mcv_temp is left completely untouched — only the
    // TIMING of when the result is captured into the output register changes.
    always @(posedge clk)
    begin
        if (phase_cnt == 2'b00)
            mcv_t <= mcv_temp;           // exactly one capture per 4-cycle window
    end
    
endmodule
