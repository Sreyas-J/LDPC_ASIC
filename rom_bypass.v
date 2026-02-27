module rom_bypass (
    input         clk,      // System clock
    input         en,       // Read enable
    input   [3:0] addr,     // 4-bit address bus for locations 0 to 11
    output reg  [3:0] data_out  // 4-bit data output
);

    always @(posedge clk) begin
        if (en) begin
            case (addr)
                4'd0:  data_out <= 4'h3; // [3]
                4'd1:  data_out <= 4'h4; // [4]
                4'd2:  data_out <= 4'h5; // [5]
                4'd3:  data_out <= 4'hF; // [] -> filled with 15
                4'd4:  data_out <= 4'hF; // [] -> filled with 15
                4'd5:  data_out <= 4'hF; // [] -> filled with 15
                4'd6:  data_out <= 4'h0; // [0]
                4'd7:  data_out <= 4'h1; // [1]
                4'd8:  data_out <= 4'h2; // [2]
                4'd9:  data_out <= 4'hF; // [] -> filled with 15
                4'd10: data_out <= 4'hF; // [] -> filled with 15
                4'd11: data_out <= 4'hF; // [] -> filled with 15
                
                // Safety net for unused addresses (12-15)
                default: data_out <= 4'h0; 
            endcase
        end
    end

endmodule