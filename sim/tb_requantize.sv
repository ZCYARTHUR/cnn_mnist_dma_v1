`timescale 1ns/1ps
module tb_requantize;
 reg signed [31:0] value;
 reg [4:0] shift;
 wire [7:0] result;
 requantize dut(value,shift,result);
 longint signed expected;
 task automatic check(input integer signed v,input integer s);
  value=v;shift=5'(s);#1;
  if(v<=0)expected=0;
  else if(s==0)expected=longint'(v);
  else expected=(longint'(v)+(64'sd1<<(s-1)))/(64'sd1<<s);
  if(expected>127)expected=127;
  if(result!==8'(expected))$fatal(1,"Requantize v=%0d shift=%0d got=%0d exp=%0d",v,s,result,expected);
 endtask
 initial begin
  for(integer s=0;s<=24;s++)begin
   check(-2147483647,s);check(-1,s);check(0,s);check(1,s);
   check(126,s);check(127,s);check(128,s);check(2147483647,s);
   if(s>0)begin check((1<<(s-1))-1,s);check(1<<(s-1),s);check((1<<(s-1))+1,s);end
   for(integer i=0;i<100;i++)check($signed($urandom),s);
  end
  $display("PASS: requantize shifts 0..24, ties, saturation, INT32 extrema");$finish;
 end
endmodule
