

module gen(

input clk,
input reset,
input iter_flag,
input cn_reset,
input cn_sel,
input vn_sel,
output [11:0] cv_list
//output reg q_load
    );
//    reg [3:0] bypass_list [0:11]; // sizes will change
//    reg [11:0] edgelist [0:11]; // sizes will change
//    wire [4:0] qv;
    reg [3:0] addr; // sizes will change
    reg [2:0] bypass [0:11];
    wire flag_edgelist;
    wire [3:0] addr_edgelist; 
//    rom_bypass r1(clk,1'b1,addr_edgelist ,bypass_list);
//    rom_edgelist r2(clk,1'b1,addr_edgelist ,edgelist);
//    rom_qv r3(clk,1'b1,addr,qv);
    
//    reg [8:0] mcv_t_l1[0:11]; // the sizes will change
//    reg [8:0] mcv_t_l2[0:11];
//    reg [8:0] mcv_t_l3[0:11];
    reg [26:0] mcv_tprev[0:11]; // sizes will change
//    wire [26:0] mcv_t_reg[0:11]; // sizes will change
//    wire [4:0] qv_list[0:11]; // sizes will change
    reg generate_flag;
    wire [26:0] mcv_t[0:11];
//    reg q_load;
//    wire cv_list[0:11]; // sizes will change
//    assign flag_edgelist = (addr==12);
    
//    assign addr_edgelist = flag_edgelist ? 0 : addr+1;
    
    
//    always @(*) begin
////        if (en) begin
////            case (addr)
//                // Mapping the provided arrays to 12-bit hex values
//                edgelist[0] = 12'h238; // [2, 3, 8]
//                edgelist[1] = 12'h046; // [0, 4, 6]
//                edgelist[2] = 12'h157; // [1, 5, 7]
//                edgelist[3] = 12'h046; // [0, 4, 6]
//                edgelist[4] = 12'h157; // [1, 5, 7]
//                edgelist[5] = 12'h238; // [2, 3, 8]
//                edgelist[6] = 12'h037; // [0, 3, 7]
//                edgelist[7] = 12'h148; // [1, 4, 8]
//                edgelist[8] = 12'h256; // [2, 5, 6]
//                edgelist[9] = 12'h138; // [1, 3, 8]
//                edgelist[10] = 12'h246; // [2, 4, 6]
//                edgelist[11] = 12'h057; // [0, 5, 7]
                
//                // Safety net for unused addresses (12-15)
////                default: data_out <= 12'h000; 
////            endcase
////        end
//    end
    
    
    
//    always @(*) begin
////        if (en) begin
////            case (addr)
//                bypass_list[0] = 4'h3; // [3]
//                bypass_list[1] = 4'h4; // [4]
//                bypass_list[2] = 4'h5; // [5]
//                bypass_list[3] = 4'hF; // [] -> filled with 15
//                bypass_list[4] = 4'hF; // [] -> filled with 15
//                bypass_list[5] = 4'hF; // [] -> filled with 15
//                bypass_list[6] = 4'h0; // [0]
//                bypass_list[7] = 4'h1; // [1]
//                bypass_list[8] = 4'h2; // [2]
//                bypass_list[9] = 4'hF; // [] -> filled with 15
//                bypass_list[10] = 4'hF; // [] -> filled with 15
//                bypass_list[11] = 4'hF; // [] -> filled with 15
                
//                // Safety net for unused addresses (12-15)
////                default: data_out <= 4'h0; 
////            endcase
////        end
//    end
    

////    always @(*) begin

                
//              assign  qv_list[0] = 5'h07; // e.g., strong '0' (+7)
//               assign qv_list[1] = 5'h1A; // e.g., moderate '1' (-6)
//               assign qv_list[2] = 5'h02; // e.g., weak '0' (+2)
//               assign qv_list[3] = 5'h1F; // e.g., very weak '1' (-1)
//               assign qv_list[4] = 5'h0C; // (+12)
//               assign qv_list[5] = 5'h14; // (-12)
//               assign qv_list[6] = 5'h00; // Complete uncertainty (0)
//               assign qv_list[7] = 5'h0E; // (+14)
//               assign qv_list[8] = 5'h11; // (-15)
//               assign qv_list[9] = 5'h05; // (+5)
//               assign qv_list[10] = 5'h18; // (-8)
//               assign qv_list[11] = 5'h09; // (+9)

////    end


// declarations
reg [11:0] edgelist [0:11];
reg [3:0]  bypass_list [0:11];
reg [4:0]  qv_list [0:11];

    
    initial begin
        // edgelist table
        edgelist[0]  = 12'h238;
        edgelist[1]  = 12'h046;
        edgelist[2]  = 12'h157;
        edgelist[3]  = 12'h046;
        edgelist[4]  = 12'h157;
        edgelist[5]  = 12'h238;
        edgelist[6]  = 12'h037;
        edgelist[7]  = 12'h148;
        edgelist[8]  = 12'h256;
        edgelist[9]  = 12'h138;
        edgelist[10] = 12'h246;
        edgelist[11] = 12'h057;
    
        // bypass table
        bypass_list[0]  = 4'h3;
        bypass_list[1]  = 4'h4;
        bypass_list[2]  = 4'h5;
        bypass_list[3]  = 4'hF;
        bypass_list[4]  = 4'hF;
        bypass_list[5]  = 4'hF;
        bypass_list[6]  = 4'h0;
        bypass_list[7]  = 4'h1;
        bypass_list[8]  = 4'h2;
        bypass_list[9]  = 4'hF;
        bypass_list[10] = 4'hF;
        bypass_list[11] = 4'hF;
    
        // qv table
//        qv_list[0]  = 5'h07;
//        qv_list[1]  = 5'h1A;
//        qv_list[2]  = 5'h02;
//        qv_list[3]  = 5'h1F;
//        qv_list[4]  = 5'h0C;
//        qv_list[5]  = 5'h14;
//        qv_list[6]  = 5'h00;
//        qv_list[7]  = 5'h0E;
//        qv_list[8]  = 5'h11;
//        qv_list[9]  = 5'h05;
//        qv_list[10] = 5'h18;
//        qv_list[11] = 5'h09;

        qv_list[0]  = 5'h07;
        qv_list[1]  = 5'h1A;
        qv_list[2]  = 5'h02;
        qv_list[3]  = 5'h1F;
        qv_list[4]  = 5'h0C;
        qv_list[5]  = 5'h14;
        qv_list[6]  = 5'h00;
        qv_list[7]  = 5'h0E;
        qv_list[8]  = 5'h11;
        qv_list[9]  = 5'h05;
        qv_list[10] = 5'h18;
        qv_list[11] = 5'h09;
    end
    
    
    integer a;
//    always@(*) begin
     
//        for(a =0; a< 12;a = a + 1)
//        begin
//            if(bypass_list[a] == edgelist[a][11:8]) bypass[a] = 3'b100;
//        else if(bypass_list[a] == edgelist[a][7:4]) bypass[a] = 3'b010;
//        else if(bypass_list[a] == edgelist[a][3:0]) bypass[a] = 3'b001;
//        else bypass[a] = 3'b000;
//        {mcv_t_l1[a], mcv_t_l2[a], mcv_t_l3[a]} = mcv_t[a];
////        mcv_tprev[a] = {mcv_t_l1[edgelist[a][11:8]], mcv_t_l2[edgelist[a][7:4]], mcv_t_l3[edgelist[a][3:0]]} ;
//        end
     
//    end
always @(*) begin
    for (a = 0; a < 12; a = a + 1) begin
        // compute bypass (unchanged)
        if (bypass_list[a] == edgelist[a][11:8]) bypass[a] = 3'b100;
        else if (bypass_list[a] == edgelist[a][7:4]) bypass[a] = 3'b010;
        else if (bypass_list[a] == edgelist[a][3:0]) bypass[a] = 3'b001;
        else bypass[a] = 3'b000;

        // read parts of mcv_t from the indices specified in edgelist
        mcv_tprev[a] = {
            mcv_t[ edgelist[a][11:8] ][26:18], // top 9 bits
            mcv_t[ edgelist[a][7:4]  ][17:9],
            mcv_t[ edgelist[a][3:0]  ][8:0]
        };
    end
end    
    
    
    genvar j;
    
    generate
    
    for(j =0; j< 12;j = j+ 1)
    begin
    
        PE pe(clk, iter_flag, cn_reset, cn_sel, vn_sel, bypass[j], mcv_tprev[j], qv_list[j], mcv_t[j], cv_list[j] );
        
    
    end
    
    
    endgenerate
    
    
    
endmodule



