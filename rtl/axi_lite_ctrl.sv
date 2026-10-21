`timescale 1ns/1ps
// Independent address/data capture; one read and one write outstanding.
module axi_lite_ctrl (
 input wire clk, input wire rst_n,
 input wire [7:0] awaddr, input wire awvalid, output wire awready,
 input wire [31:0] wdata, input wire [3:0] wstrb,
 input wire wvalid, output wire wready,
 output reg [1:0] bresp, output reg bvalid, input wire bready,
 input wire [7:0] araddr, input wire arvalid, output wire arready,
 output reg [31:0] rdata, output reg [1:0] rresp,
 output reg rvalid, input wire rready,
 input wire [255:0] registers, output reg soft_reset
);
 reg ap,wp;
 reg [7:0] a;
 reg [31:0] d;
 reg [3:0] strb;
 assign awready=rst_n && !ap && !bvalid;
 assign wready=rst_n && !wp && !bvalid;
 assign arready=rst_n && !rvalid;
 always @(posedge clk) begin
   if(!rst_n) begin
     ap<=0; wp<=0; a<=0; d<=0; strb<=0;
     bvalid<=0; bresp<=0; rvalid<=0; rresp<=0; rdata<=0; soft_reset<=0;
   end else begin
     soft_reset<=0;
     if(bvalid && bready) bvalid<=0;
     if(rvalid && rready) rvalid<=0;
     if(awvalid && awready) begin ap<=1; a<=awaddr; end
     if(wvalid && wready) begin wp<=1; d<=wdata; strb<=wstrb; end
     if(ap && wp && !bvalid) begin
       ap<=0; wp<=0; bvalid<=1; bresp<=0;
       if(a!=0) bresp<=2;
       else if(strb[0] && d[0]) soft_reset<=1;
     end
     if(arvalid && arready) begin
       rvalid<=1; rdata<=0; rresp<=0;
       if(araddr[1:0]!=0 || araddr>28) rresp<=2;
       else rdata<=registers[araddr[4:2]*32+:32];
     end
   end
 end
endmodule
