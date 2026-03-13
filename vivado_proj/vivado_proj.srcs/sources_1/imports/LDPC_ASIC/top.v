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
//   qv_flat — channel LLRs: NUM_PE PEs × LLR_BITS-bit sign-magnitude
//
// Outputs:
//   cv_list — hard decisions for all NUM_PE variable nodes
//   done    — pulses high for 1 cycle when decoding is complete

module top #(
    parameter MAX_ITER      = 5,
    parameter NUM_PE        = 12,
    parameter NUM_CN        = 9,
    parameter NUM_LAYERS    = 3,
    parameter MAX_CN_DEGREE = 4,
    parameter LLR_BITS      = 5,
    parameter CN_INDEX_BITS = 4
)(
    input  wire                       clk,
    input  wire                       rst,
    input  wire                       start,
    input  wire [NUM_PE*LLR_BITS-1:0] qv_flat,
    output wire [NUM_PE-1:0]          cv_list,
    output wire                       done
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
    gen #(
        .NUM_PE       (NUM_PE),
        .NUM_CN       (NUM_CN),
        .NUM_LAYERS   (NUM_LAYERS),
        .MAX_CN_DEGREE(MAX_CN_DEGREE),
        .LLR_BITS     (LLR_BITS),
        .CN_INDEX_BITS(CN_INDEX_BITS)
    ) gen_core (
        .clk      (clk),
        .iter_flag(iter_flag),
        .cn_reset (cn_reset),
        .cn_sel   (cn_sel),
        .vn_sel   (vn_sel),
        .qv_flat  (qv_flat),
        .cv_list  (cv_list)
    );

endmodule
