module Lvc_mem #(
    parameter MAX_DV = 3
)(
    input clk,
    input rst,
    input [5*MAX_DV-1:0] din,
    input w_ena,
    output reg [5*MAX_DV-1:0] dout
);

    reg [5*MAX_DV-1:0] mem;

    always @(posedge clk) begin
        if (rst)
            mem <= {(5*MAX_DV){1'b0}};
        else if (w_ena)
            mem <= din;
    end

    always @(posedge clk) begin
        if (rst)
            dout <= {(5*MAX_DV){1'b0}};
        else
            dout <= mem;
    end

endmodule
