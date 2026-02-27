

module gen(

input clk,
input reset,
input iter_flag,
input cn_reset,
input cn_sel,
input vn_sel
    );
    wire [3:0] bypass_list; // sizes will change
    wire [11:0] edgelist; // sizes will change
    wire [4:0] qv;
    reg [3:0] addr; // sizes will change
    reg [2:0] bypass;
    
    rom_bypass r1(clk,1'b1,addr,bypass_list);
    rom_edgelist r2(clk,1'b1,addr,edgelist);
    rom_qv r3(clk,1'b1,addr,qv);
    
    wire [8:0] mcv_t_l1[0:11]; // the sizes will change
    wire [8:0] mcv_t_l2[0:11];
    wire [8:0] mcv_t_l3[0:11];
    reg [26:0] mcv_tprev[0:11]; // sizes will change
    reg [26:0] mcv_t_reg[0:11]; // sizes will change
    reg [4:0] qv_list[0:11]; // sizes will change
    reg generate_flag;
    wire [26:0] mcv_t[0:11];
    wire cv_list[0:11]; // sizes will change
    
    
    always @(*)
    begin
        if(reset) generate_flag = 0;
    end
    
    
    always @(posedge clk)
    begin
    
        if(reset) addr <= 0;
        else if(addr == 4'd12) addr <= 0;
        else addr <= addr + 1;
       
    
    end
    
    reg [1:0] i;
    always @(posedge clk)
    begin
    
    for(i=0; i<3; i= i+ 1)
    begin
        if(bypass_list == edgelist[11:8]) bypass = 3'b100;
        else if(bypass_list == edgelist[7:4]) bypass = 3'b010;
        else if(bypass_list == edgelist[3:0]) bypass = 3'b001;
        else bypass = 3'b000;
        mcv_tprev[i] = {mcv_t_l1[edgelist[11:8]], mcv_t_l2[edgelist[7:4]], mcv_t_l3[edgelist[3:0]]};
        mcv_t_reg[i] = {mcv_t_l1[i], mcv_t_l2[i], mcv_t_l3[i]};
        qv_list[i] = qv;
    end
    
    generate_flag = 1'b1;
    
    
    end
    
   genvar k;
   generate
   
   for(k = 0; k<12; k = k+ 1)
   begin
   assign  mcv_t[k] = mcv_t_reg[k];
   end
   
   endgenerate
    
    genvar j;
    
    generate
    
    for(j =0; j< 12;j = j+ 1)
    begin
    
        PE pe(clk, iter_flag, cn_reset, cn_sel, vn_sel, bypass, mcv_tprev[j], qv_list[j], mcv_t[j], cv_list[j] );
    
    
    end
    
    
    endgenerate
    
    
    
endmodule
