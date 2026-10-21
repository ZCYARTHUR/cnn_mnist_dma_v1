`timescale 1ns/1ps
module cnn_accel_top #(parameter integer LANES=4)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK",
 X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn" *)
 input wire aclk,
 (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST",
 X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input wire aresetn,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER="PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
 input wire [7:0] s_axi_awaddr,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
 input wire [2:0] s_axi_awprot,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
 input wire  s_axi_awvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
 output wire  s_axi_awready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
 input wire [31:0] s_axi_wdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
 input wire [3:0] s_axi_wstrb,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
 input wire  s_axi_wvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
 output wire  s_axi_wready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
 output wire [1:0] s_axi_bresp,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
 output wire  s_axi_bvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
 input wire  s_axi_bready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
 input wire [7:0] s_axi_araddr,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
 input wire [2:0] s_axi_arprot,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
 input wire  s_axi_arvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
 output wire  s_axi_arready,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
 output wire [31:0] s_axi_rdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
 output wire [1:0] s_axi_rresp,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
 output wire  s_axi_rvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
 input wire  s_axi_rready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TDATA", X_INTERFACE_PARAMETER="TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1" *)
 input wire [31:0] s_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *)
 input wire [3:0] s_axis_tkeep,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
 input wire  s_axis_tlast,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
 input wire  s_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
 output wire  s_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA", X_INTERFACE_PARAMETER="TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1" *)
 output wire [31:0] m_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
 output wire [3:0] m_axis_tkeep,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
 output wire  m_axis_tlast,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
 output wire  m_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
 input wire  m_axis_tready
);
 wire soft_reset;
 wire rst_n=aresetn && !soft_reset;
 wire [255:0] registers;
 wire [31:0] last_cycles,frames,mac_clocks,stall_in,stall_out,current_cycles;
 wire core_busy,core_done,computing,output_busy,loading;
 wire [3:0] stage;
 wire model_begin,model_commit,image_commit,error;
 wire weight_we,bias_we,image_we;
 wire [10:0] weight_wr_addr;
 wire [3:0] bias_wr_addr;
 wire [7:0] image_wr_addr;
 wire [31:0] data;
 wire [4:0] shift;
 reg [447:0] biases;
 reg model_valid,wr_bank,next_bank,active_bank;
 reg [1:0] pending;
 wire frame_allowed=model_valid && !pending[wr_bank] &&
                       !(core_busy && active_bank==wr_bank) && !image_commit;
 wire model_allowed=!core_busy && !core_done && !output_busy && pending==0 && !image_commit;
 // Commit pulses take one cycle to propagate, so guard admission on them too.
 wire start=model_valid && pending[next_bank] && !core_busy && !core_done && !output_busy;
 wire [9:0] pixel_addr;
 wire signed [7:0] pixel;
 wire [LANES*13-1:0] weight_addr;
 wire [LANES*8-1:0] weights;
 wire [319:0] logits;
 assign registers={32'(LANES),stall_out,stall_in,mac_clocks,last_cycles,frames,
   {23'b0,stage,pending,error,core_busy,model_valid},32'h434e4e31};
 axi_lite_ctrl ctrl(aclk,aresetn,s_axi_awaddr,s_axi_awvalid,s_axi_awready,
   s_axi_wdata,s_axi_wstrb,s_axi_wvalid,s_axi_wready,s_axi_bresp,s_axi_bvalid,s_axi_bready,
   s_axi_araddr,s_axi_arvalid,s_axi_arready,s_axi_rdata,s_axi_rresp,s_axi_rvalid,s_axi_rready,
   registers,soft_reset);
 axis_input_adapter rx(aclk,rst_n,s_axis_tdata,s_axis_tkeep,s_axis_tvalid,s_axis_tready,
   s_axis_tlast,model_allowed,frame_allowed,weight_we,weight_wr_addr,bias_we,bias_wr_addr,
   image_we,image_wr_addr,data,shift,model_begin,model_commit,image_commit,error,loading);
 input_buffer images(aclk,image_we,wr_bank,image_wr_addr,data,active_bank,pixel_addr,pixel);
 weight_buffer #(.LANES(LANES)) weights_mem(aclk,weight_we,weight_wr_addr,data,weight_addr,weights);
 layer_scheduler #(.LANES(LANES)) core(aclk,rst_n,start,biases,shift,pixel_addr,pixel,
   weight_addr,weights,core_busy,core_done,logits,computing,stage);
 axis_output_adapter tx(aclk,rst_n,core_done,logits,current_cycles,output_busy,
   m_axis_tdata,m_axis_tkeep,m_axis_tvalid,m_axis_tready,m_axis_tlast);
 perf_counters counters(aclk,rst_n,start,core_busy,core_done,computing,
   s_axis_tvalid && !s_axis_tready,m_axis_tvalid && !m_axis_tready,
   last_cycles,frames,mac_clocks,stall_in,stall_out,current_cycles);
 always @(posedge aclk) begin
   if(!rst_n) begin
     model_valid<=0; wr_bank<=0; next_bank<=0; active_bank<=0; pending<=0; biases<=0;
   end else begin
     if(model_begin) model_valid<=0;
     if(model_commit) model_valid<=1;
     if(bias_we) biases[bias_wr_addr*32+:32]<=data;
     if(image_commit) begin pending[wr_bank]<=1; wr_bank<=~wr_bank; end
     if(start) begin
       pending[next_bank]<=0; active_bank<=next_bank; next_bank<=~next_bank;
     end
   end
 end
endmodule
