`timescale 1ns/1ps
// Addresses a 3x3 window from a cached frame (no full im2col materialization).
// cell_idx identifies a 2x2 pooled cell; sub_idx selects its convolution pixel.
module window_generator (
 input wire [7:0] cell_idx, input wire [1:0] sub_idx,
 input wire [3:0] tap_idx, output wire [9:0] pixel_addr
);
 assign pixel_addr = 10'(((int'(cell_idx)/13)*2 + int'(sub_idx[1]) + int'(tap_idx)/3)*28
                   + (int'(cell_idx)%13)*2 + int'(sub_idx[0]) + int'(tap_idx)%3);
endmodule
