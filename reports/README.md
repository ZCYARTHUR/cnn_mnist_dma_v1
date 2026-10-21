# 验证记录

- `trained_lanes*.log`：每种配置16张真实MNIST的RTL逐位比对。
- `synthetic_lanes*.log`：每种配置4张零值、最大值及随机合成图片的逐位比对。
- `requantize.log`：shift 0..24、舍入边界、饱和及INT32极值。
- `c_reference_*.log`：GCC -O2构建的C参考与Python导出结果一致。
- `training.log`：实际5轮训练与完整10,000张测试集的软件准确率。
- `verification.json`：工具版本与未执行环节。
- `board_results_template.csv`：留给AXU15EG实际测试的数据表，空白不是0。

这些日志是软件仿真与主机计算证据，不包含Vivado实现或真实DMA硬件测试。
