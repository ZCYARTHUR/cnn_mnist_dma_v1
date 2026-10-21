`timescale 1ns/1ps
// One outstanding write and read; independent AW/W capture; registered responses.
module matmul_axi(
 
 (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn" *)
 input wire s_axi_aclk, 
 (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
 input wire s_axi_aresetn,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, READ_WRITE_MODE READ_WRITE, HAS_PROT 1, HAS_WSTRB 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
 input wire [11:0] s_axi_awaddr, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
 input wire [2:0] s_axi_awprot,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
 input wire s_axi_awvalid, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
 output wire s_axi_awready,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
 input wire [31:0] s_axi_wdata, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
 input wire [3:0] s_axi_wstrb,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
 input wire s_axi_wvalid, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
 output wire s_axi_wready,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
 output reg [1:0] s_axi_bresp, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
 output reg s_axi_bvalid, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
 input wire s_axi_bready,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
 input wire [11:0] s_axi_araddr, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
 input wire [2:0] s_axi_arprot,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
 input wire s_axi_arvalid, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
 output wire s_axi_arready,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
 output reg [31:0] s_axi_rdata, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
 output reg [1:0] s_axi_rresp,
 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
 output reg s_axi_rvalid, 
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
 input wire s_axi_rready
);
 reg aw_pending,w_pending;
 reg [11:0] awaddr;
 reg [31:0] wdata;
 reg [3:0] wstrb;
 reg [127:0] a_buf,b_buf;
 reg [511:0] result_buf;
 reg start_core,active,done_sticky;
 wire busy_core,done_core;
 wire [511:0] c_core;
 assign s_axi_awready=s_axi_aresetn && !aw_pending && !s_axi_bvalid;
 assign s_axi_wready=s_axi_aresetn && !w_pending && !s_axi_bvalid;
 assign s_axi_arready=s_axi_aresetn && !s_axi_rvalid;
 matmul4_int8 core(.clk(s_axi_aclk),.rst_n(s_axi_aresetn),.start(start_core),
 .a_flat(a_buf),.b_flat(b_buf),.busy(busy_core),.done(done_core),.c_flat(c_core));
 integer n;
 always @(posedge s_axi_aclk) begin
   if(!s_axi_aresetn) begin
     aw_pending<=0; w_pending<=0; awaddr<=0; wdata<=0; wstrb<=0;
     s_axi_bvalid<=0; s_axi_bresp<=0;
     s_axi_rvalid<=0; s_axi_rresp<=0; s_axi_rdata<=0;
     a_buf<=0; b_buf<=0; result_buf<=0;
     start_core<=0; active<=0; done_sticky<=0;
   end else begin
     start_core<=0;
     if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
     if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
     if(s_axi_awvalid && s_axi_awready) begin aw_pending<=1; awaddr<=s_axi_awaddr; end
     if(s_axi_wvalid && s_axi_wready) begin w_pending<=1; wdata<=s_axi_wdata; wstrb<=s_axi_wstrb; end
     if(aw_pending && w_pending && !s_axi_bvalid) begin
       aw_pending<=0; w_pending<=0; s_axi_bvalid<=1; s_axi_bresp<=0;
       if(awaddr[1:0]!=0) s_axi_bresp<=2;
       else if(awaddr==12'h000) begin
         if(wstrb[0]) begin
           if(wdata[0] && active) s_axi_bresp<=2;
           else begin
             if(wdata[1]) done_sticky<=0;
             if(wdata[0]) begin start_core<=1; active<=1; done_sticky<=0; end
           end
         end
       end else if((awaddr>=12'h010 && awaddr<=12'h01c) ||
                   (awaddr>=12'h020 && awaddr<=12'h02c)) begin
         if(active) s_axi_bresp<=2;
         else for(n=0;n<4;n=n+1) if(wstrb[n]) begin
           if(awaddr<12'h020) a_buf[(awaddr-12'h010)*8+n*8 +:8]<=wdata[n*8 +:8];
           else b_buf[(awaddr-12'h020)*8+n*8 +:8]<=wdata[n*8 +:8];
         end
       end else s_axi_bresp<=2;
     end
     // Completion wins over a simultaneous clear; snapshot is atomic.
     if(done_core) begin result_buf<=c_core; active<=0; done_sticky<=1; end
     if(s_axi_arvalid && s_axi_arready) begin
       s_axi_rvalid<=1; s_axi_rresp<=0; s_axi_rdata<=0;
       if(s_axi_araddr[1:0]!=0) s_axi_rresp<=2;
       else if(s_axi_araddr==12'h000) s_axi_rdata<=0;
       else if(s_axi_araddr==12'h004) s_axi_rdata<={30'b0,done_sticky,active};
       else if(s_axi_araddr==12'h008) s_axi_rdata<=32'h4d4d0002;
       else if(s_axi_araddr>=12'h010 && s_axi_araddr<=12'h01c)
         s_axi_rdata<=a_buf[(s_axi_araddr-12'h010)*8 +:32];
       else if(s_axi_araddr>=12'h020 && s_axi_araddr<=12'h02c)
         s_axi_rdata<=b_buf[(s_axi_araddr-12'h020)*8 +:32];
       else if(s_axi_araddr>=12'h040 && s_axi_araddr<=12'h07c)
         s_axi_rdata<=result_buf[(s_axi_araddr-12'h040)*8 +:32];
       else s_axi_rresp<=2;
     end
   end
 end
endmodule
