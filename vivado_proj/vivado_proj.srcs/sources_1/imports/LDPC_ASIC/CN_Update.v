module CN_Update(
    input        cn_ena,
    input        reset,
    input        bypass,
    input  [8:0] mcv_tprev,
    input  [4:0] Lvc_tprev,
    input        iter_flag,
    output [8:0] mcv_t
);

    // --------------- Input field slicing ---------------
    wire        sc_tprev       = mcv_tprev[8];
    wire [3:0]  min1c_tprev    = mcv_tprev[7:4];
    wire [3:0]  min2c_tprev    = mcv_tprev[3:0];
    wire        Lvc_tprev_sign = Lvc_tprev[4];
    wire [3:0]  Lvc_tprev_mag  = Lvc_tprev[3:0];

    // --------------- Output registers (latches) --------
    reg        sc_t;
    reg [3:0]  min1c_t;
    reg [3:0]  min2c_t;

    // --------------- Combinational logic ---------------
    // Latch inference summary:
    //   bypass=1               → outputs always driven (no latch)
    //   bypass=0, cn_ena=1     → outputs always driven (no latch)
    //   bypass=0, cn_ena=0     → NO assignment → D-LATCH holds prev value
    //                            (latch enable = cn_ena, gated by !bypass)
    //
    // IMPORTANT: cn_ena must be 1 on the first valid reset cycle to
    // initialize the latches before they are ever expected to hold.

    always @(*) begin

        if (bypass) begin
            // ---- Bypass / iteration-reset mode --------------------
            if (iter_flag) begin
                sc_t    = 1'b0;
                min1c_t = 4'hf;
                min2c_t = 4'hf;
            end else begin
                sc_t    = sc_tprev;
                min1c_t = min1c_tprev;
                min2c_t = min2c_tprev;
            end

        end else if (cn_ena) begin
            // ---- Active CN-update mode (bypass=0, cn_ena=1) -------
            if (reset) begin
                // Initialise from incoming variable node message
                sc_t    = Lvc_tprev_sign;
                min1c_t = Lvc_tprev_mag;
                min2c_t = 4'b1111;
            end else begin
                // Accumulate sign and update min-1 / min-2
                sc_t = sc_tprev ^ Lvc_tprev_sign;

                if (Lvc_tprev_mag < min1c_tprev) begin
                    // New magnitude is smaller than current minimum
                    min2c_t = min1c_tprev;     // old min-1 → min-2
                    min1c_t = Lvc_tprev_mag;   // new value → min-1
                end else if (Lvc_tprev_mag < min2c_tprev) begin
                    // New magnitude falls between min-1 and min-2
                    min1c_t = min1c_tprev;     // min-1 unchanged
                    min2c_t = Lvc_tprev_mag;   // new value → min-2
                end else begin
                    // New magnitude is >= min-2: nothing changes
                    min1c_t = min1c_tprev;
                    min2c_t = min2c_tprev;
                end
            end

        end
        // bypass=0, cn_ena=0 → NO assignment to sc_t / min1c_t / min2c_t
        // Verilog infers a transparent D-latch here:
        //   enable  = cn_ena (active high)
        //   gate    = !bypass
        // When enable is low the latch is CLOSED and retains its value.

    end

    // --------------- Output assembly ---------------------------
    assign mcv_t[8]   = sc_t;
    assign mcv_t[7:4] = min1c_t;
    assign mcv_t[3:0] = min2c_t;

endmodule