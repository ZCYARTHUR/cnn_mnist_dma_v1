`timescale 1ns/1ps
module activation_pool (
 input wire clk, input wire sample, input wire first,
 input wire [31:0] values, output wire [31:0] pooled
);
 genvar g;
 generate for(g=0;g<4;g=g+1) begin: channel
   reg [7:0] maximum;
   always @(posedge clk)
     if(sample && (first || values[g*8+:8]>maximum))
       maximum<=values[g*8+:8];
   assign pooled[g*8+:8]=maximum;
 end endgenerate
endmodule
