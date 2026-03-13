module Lvc_mem #(
    parameter DATA_WIDTH = 15
)(
    input clk,
    input [DATA_WIDTH-1:0] din,
    input w_ena,
    output reg [DATA_WIDTH-1:0] dout
);

    reg [DATA_WIDTH-1:0] mem;

    initial begin
        mem  = {DATA_WIDTH{1'b0}};
        dout = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk)
    begin
        if(w_ena) mem <= din;
    end
    
    always @(posedge clk)
    begin
        dout <= mem;
    end

endmodule