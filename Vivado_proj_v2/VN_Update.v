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
    
    // Input fields
    wire sc_tprev, Lvc_tprev_sign;
    wire [3:0] min1c_tprev, min2c_tprev, Lvc_tprev_mag;
    
    // temp vars
    reg [4:0] Lvc_reg;
    
    // output fields
    wire mcv_sign;
    reg [3:0] mcv_mag;

    // Latch-based output regs (replace illegal wire self-assignments)
    reg [4:0] mcv_latch;
    reg [4:0] Lvc_latch;

    // ------------------------------------------------------------------
    // FIX A: Initialise ALL registers to zero at simulation start.
    //
    // WHY THIS IS NEEDED:
    //   mcv_latch and Lvc_latch are inferred latches (see Fixes C & D).
    //   A latch HOLDS its value when its enable is low.  Before the
    //   first VN phase (vn_ena=1), both latches have enable=0, so they
    //   hold whatever value they started with — which is X in simulation.
    //
    //   mcv feeds directly into Lv in PE:
    //       Lv = $signed(mcv[4:0]) + ... + $signed(Qv)
    //   If mcv=X then Lv=X, then Cv=X, then cv_list=XXX for the entire
    //   CN phase of iteration 0.  The X is never flushed because the
    //   latch keeps holding it until vn_ena first pulses high.
    //
    //   Similarly Lvc_reg feeds Lvc_latch.  If it starts X it poisons
    //   Lvc_mem on the first w_ena pulse.
    //
    // FIX: Force all three registers to 0 at t=0.
    //   For bypass=1 layers, mcv_latch is overwritten to 0 by the
    //   combinational logic anyway.  For bypass=0 layers we rely on
    //   this initial block to provide a clean starting value that the
    //   latch will hold until the first VN phase writes a real one.
    // ------------------------------------------------------------------
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


    // ------------------------------------------------------------------
    // FIX B: Width mismatch in mcv_mag selection.
    //
    // ORIGINAL:  if(min1c_tprev == Lvc_tprev)
    //   min1c_tprev is 4 bits; Lvc_tprev is 5 bits. Verilog zero-extends
    //   the 4-bit operand to 5 bits, so whenever Lvc_tprev[4]=1 (a
    //   negative message) bit[4] of the extended min1c_tprev is 0,
    //   making the comparison permanently FALSE for all negative Lvc.
    //   Result: mcv_mag always returns min1c_tprev regardless of whether
    //   this variable is the minimum contributor — wrong extrinsic.
    //
    // FIX: Compare magnitude fields only (both are 4-bit).
    // ------------------------------------------------------------------
    always @(*)
    begin
        if (min1c_tprev == Lvc_tprev_mag) mcv_mag = min2c_tprev;
        else                               mcv_mag = min1c_tprev;
    end

    assign mcv_sign = Lvc_tprev_sign ^ sc_tprev;


    // ------------------------------------------------------------------
    // FIX C: mcv wire self-assignment — zero-delay combinational loop.
    //
    // ORIGINAL:
    //   assign mcv = (!bypass) ? ((vn_ena) ? (...) : mcv) : 0;
    //   When bypass=0, vn_ena=0 → mcv = mcv → evaluates X, writes X,
    //   re-triggers → permanently X, poisoning Lv and cv_list.
    //
    // FIX: Infer a D-latch via always @(*) with a missing else branch.
    //   bypass=1  → forced 0 (also acts as a known-value init path).
    //   bypass=0, vn_ena=1 → latch transparent, compute new mcv.
    //   bypass=0, vn_ena=0 → missing else → latch CLOSED, holds value.
    // ------------------------------------------------------------------
    always @(*) begin
        if (bypass)
            mcv_latch = 5'b0;
        else if (vn_ena)
            mcv_latch = (mcv_sign) ? -{1'b0, mcv_mag} : {1'b0, mcv_mag};
        // else: latch holds — retains the last computed mcv value
    end
    assign mcv = mcv_latch;


    // ------------------------------------------------------------------
    // FIX D-pre: Correct the Lvc_reg subtraction.
    //
    // PREVIOUS (wrong) FIX:
    //   Lvc_reg <= Lv - $signed({1'b0, mcv[3:0]});
    //   This silently drops mcv[4] — the two's complement sign bit —
    //   turning every negative extrinsic message into a positive number
    //   and computing the wrong variable-node LLR.
    //
    // CORRECT FIX:
    //   Lvc_reg <= Lv - $signed(mcv);
    //   $signed(mcv) sign-extends the full 5-bit two's complement mcv
    //   to match the 7-bit width of Lv before subtraction. The 7-bit
    //   result is then truncated to 5 bits stored in Lvc_reg, which is
    //   the intended saturation / clipping behaviour.
    // ------------------------------------------------------------------
    always @(posedge clk)
    begin
        Lvc_reg <= Lv - $signed(mcv);
    end


    // ------------------------------------------------------------------
    // FIX D: Lvc wire self-assignment — identical zero-delay loop.
    //
    // ORIGINAL:
    //   assign Lvc = (vn_ena) ? {...} : Lvc;
    //   When vn_ena=0 → Lvc = Lvc → X forever. This corrupts
    //   Lvc_mem.din, writing X into the cache on every w_ena pulse
    //   (which arrives 1 cycle after vn_sel due to PE's registered
    //   w_ena), permanently poisoning Lvc_tprev for all later iters.
    //
    // FIX: Infer a D-latch. When vn_ena=0 the latch holds the last
    //   valid sign-magnitude converted Lvc_reg value for exactly the
    //   one extra cycle needed by w_ena to capture it into Lvc_mem.
    // ------------------------------------------------------------------
    always @(*) begin
        if (vn_ena)
            Lvc_latch = {Lvc_reg[4], (Lvc_reg[4] ? -Lvc_reg[3:0] : Lvc_reg[3:0])};
        // else: latch holds — value must remain stable for w_ena
    end
    assign Lvc = Lvc_latch;


endmodule
