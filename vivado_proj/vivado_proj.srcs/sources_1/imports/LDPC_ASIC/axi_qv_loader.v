// axi_qv_loader.v — AXI4-Lite write-only slave for loading qv_flat
//
// Accepts 32-bit AXI4-Lite writes at sequential word addresses.
// After NUM_WORDS writes, asserts qv_loaded for one cycle.
// Writing to address 0 resets the word counter for a fresh load.

`timescale 1ns / 1ps

module axi_qv_loader #(
    parameter integer QV_TOTAL_BITS = 60,    // N_B * SIZE * 5
    parameter integer DATA_WIDTH    = 32,
    parameter integer ADDR_WIDTH    = 32
)(
    input  wire                    clk,
    input  wire                    rst,

    // AXI4-Lite Write Address Channel
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire                    S_AXI_AWVALID,
    output reg                     S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WVALID,
    output reg                     S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output wire [1:0]              S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    // Outputs to decoder
    output reg [QV_TOTAL_BITS-1:0] qv_flat,
    output reg                     qv_loaded
);

    // Number of 32-bit words needed to fill qv_flat
    localparam integer NUM_WORDS = (QV_TOTAL_BITS + DATA_WIDTH - 1) / DATA_WIDTH;

    // Bits needed for word counter
    // Simple ceiling-log2: enough to hold NUM_WORDS
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer CNT_WIDTH = (NUM_WORDS > 1) ? clog2(NUM_WORDS) : 1;

    // Always respond OKAY
    assign S_AXI_BRESP = 2'b00;

    // Internal state
    reg [CNT_WIDTH:0] word_cnt;  // extra bit for terminal compare
    reg               aw_latched;
    reg [ADDR_WIDTH-1:0] aw_addr_reg;

    // ---------------------------------------------------------------
    // AXI4-Lite Write Handshake
    // We require both AW and W channels to handshake before issuing B.
    // Simple approach: accept AW and W independently, latch both,
    // then perform the write and issue BRESP.
    // ---------------------------------------------------------------

    // State: IDLE -> WAIT_AW_W -> WRITE -> RESP
    localparam S_IDLE    = 2'd0;
    localparam S_WRITE   = 2'd1;
    localparam S_RESP    = 2'd2;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] w_data_reg;

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            aw_latched    <= 1'b0;
            aw_addr_reg   <= {ADDR_WIDTH{1'b0}};
            w_data_reg    <= {DATA_WIDTH{1'b0}};
            word_cnt      <= 0;
            qv_flat       <= {QV_TOTAL_BITS{1'b0}};
            qv_loaded     <= 1'b0;
        end else begin
            // Default: deassert one-shot signals
            qv_loaded <= 1'b0;

            case (state)

                S_IDLE: begin
                    S_AXI_BVALID <= 1'b0;
                    // Accept AW and W in the same cycle or separately
                    S_AXI_AWREADY <= 1'b1;
                    S_AXI_WREADY  <= 1'b1;

                    if (S_AXI_AWVALID && S_AXI_AWREADY)
                        aw_addr_reg <= S_AXI_AWADDR;

                    // Both channels handshaked
                    if ((S_AXI_AWVALID && S_AXI_AWREADY) &&
                        (S_AXI_WVALID  && S_AXI_WREADY)) begin
                        aw_addr_reg   <= S_AXI_AWADDR;
                        w_data_reg    <= S_AXI_WDATA;
                        S_AXI_AWREADY <= 1'b0;
                        S_AXI_WREADY  <= 1'b0;
                        state         <= S_WRITE;
                    end
                    // AW only
                    else if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        aw_latched    <= 1'b1;
                        S_AXI_AWREADY <= 1'b0;
                        // Keep WREADY high, wait for W
                    end
                    // W arrives after AW was already latched
                    if (aw_latched && S_AXI_WVALID && S_AXI_WREADY) begin
                        w_data_reg    <= S_AXI_WDATA;
                        S_AXI_WREADY  <= 1'b0;
                        S_AXI_AWREADY <= 1'b0;
                        aw_latched    <= 1'b0;
                        state         <= S_WRITE;
                    end
                end

                S_WRITE: begin
                    // Perform the actual write into qv_flat
                    // Word address = byte_addr[ADDR_WIDTH-1:2]
                    // We use the word counter approach: word_cnt tracks
                    // how many words have been written sequentially.
                    // Address 0 resets the counter.

                    if (aw_addr_reg == {ADDR_WIDTH{1'b0}}) begin
                        // Writing to address 0 starts fresh
                        word_cnt <= 1;
                        qv_flat[0 +: DATA_WIDTH] <= w_data_reg;
                    end else begin
                        // Use word_cnt to place data at the correct position
                        // Shift data into the register from LSB to MSB
                        begin : write_blk
                            integer bit_pos;
                            bit_pos = word_cnt * DATA_WIDTH;
                            // Only write bits that are within qv_flat bounds
                            begin : inner_write
                                integer b;
                                for (b = 0; b < DATA_WIDTH; b = b + 1) begin
                                    if (bit_pos + b < QV_TOTAL_BITS)
                                        qv_flat[bit_pos + b] <= w_data_reg[b];
                                end
                            end
                            word_cnt <= word_cnt + 1;
                        end
                    end

                    // Check if loading is complete
                    // (word_cnt is the count *before* this write, so check
                    //  if this is the last word)
                    if ((aw_addr_reg == {ADDR_WIDTH{1'b0}} && NUM_WORDS == 1) ||
                        (aw_addr_reg != {ADDR_WIDTH{1'b0}} && (word_cnt + 1 >= NUM_WORDS))) begin
                        qv_loaded <= 1'b1;
                    end

                    S_AXI_BVALID <= 1'b1;
                    state        <= S_RESP;
                end

                S_RESP: begin
                    // Wait for BREADY
                    if (S_AXI_BREADY && S_AXI_BVALID) begin
                        S_AXI_BVALID <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
