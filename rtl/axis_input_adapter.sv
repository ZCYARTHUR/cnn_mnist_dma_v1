`timescale 1ns/1ps
// A DMA transfer is one packet, all beats have TKEEP=1111.
// MODEL: magic 434e4e01, shift, 1699 packed weight words, 14 INT32 biases.
// IMAGE: magic 434e4e02, 196 words (784 bytes, each in [0,127]).
module axis_input_adapter (
 input wire clk, input wire rst_n,
 input wire [31:0] tdata, input wire [3:0] tkeep,
 input wire tvalid, output wire tready, input wire tlast,
 input wire model_allowed, input wire frame_allowed,
 output wire weight_we, output wire [10:0] weight_addr,
 output wire bias_we, output wire [3:0] bias_addr,
 output wire image_we, output wire [7:0] image_addr,
 output wire [31:0] data,
 output reg [4:0] shift, output reg model_begin,
 output reg model_commit, output reg image_commit, output reg error,
 output wire loading
);
 localparam HEAD=0, SHIFT=1, MODEL=2, IMAGE=3, DRAIN=4;
 reg [2:0] state;
 reg [10:0] count;
 wire fire=tvalid && tready;
 wire good=fire && tkeep==15;
 wire image_byte_valid=!(tdata[7] || tdata[15] || tdata[23] || tdata[31]);
 assign loading=state!=HEAD;
 assign tready=rst_n && ((state!=HEAD) ||
   ((tdata==32'h434e4e01)?model_allowed:
    (tdata==32'h434e4e02)?frame_allowed:1'b1));
 assign weight_we=good && state==MODEL && count<1699;
 assign weight_addr=count;
 assign bias_we=good && state==MODEL && count>=1699;
 assign bias_addr=4'(count-1699);
 assign image_we=good && state==IMAGE && image_byte_valid;
 assign image_addr=count[7:0];
 assign data=tdata;
 always @(posedge clk) begin
   if(!rst_n) begin state<=HEAD; count<=0; shift<=0; error<=0;
     model_begin<=0; model_commit<=0; image_commit<=0;
   end else begin
     model_begin<=0; model_commit<=0; image_commit<=0;
     if(fire) begin
       if(tkeep!=15) begin error<=1; state<=tlast?HEAD:DRAIN; end
       else case(state)
         HEAD: begin
           count<=0;
           if(tdata==32'h434e4e01) model_begin<=1;
           if(tlast) begin error<=1; state<=HEAD; end
           else if(tdata==32'h434e4e01) state<=SHIFT;
           else if(tdata==32'h434e4e02) state<=IMAGE;
           else begin error<=1; state<=DRAIN; end
         end
         SHIFT: if(tlast || tdata>24) begin error<=1; state<=tlast?HEAD:DRAIN; end
                else begin shift<=tdata[4:0]; state<=MODEL; end
         MODEL: begin
           if(tlast!=(count==1712)) begin error<=1; state<=tlast?HEAD:DRAIN; end
           else if(tlast) begin state<=HEAD; model_commit<=1; end
           else count<=count+1;
         end
         IMAGE: begin
           if(!image_byte_valid || tlast!=(count==195)) begin
             error<=1; state<=tlast?HEAD:DRAIN;
           end else if(tlast) begin state<=HEAD; image_commit<=1; end
           else count<=count+1;
         end
         DRAIN: if(tlast) state<=HEAD;
         default: state<=HEAD;
       endcase
     end
   end
 end
endmodule
