`timescale 1ns/1ps
module tb_cnn;
 parameter integer LANES=4;
 reg clk=0; always #5 clk=~clk;
 reg resetn=0;
 reg [7:0] awaddr=0,araddr=0;
 reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
 wire awready,wready,bvalid,arready,rvalid;
 reg [31:0] wdata=0;
 wire [31:0] rdata;
 wire [1:0] bresp,rresp;
 reg [31:0] txdata=0;
 reg [3:0] txkeep=15;
 reg txvalid=0,txlast=0,rxready=0;
 wire txready,rxvalid,rxlast;
 wire [31:0] rxdata;
 wire [3:0] rxkeep;
 cnn_accel_top #(.LANES(LANES)) dut(clk,resetn,
  awaddr,3'b0,awvalid,awready,wdata,4'hf,wvalid,wready,bresp,bvalid,bready,
  araddr,3'b0,arvalid,arready,rdata,rresp,rvalid,rready,
  txdata,txkeep,txlast,txvalid,txready,rxdata,rxkeep,rxlast,rxvalid,rxready);
 reg [31:0] model[0:1714],images[0:197*64-1],expected[0:640-1];
 string dir;
 integer nframes=4,received=0,wordidx=0,overlapped_writes=0;
 reg stalled=0;
 reg [36:0] held;
 reg [31:0] rd;
 task automatic send_word(input [31:0] d,input bit last,input [3:0] keep=15);
  repeat($urandom_range(0,2)) @(negedge clk);
  txdata=d;txlast=last;txkeep=keep;txvalid=1;
  do @(posedge clk); while(!txready);
  @(negedge clk);txvalid=0;txlast=0;
 endtask
 task automatic read_reg(input [7:0] addr,output [31:0] data,input [1:0] resp=0);
  @(negedge clk);araddr=addr;arvalid=1;
  do @(posedge clk);while(!arready);
  @(negedge clk);arvalid=0;
  wait(rvalid);
  data=rdata;
  repeat(4) begin @(posedge clk); if(!rvalid || rdata!==data || rresp!==resp) $fatal(1,"AXI read stability/response"); end
  @(negedge clk);rready=1;@(posedge clk);@(negedge clk);rready=0;
 endtask
 task automatic write_reg(input [7:0] addr,input [31:0] data,input bit data_first,input [1:0] resp=0);
  fork
   begin
    if(data_first) repeat(5) @(negedge clk);
    @(negedge clk);awaddr=addr;awvalid=1;
    do @(posedge clk);while(!awready);
    @(negedge clk);awvalid=0;
   end
   begin
    if(!data_first) repeat(5) @(negedge clk);
    @(negedge clk);wdata=data;wvalid=1;
    do @(posedge clk);while(!wready);
    @(negedge clk);wvalid=0;
   end
  join
  wait(bvalid);
  repeat(4) begin @(posedge clk);if(!bvalid || bresp!==resp) $fatal(1,"AXI write response");end
  @(negedge clk);bready=1;@(posedge clk);@(negedge clk);bready=0;
 endtask
 always @(negedge clk) rxready=resetn && ($urandom_range(0,3)!=0);
 always @(posedge clk) if(resetn) begin
  if(dut.image_we && (dut.pending[dut.wr_bank] || (dut.core_busy && dut.active_bank==dut.wr_bank)))
   $fatal(1,"Input buffer ownership violation");
  if(dut.image_we && dut.core_busy)overlapped_writes++;
  if(stalled && {rxvalid,rxlast,rxkeep,rxdata}!=={1'b1,held}) $fatal(1,"Output changed during backpressure");
  stalled=rxvalid&&!rxready;
  held={rxlast,rxkeep,rxdata};
  if(rxvalid&&rxready) begin
   if(rxkeep!=15 || rxlast!=(wordidx==11)) $fatal(1,"Bad output packet boundary");
   if(wordidx==0 && rxdata!=32'h434e4e10) $fatal(1,"Bad result magic");
   if(wordidx==1) begin
    if(rxdata==0) $fatal(1,"Zero cycle count");
    $display("LANES=%0d FRAME=%0d CORE_CYCLES=%0d",LANES,received,rxdata);
   end
   if(wordidx>=2 && rxdata!==expected[received*10+wordidx-2])
    $fatal(1,"Logit mismatch frame=%0d class=%0d got=%0d expected=%0d",received,wordidx-2,$signed(rxdata),$signed(expected[received*10+wordidx-2]));
   if(wordidx==11) begin received++;wordidx=0;end else wordidx++;
  end
 end
 initial begin
  if(!$value$plusargs("VECTORS=%s",dir)) dir="vectors";
  if(!$value$plusargs("FRAMES=%d",nframes)) nframes=4;
  if(nframes<1 || nframes>64) $fatal(1,"FRAMES out of range");
  $readmemh({dir,"/model.hex"},model);
  $readmemh({dir,"/images.hex"},images,0,nframes*197-1);
  $readmemh({dir,"/expected.hex"},expected,0,nframes*10-1);
  repeat(8) @(negedge clk);resetn=1;
  read_reg(0,rd);if(rd!=32'h434e4e31) $fatal(1,"ID");
  read_reg(28,rd);if(rd!=LANES) $fatal(1,"LANES register");
  read_reg(3,rd,2);
  write_reg(4,1,0,2); // Invalid register, AW before W.
  write_reg(0,1,1);   // Soft reset, W before AW.
  // Unknown packet, drain until TLAST; error is sticky.
  send_word(32'hdeadbeef,0);
  send_word(0,1);
  read_reg(4,rd);if(!rd[2]) $fatal(1,"Missing packet error");
  write_reg(0,1,0);
  read_reg(4,rd);if(rd!=0) $fatal(1,"Reset did not clear status");
  // Early TLAST in a model invalidates it; reload recovers.
  send_word(32'h434e4e01,0);send_word(0,1);
  read_reg(4,rd);if(rd[0] || !rd[2]) $fatal(1,"Malformed model accepted");
  write_reg(0,1,1);
  for(integer i=0;i<1715;i++) send_word(model[i],i==1714);
  repeat(4) @(negedge clk);
  read_reg(4,rd);if(!rd[0] || rd[2]) $fatal(1,"Model load status");
  // Invalid TKEEP on image does not commit a frame.
  send_word(32'h434e4e02,0);send_word(0,1,3);
  read_reg(4,rd);if(!rd[2]) $fatal(1,"TKEEP validation");
  // A pixel outside [0,127] is rejected and the remainder is drained.
  send_word(32'h434e4e02,0);
  for(integer i=0;i<196;i++)send_word(i==0?32'h80000000:0,i==195);
  // Late TLAST must not create an extra result.
  send_word(32'h434e4e02,0);
  for(integer i=0;i<196;i++)send_word(0,0);
  send_word(0,1);
  for(integer f=0;f<nframes;f++)
   for(integer i=0;i<197;i++) send_word(images[f*197+i],i==196);
  wait(received==nframes);
  repeat(5) @(negedge clk);
  read_reg(8,rd);if(rd!=nframes) $fatal(1,"Frame counter");
  read_reg(20,rd);if(nframes>=3 && rd==0) $fatal(1,"Input backpressure not exercised");
  read_reg(24,rd);if(rd==0) $fatal(1,"Output backpressure not exercised");
  if(nframes>=2 && overlapped_writes==0)$fatal(1,"No image load/compute overlap observed");
  write_reg(0,1,0);
  read_reg(4,rd);if(rd!=0)$fatal(1,"Final reset status");
  read_reg(8,rd);if(rd!=0)$fatal(1,"Final reset frame count");
  $display("PASS: bit-exact CNN, double buffers, randomized stream stalls, AXI-Lite and packet recovery");
  $finish;
 end
 initial begin repeat(10000000) @(posedge clk);$fatal(1,"Simulation timeout");end
endmodule
