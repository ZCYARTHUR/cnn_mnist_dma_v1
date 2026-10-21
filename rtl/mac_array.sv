`timescale 1ns/1ps
module mac_array #(parameter integer LANES=4) (
 input wire clk, input wire signed [7:0] activation,
 input wire [LANES*8-1:0] weights,
 output wire [LANES*16-1:0] products
);
 genvar g;
 generate for(g=0;g<LANES;g=g+1) begin: pe
   (* use_dsp="yes" *) reg signed [15:0] p;
   always @(posedge clk) p <= activation*$signed(weights[g*8+:8]);
   assign products[g*16+:16]=p;
 end endgenerate
endmodule
