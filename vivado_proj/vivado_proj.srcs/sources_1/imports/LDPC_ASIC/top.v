// top.v
//
// Top-level integration of the LDPC decoder with AXI4-Stream I/O:
//   - AXI Stream Slave:  receives channel LLRs (qv_flat) in DATA_WIDTH-bit beats
//   - AXI Stream Master: sends decoded hard decisions (cv_list) in DATA_WIDTH-bit beats
//   - controller:        generates all sequencing signals
//   - gen:               check-node + variable-node processing core
//
// Decoding starts automatically when the input stream frame completes (s_axis_tlast).

module top #(
    parameter N          = 672,
    parameter M          = 126,
    parameter MAX_DC     = 15,
    parameter MAX_DV     = 3,
    parameter MAX_ITER   = 0,
    parameter DATA_WIDTH = 256
)(
    input  wire                   clk,
    input  wire                   rst,

    // AXI Stream Slave – input LLRs
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,

    // AXI Stream Master – output decoded bits
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast
);

    // ----------------------------------------------------------------
    // Parameters — pad to full multiples of DATA_WIDTH for clean indexing
    // ----------------------------------------------------------------
    localparam QV_BITS       = N * 5;
    localparam NUM_IN_BEATS  = (QV_BITS + DATA_WIDTH - 1) / DATA_WIDTH;
    localparam QV_PAD_BITS   = NUM_IN_BEATS * DATA_WIDTH;
    localparam NUM_OUT_BEATS = (N + DATA_WIDTH - 1) / DATA_WIDTH;
    localparam CV_PAD_BITS   = NUM_OUT_BEATS * DATA_WIDTH;

    // Bit-widths for counters
    localparam IN_CNT_W  = (NUM_IN_BEATS > 1)  ? $clog2(NUM_IN_BEATS)  : 1;
    localparam OUT_CNT_W = (NUM_OUT_BEATS > 1) ? $clog2(NUM_OUT_BEATS) : 1;

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    reg  [QV_PAD_BITS-1:0]  qv_flat_padded;
    wire [QV_BITS-1:0]      qv_flat;
    assign qv_flat = qv_flat_padded[QV_BITS-1:0];

    wire [N-1:0]            cv_list;
    reg  [CV_PAD_BITS-1:0]  cv_list_padded;

    wire iter_flag, cn_reset, cn_sel, vn_sel, done;
    reg  start;

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    localparam S_LOAD   = 2'd0;
    localparam S_DECODE = 2'd1;
    localparam S_OUTPUT = 2'd2;

    reg [1:0]            state;
    reg [IN_CNT_W-1:0]  in_beat_cnt;
    reg [OUT_CNT_W-1:0] out_beat_cnt;

    // s_axis_tready: accept data only during LOAD state (combinational)
    assign s_axis_tready = (state == S_LOAD);

    // m_axis_tdata / m_axis_tlast: combinational from padded register + counter
    assign m_axis_tdata = cv_list_padded[out_beat_cnt * DATA_WIDTH +: DATA_WIDTH];
    assign m_axis_tlast = (out_beat_cnt == NUM_OUT_BEATS - 1) && m_axis_tvalid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_LOAD;
            in_beat_cnt    <= 0;
            out_beat_cnt   <= 0;
            qv_flat_padded <= {QV_PAD_BITS{1'b0}};
            cv_list_padded <= {CV_PAD_BITS{1'b0}};
            start          <= 1'b0;
            m_axis_tvalid  <= 1'b0;
        end else begin
            start <= 1'b0;

            case (state)
                // -----------------------------------------------
                // S_LOAD: Accept input stream beats
                // -----------------------------------------------
                S_LOAD: begin
                    m_axis_tvalid <= 1'b0;

                    if (s_axis_tvalid && s_axis_tready) begin
                        qv_flat_padded[in_beat_cnt*DATA_WIDTH +: DATA_WIDTH] <= s_axis_tdata;

                        if (s_axis_tlast) begin
                            start       <= 1'b1;
                            state       <= S_DECODE;
                            in_beat_cnt <= 0;
                        end else begin
                            in_beat_cnt <= in_beat_cnt + 1;
                        end
                    end
                end

                // -----------------------------------------------
                // S_DECODE: Wait for decoder to finish
                // -----------------------------------------------
                S_DECODE: begin
                    if (done) begin
                        cv_list_padded          <= {{(CV_PAD_BITS-N){1'b0}}, cv_list};
                        state                   <= S_OUTPUT;
                        out_beat_cnt            <= 0;
                        m_axis_tvalid           <= 1'b1;
                    end
                end

                // -----------------------------------------------
                // S_OUTPUT: Send decoded result via AXI Stream
                //   tdata and tlast are combinational from out_beat_cnt
                //   tvalid is registered (set on entry, cleared on exit)
                // -----------------------------------------------
                S_OUTPUT: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (out_beat_cnt == NUM_OUT_BEATS - 1) begin
                            state         <= S_LOAD;
                            out_beat_cnt  <= 0;
                            m_axis_tvalid <= 1'b0;
                        end else begin
                            out_beat_cnt <= out_beat_cnt + 1;
                        end
                    end
                end

                default: state <= S_LOAD;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Controller
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
