# DMA驱动INT8小型CNN：从已上板矩阵乘法到MNIST

这是独立的第一版CNN工程，目标器件是你已使用的AXU15EG（`xczu15eg-ffvb1156-2-i`）。保留原来的`ps_hello`和矩阵乘法工程。新设计需要重新生成bitstream与XSA，不能仅替换Vitis的`main.c`。

本包已完成训练、整数参考、RTL与仿真。Vivado综合/实现、生成新BSP以及AXU15EG实测，需要在你的Windows电脑上继续。**包内没有声称已经上板通过的CNN bitstream，也没有编造CPU加速比或资源用量。**

## 已经做好的内容

| 项目 | 内容与结果 |
|---|---|
| 网络 | 28×28灰度 → 4通道3×3有效卷积 → ReLU → 2×2最大池化 → 676到10全连接 |
| 训练 | MNIST训练集60,000张，5个epoch，固定随机种子42 |
| 完整测试集 | 10,000张：FP32准确率96.58%，整数参考准确率96.56% |
| 量化 | INT8权重与特征、INT32偏置/累加、2的幂缩放、舍入与饱和 |
| 数据传输 | AXI DMA Simple Mode；AXI4-Lite控制，32位AXI4-Stream数据 |
| 数据复用 | 权重驻留PL；卷积/激活/池化融合；中间特征不回DDR |
| 并行与缓冲 | 4/8/16路MAC参数、双图像缓冲、下一张加载与当前张计算重叠 |
| RTL验证 | 16张真实MNIST及4张合成边界图片，三种并行度的10个logit逐位比对 |
| 接口验证 | 独立AW/W到达、读写响应暂停、随机Stream反压、TLAST/TKEEP错误恢复、缓存所有权 |
| 软件 | 可移植整数C参考、A53 DMA驱动、串行/批处理计时、结果校验 |

完整测试集准确率来自**软件整数模型**；RTL仿真验证的是随包提供的测试子集。`reports/`保存本次实际运行的记录，`trained/metadata.json`保存训练结果。

## 先看哪些文件

| 路径 | 用途 |
|---|---|
| `docs/01_上板步骤.md` | 从现有Vivado工程迁移、生成XSA、建立Vitis应用 |
| `docs/02_架构与协议.md` | 数据顺序、寄存器、定点数规则、模块职责 |
| `docs/03_性能实验.md` | 性能口径、结果表、下一轮优化方向 |
| `rtl/` | 13个可综合SystemVerilog模块 |
| `sim/` | CNN与量化自检testbench、C参考校验程序 |
| `python/train_export.py` | 训练与量化导出 |
| `python/reference.py` | 独立整数参考、二进制/HEX/C头文件导出 |
| `trained/` | 已训练权重和16张真实MNIST图片，可直接用于第一轮上板 |
| `vectors/` | 固定种子合成数据，含零值、最大输入与随机值；不用于报告识别准确率 |
| `software/` | Vitis应用源码；使用时再拷贝一个数据头文件到`src` |
| `scripts/` | 仿真、原板配置导出、新Vivado工程构建、实现脚本 |

## 现在先做这一步

解压到一个短的英文目录，例如：

```text
D:/FPGA/cnn_mnist_dma_v1
```

在已打开且已验证的Vivado `ps_hello`工程中，先打开Block Design，然后在**Vivado底部Tcl Console**执行：

```tcl
source D:/FPGA/cnn_mnist_dma_v1/scripts/export_board.tcl
```

这会把你的PS、DDR、UART等板级配置导出到新目录，原工程不被保存或改写。后续命令在`docs/01_上板步骤.md`。不要把Tcl指令输入Windows CMD，也不要把Python指令输入Vivado Tcl Console。

## 在Windows重跑RTL仿真

在Vivado已加入PATH的CMD窗口中：

```bat
cd /d D:\FPGA\cnn_mnist_dma_v1
scripts\run_xsim.bat 4 trained 16
scripts\run_xsim.bat 8 trained 16
scripts\run_xsim.bat 16 trained 16
```

需要看到CNN和量化两个`PASS`。`run_xsim.bat`为你本机Vivado提供入口；本次实际执行的仿真器是Verilator，XSim入口尚未在本环境执行。

Linux安装Verilator和C++编译器后，可执行：

```bash
python scripts/run_verilator.py --vectors trained
python scripts/run_verilator.py --vectors vectors
```

如果工具名是`verilator-cli`，脚本也会自动查找；也可通过`VERILATOR`环境变量指定可执行文件。

## 重新训练是可选项

第一轮联调直接用`trained/`，无需重新训练。重训命令（Windows CMD或终端）：

```bat
python -m pip install -r python/requirements.txt
python python/train_export.py --epochs 5 --frames 16 --out trained_new
```

脚本下载MNIST，训练FP32模型，只使用训练集前2,048张校准激活范围，然后跑完整测试集的整数参考。测试集没有参与梯度训练或量化校准。训练库版本或CPU后端差异可能使重训结果略有变化；随包权重与对应参考输出固定可复现。

重训后必须成套使用新目录的`model.hex`、`images.hex`、`expected.hex`和`cnn_test_data.h`，不能混用新权重和旧参考结果。

## 这一版的边界

网络结构固定为一层卷积和一层全连接；不是任意ONNX模型的通用执行引擎。窗口模块从片上整帧缓存读3×3窗口，还没有实现流式三行缓存；MAC目前每个tap使用读、乘、累加三个周期，还不是每周期发射一个tap。卷积固定用4路，4/8/16路配置主要改变FC并行度。批处理采用Simple DMA分别重启两个通道，不是Scatter-Gather。没有摄像头、Linux驱动、UVM环境或医学检测功能。

这些限制明确了下一轮性能改进的位置，不影响先把训练→量化→DMA→RTL→分类校验的完整路径搭起来。不要把MNIST识别结果写成血糖检测结果。
