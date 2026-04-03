// top.v — Synthesizable LDPC decoder top module with AXI4-Lite qv input

module top #(
    parameter SIZE       = 3,
    parameter M_B        = 3,
    parameter N_B        = 4,
    parameter MAX_ITER   = 5,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,

    // AXI4-Lite Write interface for qv_flat loading
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,

    output wire [1:0]              S_AXI_BRESP,
    output wire                    S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    // Decoder outputs
    output wire                    qv_loaded,
    output wire [N_B*SIZE-1:0]     cv_list,
    output wire                    done
);

    localparam QV_TOTAL_BITS = N_B * SIZE * 5;

    // Internal qv_flat assembled by the AXI loader
    wire [QV_TOTAL_BITS-1:0] qv_flat;

    // AXI4-Lite qv loader
    axi_qv_loader #(
        .QV_TOTAL_BITS(QV_TOTAL_BITS),
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH)
    ) qv_loader (
        .clk           (clk),
        .rst           (rst),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY),
        .qv_flat       (qv_flat),
        .qv_loaded     (qv_loaded)
    );

    // Controller
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

    // Decoder core
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
