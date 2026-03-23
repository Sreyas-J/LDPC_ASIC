module Lvc_mem #(
    parameter MAX_DV = 3
)(
    input clk,
    input [5*MAX_DV-1:0] din,
    input w_ena,
    output reg [5*MAX_DV-1:0] dout
);

    reg [5*MAX_DV-1:0] mem;

    initial begin
        mem  = {(5*MAX_DV){1'b0}};
        dout = {(5*MAX_DV){1'b0}};
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
