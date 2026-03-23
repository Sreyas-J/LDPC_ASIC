// top.v — Synthesizable LDPC decoder top module

module top #(
    parameter SIZE     = 3,
    parameter M_B      = 3,
    parameter N_B      = 4,
    parameter MAX_ITER = 5
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire [N_B*SIZE*5-1:0]   qv_flat,
    output wire [N_B*SIZE-1:0]     cv_list,
    output wire                    done
);

    wire iter_flag;
    wire cn_reset;
    wire cn_sel;
    wire vn_sel;

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

    gen #(
        .SIZE(SIZE), .M_B(M_B), .N_B(N_B)
    ) gen_core (
        .clk      (clk),
        .rst      (rst),
        .iter_flag(iter_flag),
        .cn_reset (cn_reset),
        .cn_sel   (cn_sel),
        .vn_sel   (vn_sel),
        .qv_flat  (qv_flat),
        .cv_list  (cv_list)
    );

endmodule
