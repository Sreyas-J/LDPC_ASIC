// controller.v
//
// Sequencer for the LDPC min-sum flooding decoder (gen.v core).
//
// One decode run = MAX_ITER iterations, each exactly 6 clock cycles.
//
// Registered-output timing (signals change on posedge, seen by gen.v
// on the *following* posedge):
//
//   Phase 0  : cn_sel=1, cn_reset=1, iter_flag=(first iter)  registered
//   Phase 1  : gen.v captures cn_summary  (idle controller output)
//   Phase 2  : vn_sel=1 registered  (first VN cycle)
//   Phase 3  : vn_sel=1 registered AGAIN (second VN cycle)
//              At phase 3 posedge: PE sees vn_sel=1 → mcv_latch open (correct
//              mcv) → Lvc_reg updated correctly.  After phase 3 NBA, vn_sel
//              is still 1 (registered), so Lvc_latch stays open and captures
//              the new Lvc_reg.  This is necessary because Lvc_latch is an
//              inferred transparent latch; with a registered controller the
//              latch would otherwise close before seeing the updated Lvc_reg.
//   Phase 4  : PE sees vn_sel=1 from phase 3 → w_ena=1 → Lvc_mem written;
//              vn_sel_d=1 → cv_list captured.
//   Phase 5  : cv_list valid; if last iter → DONE, else assert cn_sel=1
//              for next iteration and return to phase 1
//
// The IDLE→RUN transition asserts the phase-0 outputs immediately
// (same posedge as start), saving one dead cycle.
//
// Interface
//   Inputs  : clk, rst (async active-high), start (pulse ≥1 cycle)
//   Outputs : iter_flag, cn_reset, cn_sel, vn_sel - directly to gen.v
//             done - pulses high for 1 cycle when decoding is complete

module controller #(
    parameter MAX_ITER = 5
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    output reg  iter_flag,
    output reg  cn_reset,
    output reg  cn_sel,
    output reg  vn_sel,
    output reg  done
);

    // ----------------------------------------------------------------
    // State encoding
    // ----------------------------------------------------------------
    localparam IDLE = 2'd0;
    localparam RUN  = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;
    reg [2:0] phase;          // 1..5 within one iteration
    reg [3:0] iter_count;     // 0 .. MAX_ITER-1

    // ----------------------------------------------------------------
    // Main FSM
    // ----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            phase      <= 3'd0;
            iter_count <= 4'd0;
            iter_flag  <= 1'b0;
            cn_reset   <= 1'b0;
            cn_sel     <= 1'b0;
            vn_sel     <= 1'b0;
            done       <= 1'b0;
        end else begin
            // Default all outputs low every cycle
            iter_flag <= 1'b0;
            cn_reset  <= 1'b0;
            cn_sel    <= 1'b0;
            vn_sel    <= 1'b0;
            done      <= 1'b0;

            case (state)

                // ------------------------------------------------
                // IDLE: wait for start pulse
                // On the same posedge as start, register the phase-0
                // outputs so gen.v sees them on the very next cycle.
                // ------------------------------------------------
                IDLE: begin
                    if (start) begin
                        cn_sel     <= 1'b1;   // gen.v captures CN next cycle
                        cn_reset   <= 1'b1;
                        iter_flag  <= 1'b1;   // first iteration: mux Qv
                        state      <= RUN;
                        phase      <= 3'd1;
                        iter_count <= 4'd0;
                    end
                end

                // ------------------------------------------------
                // RUN: phases 1-5, repeated MAX_ITER times
                // ------------------------------------------------
                RUN: begin
                    case (phase)

                        // Phase 1: gen.v is sampling cn_sel=1 (registered
                        // last cycle); nothing new to drive this cycle.
                        // Keep iter_flag=1 during the first iteration so that
                        // PE.v continues to mux Qv into Lvc_muxed.
                        3'd1: begin
                            if (iter_count == 4'd0) iter_flag <= 1'b1;
                            phase <= 3'd2;
                        end

                        // Phase 2: assert vn_sel - gen.v / PE will act on
                        // it on the next posedge.
                        // Keep iter_flag=1 for iter 0: the VN_Update uses
                        // Lvc_muxed (= Qv when iter_flag=1) for sign/magnitude
                        // exclusion; using stale Lvc_tprev=0 instead gives the
                        // wrong sign on every mcv output.
                        3'd2: begin
                            if (iter_count == 4'd0) iter_flag <= 1'b1;
                            vn_sel <= 1'b1;
                            phase  <= 3'd3;
                        end

                        // Phase 3: keep vn_sel=1 so the Lvc_latch (transparent
                        // latch in VN_Update) stays open after Lvc_reg updates
                        // at this posedge, capturing the correct new value.
                        // Also keep iter_flag=1 for iter 0.
                        3'd3: begin
                            if (iter_count == 4'd0) iter_flag <= 1'b1;
                            vn_sel <= 1'b1;
                            phase  <= 3'd4;
                        end

                        // Phase 4: Lvc_mem written (w_ena=1), cv_list
                        // captured (vn_sel_d=1).
                        // Keep iter_flag=1 for iter 0 (latch still needs Qv).
                        3'd4: begin
                            if (iter_count == 4'd0) iter_flag <= 1'b1;
                            phase <= 3'd5;
                        end

                        // Phase 5: cv_list is valid and stable.
                        // Either finish or kick off the next iteration.
                        3'd5: begin
                            if (iter_count == MAX_ITER - 1) begin
                                state <= DONE;
                            end else begin
                                // Assert CN phase for next iteration
                                // (iter_flag stays 0 - use stored Lvc)
                                cn_sel     <= 1'b1;
                                cn_reset   <= 1'b1;
                                iter_count <= iter_count + 1'b1;
                                phase      <= 3'd1;
                            end
                        end

                        default: phase <= 3'd1;
                    endcase
                end

                // ------------------------------------------------
                // DONE: pulse done for one cycle then return to IDLE
                // ------------------------------------------------
                DONE: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
