`timescale 1ns/1ps
// Replicated read banks trade BRAM capacity for LANES independent reads.
// All replicas receive the same packed write; no multiported RAM assumption.
module weight_buffer #(parameter integer LANES=4) (
 input wire clk, input wire we, input wire [10:0] wr_addr,
 input wire [31:0] wr_data,
 input wire [LANES*13-1:0] rd_addr,
 output wire [LANES*8-1:0] rd_data
);
 genvar g;
 generate for(g=0;g<LANES;g=g+1) begin: banks
   (* ram_style="block" *) reg [31:0] mem [0:1698];
   wire [12:0] a = rd_addr[g*13+:13];
   reg [31:0] rd_word;
   reg [1:0] rd_byte;
   always @(posedge clk) begin
     if(we) mem[wr_addr] <= wr_data;
     rd_word <= mem[a[12:2]];
     rd_byte <= a[1:0];
   end
   assign rd_data[g*8+:8]=rd_word[rd_byte*8+:8];
 end endgenerate
endmodule
