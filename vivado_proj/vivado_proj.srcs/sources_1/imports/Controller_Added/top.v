// top.v
//
// Top-level integration of the LDPC decoder:
//   controller  — generates all sequencing signals
//   gen         — check-node + variable-node processing core
//
// External interface (what the testbench drives):
//   clk     — system clock
//   rst     — async active-high reset (resets controller FSM)
//   start   — pulse high for ≥1 cycle to begin a decode run
//   qv_flat — channel LLRs: 12 PEs × 5-bit sign-magnitude,
//             PE0 at [4:0], PE11 at [59:55]
//
// Outputs:
//   cv_list — hard decisions for all 12 variable nodes
//   done    — pulses high for 1 cycle when decoding is complete

module top #(
    parameter MAX_ITER = 5
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [59:0] qv_flat,
    output wire [11:0] cv_list,
    output wire        done
);

    wire iter_flag;
    wire cn_reset;
    wire cn_sel;
    wire vn_sel;

    // ----------------------------------------------------------------
    // Controller: generates iter_flag / cn_reset / cn_sel / vn_sel
    // ----------------------------------------------------------------
    controller #(
        .MAX_ITER(MAX_ITER)
    ) ctrl (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .iter_flag(iter_flag),
        .cn_reset (cn_reset),
        .cn_sel   (cn_sel),
        .vn_sel   (vn_sel),
        .done     (done)
    );

    // ----------------------------------------------------------------
    // Decoder core
    // ----------------------------------------------------------------
    gen gen_core (
        .clk      (clk),
        .iter_flag(iter_flag),
        .cn_reset (cn_reset),
        .cn_sel   (cn_sel),
        .vn_sel   (vn_sel),
        .qv_flat  (qv_flat),
        .cv_list  (cv_list)
    );

endmodule
