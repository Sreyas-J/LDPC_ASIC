module rom_edgelist (
    input          clk,      // System clock
    input          en,       // Read enable
    input   [3:0]  addr,     // 4-bit address bus
    output reg  [11:0] data_out[0:11]  // 12-bit data output
);

    always @(*) begin
        if (en) begin
//            case (addr)
                // Mapping the provided arrays to 12-bit hex values
                data_out[0] = 12'h238; // [2, 3, 8]
                data_out[1] = 12'h046; // [0, 4, 6]
                data_out[2] = 12'h157; // [1, 5, 7]
                data_out[3] = 12'h046; // [0, 4, 6]
                data_out[4] = 12'h157; // [1, 5, 7]
                data_out[5] = 12'h238; // [2, 3, 8]
                data_out[6] = 12'h037; // [0, 3, 7]
                data_out[7] = 12'h148; // [1, 4, 8]
                data_out[8] = 12'h256; // [2, 5, 6]
                data_out[9] = 12'h138; // [1, 3, 8]
                data_out[10] = 12'h246; // [2, 4, 6]
                data_out[11] = 12'h057; // [0, 5, 7]
                
                // Safety net for unused addresses (12-15)
//                default: data_out <= 12'h000; 
//            endcase
        end
    end

endmodule