`timescale 1ns/1ps
module perf_counters (
 input wire clk, input wire rst_n, input wire start, input wire busy,
 input wire done, input wire computing, input wire input_stall,
 input wire output_stall,
 output reg [31:0] last_cycles, output reg [31:0] frames,
 output reg [31:0] mac_clocks, output reg [31:0] stall_in,
 output reg [31:0] stall_out, output wire [31:0] current_cycles
);
 reg [31:0] running;
 assign current_cycles=running;
 always @(posedge clk) begin
   if(!rst_n) begin running<=0; last_cycles<=0; frames<=0;
     mac_clocks<=0; stall_in<=0; stall_out<=0;
   end else begin
     if(start) running<=0;
     else if(busy) running<=running+1;
     if(done) begin last_cycles<=running; frames<=frames+1; end
     if(computing) mac_clocks<=mac_clocks+1;
     if(input_stall) stall_in<=stall_in+1;
     if(output_stall) stall_out<=stall_out+1;
   end
 end
endmodule
