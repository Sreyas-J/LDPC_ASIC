
module Lvc_mem(

input clk,
input [14:0] din,
input w_ena,
output reg [14 : 0] dout
);

    reg [14:0] mem;
    always @(posedge clk)
    begin
    
        if(w_ena) mem <= din;
    
    end
    
    always @(posedge clk)
    begin
    
        dout <= mem;
    
    end


endmodule
