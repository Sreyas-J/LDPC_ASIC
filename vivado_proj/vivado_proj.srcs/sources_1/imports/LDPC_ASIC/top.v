// top.v
//
// Top-level integration of the LDPC decoder:
//   controller  - generates all sequencing signals
//   gen         - check-node + variable-node processing core
//
// External interface (what the testbench drives):
//   clk     - system clock
//   rst     - async active-high reset (resets controller FSM)
//   start   - pulse high for >=1 cycle to begin a decode run
//   qv_flat - channel LLRs: N PEs x 5-bit sign-magnitude
//   cv_list - hard decisions for all N variable nodes
//   done    - pulses high for 1 cycle when decoding is complete

module top #(
    parameter N        = 672,
    parameter M        = 126,
    parameter MAX_DC   = 15,
    parameter MAX_DV   = 3,
    parameter MAX_ITER = 5
)(
    input  wire            clk,
    input  wire            rst,
    input  wire            start,
    input  wire [N*5-1:0]  qv_flat,
    output wire [N-1:0]    cv_list,
    output wire            done
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
        .N(N), .M(M), .MAX_DC(MAX_DC), .MAX_DV(MAX_DV)
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
