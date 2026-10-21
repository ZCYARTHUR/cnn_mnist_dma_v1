`timescale 1ns/1ps
// Two independent 784-byte frame banks. Only valid ownership is reset.
module input_buffer (
 input wire clk, input wire we, input wire wr_bank,
 input wire [7:0] wr_addr, input wire [31:0] wr_data,
 input wire rd_bank, input wire [9:0] rd_addr,
 output wire signed [7:0] rd_data
);
 (* ram_style="block" *) reg [31:0] mem [0:511];
 reg [31:0] rd_word;
 reg [1:0] rd_byte;
 assign rd_data=rd_word[rd_byte*8+:8];
 always @(posedge clk) begin
   if (we) mem[{wr_bank,wr_addr}] <= wr_data;
   rd_word <= mem[{rd_bank,rd_addr[9:2]}];
   rd_byte <= rd_addr[1:0];
 end
endmodule
