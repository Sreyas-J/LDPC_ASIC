module rom_edgelist (
    input          clk,      // System clock
    input          en,       // Read enable
    input   [3:0]  addr,     // 4-bit address bus
    output reg  [11:0] data_out  // 12-bit data output
);

    always @(posedge clk) begin
        if (en) begin
            case (addr)
                // Mapping the provided arrays to 12-bit hex values
                4'd0:  data_out <= 12'h238; // [2, 3, 8]
                4'd1:  data_out <= 12'h046; // [0, 4, 6]
                4'd2:  data_out <= 12'h157; // [1, 5, 7]
                4'd3:  data_out <= 12'h046; // [0, 4, 6]
                4'd4:  data_out <= 12'h157; // [1, 5, 7]
                4'd5:  data_out <= 12'h238; // [2, 3, 8]
                4'd6:  data_out <= 12'h037; // [0, 3, 7]
                4'd7:  data_out <= 12'h148; // [1, 4, 8]
                4'd8:  data_out <= 12'h256; // [2, 5, 6]
                4'd9:  data_out <= 12'h138; // [1, 3, 8]
                4'd10: data_out <= 12'h246; // [2, 4, 6]
                4'd11: data_out <= 12'h057; // [0, 5, 7]
                
                // Safety net for unused addresses (12-15)
                default: data_out <= 12'h000; 
            endcase
        end
    end

endmodule