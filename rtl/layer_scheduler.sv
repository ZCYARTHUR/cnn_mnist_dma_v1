`timescale 1ns/1ps
// Fixed topology: Conv(1->4,3x3 valid), ReLU, MaxPool2, FC(676->10).
// Three clocks per tap: synchronous read, registered multiply, accumulate.
// LANES changes FC output parallelism; convolution always uses 4 lanes.
module layer_scheduler #(parameter integer LANES=4) (
 input wire clk, input wire rst_n, input wire start,
 input wire [447:0] biases, input wire [4:0] shift,
 output wire [9:0] pixel_addr, input wire signed [7:0] pixel,
 output reg [LANES*13-1:0] weight_addr,
 input wire [LANES*8-1:0] weights,
 output reg busy, output reg done, output reg [319:0] logits,
 output wire computing, output wire [3:0] stage
);
 localparam IDLE=0, INIT=1, READ=2, MUL=3, ADD=4, STORE=5, POOL=6;
 reg [3:0] state;
 reg fc;
 reg [7:0] cell_idx;
 reg [1:0] sub_idx;
 reg [9:0] tap;
 reg [4:0] group_base;
 wire [LANES*16-1:0] products;
 wire [LANES*32-1:0] sums;
 reg [LANES*32-1:0] init_bias;
 wire [31:0] quantized, pooled;
 // Channel banks allow simultaneous writes of four pooled results.
 (* ram_style="block" *) reg [7:0] features0[0:168];
 (* ram_style="block" *) reg [7:0] features1[0:168];
 (* ram_style="block" *) reg [7:0] features2[0:168];
 (* ram_style="block" *) reg [7:0] features3[0:168];
 reg [7:0] feature;
 integer i;
 initial begin
   if(LANES!=4 && LANES!=8 && LANES!=16) $error("LANES must be 4,8,16");
 end
 assign stage=state;
 assign computing=(state==ADD);
 window_generator window_addr(cell_idx,sub_idx,tap[3:0],pixel_addr);
 mac_array #(.LANES(LANES)) mac(clk,fc?$signed(feature):pixel,weights,products);
 accumulator #(.LANES(LANES)) accum(clk,state==INIT,state==ADD,init_bias,products,sums);
 genvar g;
 generate for(g=0;g<4;g=g+1) begin: quant
   requantize rq($signed(sums[g*32+:32]),shift,quantized[g*8+:8]);
 end endgenerate
 activation_pool pooling(clk,state==STORE && !fc,sub_idx==0,quantized,pooled);
 always @* begin
   weight_addr=0; init_bias=0;
   for(integer lane=0;lane<LANES;lane=lane+1) begin
     if(fc && int'(group_base)+lane<10) begin
       weight_addr[lane*13+:13]=13'(36+(int'(group_base)+lane)*676+int'(tap));
       init_bias[lane*32+:32]=biases[(4+int'(group_base)+lane)*32+:32];
     end else if(!fc && lane<4) begin
       weight_addr[lane*13+:13]=13'(lane*9+int'(tap));
       init_bias[lane*32+:32]=biases[lane*32+:32];
     end
   end
 end
 always @(posedge clk) begin
   case(tap/169)
    0: feature<=features0[tap%169];
    1: feature<=features1[tap%169];
    2: feature<=features2[tap%169];
    default: feature<=features3[tap%169];
   endcase
   if(state==POOL) begin
     features0[cell_idx]<=pooled[7:0];
     features1[cell_idx]<=pooled[15:8];
     features2[cell_idx]<=pooled[23:16];
     features3[cell_idx]<=pooled[31:24];
   end
   if(!rst_n) begin
     state<=IDLE; fc<=0; busy<=0; done<=0; logits<=0;
     cell_idx<=0; sub_idx<=0; tap<=0; group_base<=0;
   end else begin
     done<=0;
     case(state)
       IDLE: if(start) begin
         busy<=1; fc<=0; cell_idx<=0; sub_idx<=0; tap<=0;
         group_base<=0; state<=INIT;
       end
       INIT: state<=READ;
       READ: state<=MUL;
       MUL: state<=ADD;
       ADD: if((!fc && tap==8) || (fc && tap==675)) state<=STORE;
            else begin tap<=tap+1; state<=READ; end
       STORE: begin
         tap<=0;
         if(fc) begin
           for(i=0;i<LANES;i=i+1)
             if(int'(group_base)+i<10) logits[(int'(group_base)+i)*32+:32]<=sums[i*32+:32];
           if(int'(group_base)+LANES>=10) begin busy<=0; done<=1; state<=IDLE; end
           else begin group_base<=5'(int'(group_base)+LANES); state<=INIT; end
         end else if(sub_idx==3) state<=POOL;
         else begin sub_idx<=sub_idx+1; state<=INIT; end
       end
       POOL: begin
         sub_idx<=0;
         if(cell_idx==168) begin fc<=1; group_base<=0; end
         else cell_idx<=cell_idx+1;
         state<=INIT;
       end
       default: state<=IDLE;
     endcase
   end
 end
endmodule
