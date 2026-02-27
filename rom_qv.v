
module rom_qv (
    input        clk,      // System clock
    input        en,       // Read enable
    input   [3:0] addr,     // 4-bit address bus for locations 0 to 11
    output reg  [4:0] data_out  // 5-bit LLR data output
);

    always @(posedge clk) begin
        if (en) begin
            case (addr)
                // Placeholder 5-bit LLR values (e.g., in 2's complement)
                // 5'h00 to 5'h0F are positive (0 to +15)
                // 5'h10 to 5'h1F are negative (-16 to -1)
                
                4'd0:  data_out <= 5'h07; // e.g., strong '0' (+7)
                4'd1:  data_out <= 5'h1A; // e.g., moderate '1' (-6)
                4'd2:  data_out <= 5'h02; // e.g., weak '0' (+2)
                4'd3:  data_out <= 5'h1F; // e.g., very weak '1' (-1)
                4'd4:  data_out <= 5'h0C; // (+12)
                4'd5:  data_out <= 5'h14; // (-12)
                4'd6:  data_out <= 5'h00; // Complete uncertainty (0)
                4'd7:  data_out <= 5'h0E; // (+14)
                4'd8:  data_out <= 5'h11; // (-15)
                4'd9:  data_out <= 5'h05; // (+5)
                4'd10: data_out <= 5'h18; // (-8)
                4'd11: data_out <= 5'h09; // (+9)
                
                // Safety net for unused addresses (12-15)
                default: data_out <= 5'h00; 
            endcase
        end
    end

endmodule
