`timescale 1ns/1ps
module accumulator #(parameter integer LANES=4) (
 input wire clk, input wire clear, input wire add,
 input wire [LANES*32-1:0] bias, input wire [LANES*16-1:0] products,
 output wire [LANES*32-1:0] sums
);
 genvar g;
 generate for(g=0;g<LANES;g=g+1) begin: lane
   reg signed [31:0] acc;
   always @(posedge clk) begin
     if(clear) acc <= $signed(bias[g*32+:32]);
     else if(add) acc <= acc + {{16{products[g*16+15]}},products[g*16+:16]};
   end
   assign sums[g*32+:32]=acc;
 end endgenerate
endmodule
