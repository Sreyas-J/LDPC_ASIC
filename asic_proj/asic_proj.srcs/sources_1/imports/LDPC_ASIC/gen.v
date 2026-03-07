

module gen(

input clk,
input reset,
input iter_flag,
input cn_reset,
input cn_sel,
input vn_sel,
output [11:0] cv_list,
output reg q_load
    );
    wire [3:0] bypass_list; // sizes will change
    wire [11:0] edgelist; // sizes will change
    wire [4:0] qv;
    reg [3:0] addr; // sizes will change
    reg [2:0] bypass;
    wire flag_edgelist;
    wire [3:0] addr_edgelist; 
    rom_bypass r1(clk,1'b1,addr_edgelist ,bypass_list);
    rom_edgelist r2(clk,1'b1,addr_edgelist ,edgelist);
    rom_qv r3(clk,1'b1,addr,qv);
    
    reg [8:0] mcv_t_l1[0:11]; // the sizes will change
    reg [8:0] mcv_t_l2[0:11];
    reg [8:0] mcv_t_l3[0:11];
    reg [26:0] mcv_tprev[0:11]; // sizes will change
    wire [26:0] mcv_t_reg[0:11]; // sizes will change
    reg [4:0] qv_list[0:11]; // sizes will change
    reg generate_flag;
    wire [26:0] mcv_t[0:11];
//    reg q_load;
//    wire cv_list[0:11]; // sizes will change
    assign flag_edgelist = (addr==12);
    
    assign addr_edgelist = flag_edgelist ? 0 : addr+1;
    
    always @(*)
    begin
        if(reset) generate_flag = 0;
        
    end
    
    
    always @(posedge clk)
    begin
    
    
        if(reset) begin
            addr <= 0;
            q_load<=1;
        end
        else if(addr == 4'd12) begin
            addr <= 0;
            if(q_load) q_load<=0;
        end
        else addr <= addr + 1;
        
        
       
    
    end
    
//    reg [1:0] i;
    
    integer i;
    
    always @(posedge clk)
    begin
    
    if(reset) begin ///changed reset
        bypass <= 3'b000;

        for(i=0;i<12;i=i+1) begin
            mcv_tprev[i] <= 27'd0;
            mcv_t_l1[i] <= 9'd0;
            mcv_t_l2[i] <= 9'd0;
            mcv_t_l3[i] <= 9'd0;
            qv_list[i] <= 5'd0;
        end
    end
    
    else if(q_load) qv_list[addr] <= qv;
    
    else begin
    
        if(bypass_list == edgelist[11:8]) bypass <= 3'b100;
        else if(bypass_list == edgelist[7:4]) bypass <= 3'b010;
        else if(bypass_list == edgelist[3:0]) bypass <= 3'b001;
        else bypass = 3'b000;
        {mcv_t_l1[addr], mcv_t_l2[addr], mcv_t_l3[addr]} <= mcv_t[addr];
        mcv_tprev[addr] <= {mcv_t_l1[edgelist[11:8]], mcv_t_l2[edgelist[7:4]], mcv_t_l3[edgelist[3:0]]} ;
        
        
    
    
    
        generate_flag = 1'b1;
    end
    
   end
    
    genvar j;
    
    generate
    
    for(j =0; j< 12;j = j+ 1)
    begin
    
        PE pe(clk, iter_flag, cn_reset, cn_sel, vn_sel, bypass, mcv_tprev[j], qv_list[j], mcv_t[j], cv_list[j] );
    
    
    end
    
    
    endgenerate
    
    
    
endmodule



