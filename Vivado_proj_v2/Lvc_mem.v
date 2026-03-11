module Lvc_mem(

input clk,
input [14:0] din,
input w_ena,
output reg [14:0] dout
);

    reg [14:0] mem;

    // ------------------------------------------------------------------
    // FIX: Initialise mem and dout to zero at simulation start.
    //
    // ORIGINAL: Both registers start as X in simulation.
    //   dout has NO read-enable gate — it is clocked unconditionally
    //   every cycle (always @(posedge clk) dout <= mem).  Therefore on
    //   the very first posedge, dout captures X from mem and becomes X.
    //   dout feeds Lvc_tprev in PE, which (when iter_flag=0) is muxed
    //   directly into Lvc_muxed and all downstream CN/VN computation,
    //   producing X outputs throughout the first iteration.
    //
    // FIX: Power-on initialise both registers to 0.  In hardware this
    //   corresponds to a synchronous reset of the Lvc cache before the
    //   first LDPC iteration begins (iter_flag=1 forces Qv anyway, so
    //   the initial 0 is never used for actual decoding).
    // ------------------------------------------------------------------
    initial begin
        mem  = 15'b0;
        dout = 15'b0;
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
