`timescale 1ns/1ps
// C = A * B. Row-major packed buses: element 0 is in the least significant bits.
// Pulse start for one cycle when busy=0. Inputs are captured on acceptance.
// Four signed multipliers; one output row takes four compute clocks.
// done pulses on the 16th compute clock; sample c_flat on done. Rows update during busy.
module matmul4_int8 (
    input wire clk, input wire rst_n, input wire start,
    input wire [127:0] a_flat, input wire [127:0] b_flat,
    output reg busy, output reg done, output reg [511:0] c_flat
);
    reg signed [7:0] a [0:15];
    reg signed [7:0] b [0:15];
    reg signed [31:0] acc [0:3];
    reg [1:0] row_idx, k_idx;
    wire signed [15:0] product [0:3];
    wire signed [31:0] sum [0:3];
    genvar g;
    generate for (g=0; g<4; g=g+1) begin: lanes
        assign product[g] = a[{row_idx,k_idx}] * b[k_idx*4+g];
        assign sum[g] = acc[g] + {{16{product[g][15]}},product[g]};
    end endgenerate
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; c_flat <= 0;
            row_idx <= 0; k_idx <= 0;
            for (i=0; i<4; i=i+1) acc[i] <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                if (start) begin
                    for (i=0; i<16; i=i+1) begin
                        a[i] <= a_flat[i*8 +: 8]; b[i] <= b_flat[i*8 +: 8];
                    end
                    for (i=0; i<4; i=i+1) acc[i] <= 0;
                    row_idx <= 0; k_idx <= 0; busy <= 1;
                end
            end else begin
                for (i=0; i<4; i=i+1) begin
                    if (k_idx==3) begin
                        c_flat[(row_idx*4+i)*32 +: 32] <= sum[i];
                        acc[i] <= 0;
                    end else acc[i] <= sum[i];
                end
                if (k_idx==3) begin
                    k_idx <= 0;
                    if (row_idx==3) begin busy <= 0; done <= 1; end
                    else row_idx <= row_idx+1'b1;
                end else k_idx <= k_idx+1'b1;
            end
        end
    end
endmodule
