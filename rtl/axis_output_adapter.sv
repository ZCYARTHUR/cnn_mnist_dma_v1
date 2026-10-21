`timescale 1ns/1ps
// Snapshot each result; payload is immutable under backpressure.
module axis_output_adapter (
 input wire clk, input wire rst_n, input wire submit,
 input wire [319:0] logits, input wire [31:0] cycles,
 output wire busy, output wire [31:0] tdata,
 output wire [3:0] tkeep, output reg tvalid,
 input wire tready, output wire tlast
);
 reg [383:0] packet;
 reg [3:0] index;
 assign busy=tvalid;
 assign tdata=packet[index*32+:32];
 assign tkeep=4'hf;
 assign tlast=tvalid && index==11;
 always @(posedge clk) begin
   if(!rst_n) begin tvalid<=0; index<=0; packet<=0; end
   else if(submit && !tvalid) begin
     packet<={logits,cycles,32'h434e4e10}; index<=0; tvalid<=1;
   end else if(tvalid && tready) begin
     if(index==11) begin tvalid<=0; index<=0; end
     else index<=index+1;
   end
 end
endmodule
