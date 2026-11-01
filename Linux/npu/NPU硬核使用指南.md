# DR1M90 NPU 硬核使用指南

> 基于 `D:\FPGA\Linux\npu` 目录整理  
> 板卡：米联客 MLK-F3P-CZ02（Anlogic DR1M90GEG400，ARM Cortex-A53 + FPGA）  
> 整理日期：2026-10-30  
> 配套官方 demo：`sdk/face_detection.tar.gz`  
> **说明**：本文依据目录里的源码、设备树、IP 参数、ONNX 模型和已有开发记录做静态整理，
> 未在板子上逐条实测；命令中的 IP、路径、脚本名请以你的实际环境为准。

---

## 0. 5 分钟速览

先记住下面 6 条，后面的内容都是围绕它们展开的：

1. **这个目录是 DR1M90 的 Linux + PL 工程，不是 Zynq 工程。**  
   Zynq 那边只负责 OV5640 采集和 UDP 发送；NPU 在 DR1M90 板子上。

2. **NPU 有两套：**
   - **硬核 NPU（Hard NPU）**：在 DR1M90 的 PS/SoC 内部，基地址 `0x63F00000`，中断 `GIC SPI 112`，设备节点 `/dev/hard_npu`。
   - **软核 NPU（Soft NPU / Video_NPU）**：在 PL 里，IP 名 `NPU_SOFT_0`（Block Design 里叫 `Video_NPU_0`），基地址 `0x1F0000000`，中断 `GIC SPI 97`，设备节点 `/dev/soft_npu`。

3. **用户态不要直接写 NPU 寄存器。**  
   官方软件栈是：

   ```text
   C++ 应用
     └── ArmNN 32.1（Alnpu 后端 + ONNX Parser）
           ├── /dev/hard_npu   （硬核：Conv/FC 等）
           ├── /dev/soft_npu   （Soft NPU：Pool/Act/Upsample/Route/Shortcut/YOLO/Resize）
           └── /dev/cma_mem    （DMA 物理连续内存）
   ```

4. **模型必须是量化后的 ONNX。**  
   demo 自带两个模型：
   - `inputs/yolo_face_uint8_15.onnx`：人脸检测，输入 **416×416**，1 类 `face`，YOLOv3-tiny 风格，两个输出头。
   - `inputs/fire_detect_sim_quant_uint8.onnx`：烟雾/火焰检测，输入 **640×640**，YOLOv8n 风格，需要 `--yolov8 1`。

5. **最快验证路径：**  
   在 DR1 板子上解压 `face_detection.tar.gz`，接 MIPI 或 USB 摄像头，跑 `yolo_demo_hdmi_camera`，HDMI 能看到人脸框就说明 NPU/JPU/显示链路都通了。

6. **当前 PL 的 Soft NPU 配置是：**  
   `YOLOV3TINY=1`、`MBFace=0`、`YOLOV8N=0`、`SOFT_RESIZE=1`、`SOFT_CSC=0`、`SOFT_YOLO=1`。  
   想换网络、启用 MBFace 或改软核加速选项，需要在 TangDynasty 里重新配置 `NPU_SOFT_0`，重新导出 HPF/bitstream，并重新生成启动镜像。

---

## 1. 目录地图

```text
Linux/npu/
├─ boot/                 可直接启动的镜像
│  ├─ BOOT.bin           FSBL + bitstream + 启动镜像
│  ├─ boot.scr           U-Boot 脚本：加载 uImage/uInitrd/dtb
│  ├─ system.dtb         Linux 设备树（包含 hard_npu / soft_npu 节点）
│  ├─ uImage.lz4         Linux 内核 + 可能内建的驱动
│  └─ uInitrd.lz4        initrd/rootfs（含 jpu.ko、mipicam.ko 等）
├─ driver/               显示相关 Linux 驱动（dynclk、vdmafb），不是 NPU 驱动
├─ sdk/
│  ├─ anlogic-dr1m90-softip.dts   PL IP 的设备树片段（soft_npu、vdma、hdmi 等）
│  └─ face_detection.tar.gz       官方 NPU demo（源码、模型、库、脚本）
├─ soc_dts/
│  ├─ kernel-dts/anlogic-dr1.dts  Linux 设备树
│  └─ uboot-dts/anlogic-dr1.dts   U-Boot 设备树
├─ soc_hw/               导出的 HPF（含 system.bit），给 FutureDynasty 建 FSBL
├─ soc_prj/              TangDynasty 工程（Video_NPU / ISP / MIPI / HDMI / VDMA）
└─ soc_sdk/              FSBL 工程（soc_base + soc_fsbl）
```

`face_detection.tar.gz` 解压后的关键内容：

```text
app/face_detection/
├─ inputs/              模型和 JSON 配置
│  ├─ yolo_face_uint8_15.onnx
│  ├─ example_yolo_face.json
│  ├─ fire_detect_sim_quant_uint8.onnx
│  └─ fire_detect_sim_quant_uint8.json
├─ libs/
│  ├─ armnn_lib/                    ArmNN 32.1 + Alnpu 后端 + ONNX Parser
│  └─ ffmpeg_opencv4.7.0_aarch64/   OpenCV 4.7 / FFmpeg
├─ src/
│  ├─ npu_flow/          demo 应用和工具（executor、preprocess、postprocess、camera、hdmi、udp_send）
│  ├─ jpu_driver/        JPU 用户态库
│  └─ linux_driver/      hard_npu / soft_npu / cma_mem / jpu / mipicam 内核模块源码
├─ scripts/              run_*.sh 运行脚本
├─ build.sh              交叉编译脚本
└─ build/                官方预编译产物（可参考）
```

---

## 2. 硬件架构

```text
DR1M90（MLK-F3P-CZ02）
┌──────────────────────────── PS（ARM Cortex-A53，Linux） ────────────────────────────┐
│                                                                                      │
│   C++ 应用（OpenCV / ArmNN / 业务逻辑）                                               │
│      │                                                                               │
│      ├── /dev/cma_mem   ── CMA/DMA 缓冲区（物理地址 + 虚拟地址）                       │
│      ├── /dev/hard_npu  ── 硬核 NPU 寄存器 / 中断                                    │
│      └── /dev/soft_npu  ── PL Soft NPU 寄存器 / 中断                                 │
│                                                                                      │
│   AXI Interconnect ───────────────► DDR（1 GB）                                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
        │ AXI-Lite + AXI Master                          │ AXI-Lite + AXI Master
        ▼                                                ▼
┌────────────────────────────┐             ┌──────────────────────────────────────────┐
│ Hard NPU                   │             │ Soft NPU / Video_NPU（PL）                 │
│ 0x63F00000 ~ 0x63FFFFFF    │             │ 0x1F0000000 ~ 0x1F00FFFF                  │
│ IRQ: GIC SPI 112           │             │ IRQ: GIC SPI 97                           │
│ 主要做 Conv/FC 的 MAC 阵列 │             │ Soft NN / Soft YOLO / Soft Resize 等       │
└────────────────────────────┘             └──────────────────────────────────────────┘
```

### 2.1 地址和中断总表

| 模块 | 物理地址 | 大小 | Linux 中断 | 设备节点/驱动 | 用途 |
|---|---|---|---|---|---|
| Hard NPU | `0x63F00000` | `0x100000` | `GIC SPI 112` | `/dev/hard_npu`，`hard_npu.ko` | 硬核卷积/全连接加速 |
| Hard NPU Top Cfg | `0xF8800000` | `0x200` | — | 由 `hard_npu` 驱动内部使用 | 使能、SRAM 唤醒 |
| Hard NPU Reset | `0xF8801000` | `0x100` | — | 由驱动/reset 控制器使用 | 软复位 |
| Soft NPU | `0x1F0000000` | `0x10000` | `GIC SPI 97` | `/dev/soft_npu`，`soft_npu.ko` | PL 软核加速 |
| JPU（JPEG 硬解） | `0xF8460000` | `0x300` | `GIC SPI 113`（驱动里 `145-32`） | `/dev/jpu`，`jpu.ko` | JPEG 解码，输出 YUV422 |
| VDMA | `0x80200000` | `0x1000` | `GIC SPI 84` | `axi_vdma` | 帧缓冲搬运 |
| VDMA Framebuffer | `0x80100000` | `0x1000` | — | `/dev/fb0`，`vdmafb` | HDMI 显示 |
| Dynclk | `0x80101000` | `0x1000` | — | `anlogic,dynclk` | 像素时钟 |
| MIPI Camera | `0x80300000` | `0x10000` | `GIC SPI 82` | `/dev/mipicam` | MIPI 摄像头采集 |

> 说明：DTS 里的 `interrupts = <GIC_SPI 112 ...>` 是 Linux 的 SPI 编号；HPF/裸机头文件里的 `NPU_HARD_IRQn = 144`、`NPU_SOFT_IRQn = 129` 是包含 32 个 SGI/PPI 的原始中断号，两者相差 32，是正常的。

### 2.2 硬核 NPU 和 Soft NPU 的分工

| 项目 | Hard NPU | Soft NPU（Video_NPU） |
|---|---|---|
| 位置 | PS/SoC 内部硬核 | PL 逻辑（`NPU_SOFT_0`） |
| 主要工作 | 卷积、全连接等重计算 | 池化、激活、上采样、Route、Shortcut、YOLO 后处理、Resize |
| 时钟 | PS 内部时钟 | 本工程 `PLL_npu` CLK0 = **150 MHz** |
| 可配置性 | 固定硬件 | 由 TD 里的 IP 参数决定 |
| 驱动 | `/dev/hard_npu` | `/dev/soft_npu` |
| 中断 | GIC SPI 112 | GIC SPI 97 |

> 按米联客/安路官方资料，硬核 NPU 是 512 MAC 级 INT8 卷积加速器（约 1 TOPS 量级）。本目录的 DTB 和 IP 参数文件没有直接写 MAC 数量，实际指标以官方手册为准。

---

## 3. PL 里的 Soft NPU（Video_NPU）是怎么配置的

### 3.1 当前 IP 参数

来自 `soc_prj/al_ip/NPU_SOFT_0/.params_NPU_SOFT_0.txt` 和 Block Design 里的 `Video_NPU_0`：

| 参数 | 当前值 | 含义 |
|---|---|---|
| `SOFT_NN` | 1 | 启用软核 NN 加速 |
| `NN_POOLING` | 1 | 池化 |
| `NN_ACTIVATE` | 1 | 激活函数 |
| `NN_UPSAMPLE` | 1 | 上采样 |
| `NN_ROUTE` | 1 | YOLO Route 层 |
| `NN_SHORTCUT` | 1 | Shortcut/残差 |
| `SOFT_RESIZE` | 1 | 硬件 Resize |
| `SOFT_CSC` | 0 | 颜色空间转换（当前关闭） |
| `SOFT_YOLO` | 1 | YOLO 相关加速 |
| `PRE_PROCESS` | 1 | 预处理 |
| `POST_PROCESS` | 0 | 后处理（当前关闭） |
| `YOLOV3TINY` | 1 | 当前选择的网络预设 |
| `YOLOV3` / `YOLOV4` / `YOLOV5S` | 0 | 未启用 |
| `MBFace` | 0 | **未启用** |
| `YOLOV8N` | 0 | 未启用 |
| `SOFT_HDMI_DISPLAY` | 0 | 未启用 |
| `ALL_OPERATOR` | 1 | 允许通用算子 |
| `SELECTABLE_NET` | 0 | 不可运行时切换网络 |

AXI 位宽：

- `AXIS_DT_WD=32`、`AXIS_DT_NB=4`：视频流侧 128 bit；
- `AXIM_DT_WD=64`、`AXIM_DT_NB=8`：AXI Master 侧 512 bit；
- 地址宽度 33 bit，可访问 DDR。

### 3.2 Soft NPU 内部寄存器块

从 `src/linux_driver/soft_npu_driver/soft_npu.c` 可以直接看到：

| 块 | 偏移 | 用途 | 清中断寄存器 |
|---|---|---|---|
| TOP | `0x0000` | 全局状态，中断状态在 `0x8` | — |
| Soft NN | `0x1800` | 池化/激活/上采样/Route/Shortcut 等 | `0x18BC` |
| Soft YOLO | `0x2000` | YOLO 相关 | `0x2040` |
| Soft CSC | `0x2800` | 颜色空间转换（当前 IP 关闭） | `0x286C` |
| Soft Resize | `0x3000` | 硬件缩放 | `0x3044` |
| DMA Start 0/1 | `0x0804` / `0x1004` | 启动 DMA | — |

### 3.3 改配置的代价

当前 bitstream 是围绕 **YOLOv3-tiny** 预设生成的。注意：

- `MBFace=0`：如果你要用厂商的 MBFace 人脸识别加速，需要重新生成 IP；
- `YOLOV8N=0`：虽然 demo 里能跑 YOLOv8n 的火焰模型（后处理在 ArmNN/CPU 侧），但如果想要软核对 YOLOv8n 做专门加速，也应重新配置；
- `SOFT_CSC=0`：颜色空间转换不在 PL 做，走 CPU/NEON；
- 改 IP 参数后，必须重新导出 HPF、重新生成 bitstream 和 `BOOT.bin`，并保证板子上的 `system.dtb` 与新的地址/中断一致。

---

## 4. 设备树与驱动

### 4.1 设备树节点

硬核 NPU（从 `boot/system.dtb` 解析出来的实际节点）：

```dts
hard_npu@63F00000 {
    compatible = "anlogic,hard_npu";
    reg = <0x0 0x63F00000 0x0 0x100000>,   /* NPU 寄存器 */
          <0x0 0xF8800000 0x0 0x200>,      /* Top 配置 */
          <0x0 0xF8801000 0x0 0x100>;      /* Reset/Top 控制 */
    interrupts = <GIC_SPI 112 IRQ_TYPE_LEVEL_HIGH>;
};
```

软核 NPU（`sdk/anlogic-dr1m90-softip.dts`）：

```dts
soft_npu0: soft_npu@1f0000000 {
    compatible = "anlogic,soft_npu";
    reg = <0x1 0xf0000000 0x0 0x10000>;
    interrupts = <GIC_SPI 97 IRQ_TYPE_LEVEL_HIGH>;
    status = "okay";
};
```

### 4.2 驱动一览

| 驱动 | 设备节点 | 作用 | 源码位置（demo 解压后） |
|---|---|---|---|
| `hard_npu.ko` | `/dev/hard_npu` | 硬核 NPU 寄存器、中断、mmap | `src/linux_driver/hard_npu_driver/hard_npu.c` |
| `soft_npu.ko` | `/dev/soft_npu` | Soft NPU 寄存器、中断、mmap | `src/linux_driver/soft_npu_driver/soft_npu.c` |
| `cma_mem.ko` | `/dev/cma_mem` | CMA/DMA 物理连续内存分配 | `src/linux_driver/cma_mem_driver/cma_mem.c` |
| `jpu.ko` | `/dev/jpu` | JPEG 硬解 | `src/linux_driver/jpu_driver/jpu.c` |
| `mipicam.ko` | `/dev/mipicam` | MIPI 摄像头 | `src/linux_driver/mipicam_driver/` |

> 从 `boot/uImage.lz4` 的字符串能看到 `[HARD NPU]` 等内核日志，说明 **hard_npu 驱动很可能已经编进内核**；`uInitrd.lz4` 里能看到 `/opt/bin/jpu.ko`、`/opt/bin/mipicam.ko`。`soft_npu`/`cma_mem` 是内建还是模块，以板子上的 `lsmod` 和 `/dev` 为准。

### 4.3 驱动 ioctl 接口

两个 NPU 驱动的接口几乎一样，只是 magic 不同：

| ioctl | Hard NPU | Soft NPU | 作用 |
|---|---|---|---|
| `WAIT_INTERRUPT` | `HARDNPU_IOCTL_WAIT_INTERRUPT` | `SOFTNPU_IOCTL_WAIT_INTERRUPT` | 等中断，带毫秒超时，返回 `intr_flag` / `work_status` |
| `GET_REGISTER_INFO` | `HARDNPU_IOCTL_GET_REGISTER_INFO` | `SOFTNPU_IOCTL_GET_REGISTER_INFO` | 获取寄存器物理地址/大小，供 mmap |
| `WRITE_REG` | `HARDNPU_IOCTL_WRITE_REG` | `SOFTNPU_IOCTL_WRITE_REG` | 写 32-bit 寄存器 |
| `READ_REG` | `HARDNPU_IOCTL_READ_REG` | `SOFTNPU_IOCTL_READ_REG` | 读 32-bit 寄存器 |

它们都支持 `mmap` 寄存器块。注意：

- 驱动里用 `s_is_open` 做互斥，**同一时间只允许一个进程打开** `/dev/hard_npu` 或 `/dev/soft_npu`。ArmNN 的 Alnpu 后端已经打开了它们，你的应用不要再打开。
- 这些 ioctl 是给 Alnpu 后端/调试用的。**不建议自己拼 NPU 指令序列**，因为硬核的指令/描述符格式没有在这个目录里公开。

### 4.4 驱动 probe 时做了什么

Hard NPU（`hard_npu.c`）：

1. 从 DTS 拿第 0 段内存（`0x63F00000`）并 `devm_ioremap_resource`；
2. 从第 1 段内存（`0xF8800000`）写 `+0x1B8 = 0x3` 使能 NPU；
3. 写 `+0x30` 清 SRAM 唤醒位；
4. 通过 reset controller 做一次软复位；
5. 注册中断（ISR 读 `0x1018` / `0x1014`，写 `0x101C` 清中断）；
6. 创建 `/dev/hard_npu`。

Soft NPU（`soft_npu.c`）：

1. 映射 `0x1F0000000` 的 64 KB；
2. 注册中断，按 `TOP + 0x8` 的中断状态分别清 Soft NN/YOLO/CSC/Resize 的中断；
3. 创建 `/dev/soft_npu`。

### 4.5 CMA 内存

- `cma_mem` 用 `dma_alloc_coherent` 分配物理连续内存；
- DTS 里 `&cma { alloc-ranges = <0x0 0x0 0x0 0x1fffffff>; size = <0x0 0x8000000>; }`，即 **128 MB CMA 池**；
- NPU、JPU、VDMA、framebuffer 都依赖这类内存；
- 用户态通过 `cma_mem_alloc()` / `CmaBuf` 使用，**不要用普通 `malloc` 的内存直接喂 NPU**。

---

## 5. 用户态软件栈

### 5.1 分层

```text
你的业务代码
  │
  ├── OpenCV（读图、resize、画框）
  ├── BufferedNPUExecutor / NPUExecutor（demo 封装）
  │     └── ArmNN 32.1
  │           ├── armnnOnnxParser（读 ONNX）
  │           ├── Alnpu 后端（硬核 + Soft NPU）
  │           └── CpuAcc / CpuRef（回退）
  ├── JPU 用户态库（JPEG 硬解）
  └── udp_send（检测结果 JSON）
```

### 5.2 关键类/函数

| 名称 | 所在文件 | 作用 |
|---|---|---|
| `CmaResourceZone` | `flow_common_types.hpp` | RAII 管理 `cma_mem_init/deinit` |
| `CmaBuf` | `flow_common_types.hpp` | 分配/释放 CMA，带 `sync_cpu` / `sync_device` |
| `CmaAllocator` | `armnnALUtils/cma_mem_init.hpp` | 给 ArmNN 的 CpuAcc/CpuRef 提供 CMA 分配器 |
| `BufferedNPUExecutor` | `buffered_executor.hpp` | 加载 ONNX、优化、分配 8 组输入/输出 CMA、`Run(idx)` |
| `NPUExecutor` | `executor.hpp` | 单缓冲版本，接口更简单 |
| `npu_input_quant_param_t` | `armnnALUtils/DataProcess.hpp` | 输入量化参数（mean/scale/zero_point） |
| `npu_input_quant_param_init()` | `preprocess.cpp` | 根据模型 scale/zero 和训练 mean/scale 计算定点参数 |
| `prepare_input_data()` | `preprocess.cpp` | 把 packed BGR 转成 NCHW RGB 平面并量化 |
| `soft_resize_yuv422_to_rgb_plane()` | `preprocess.cpp` | NEON 实现的 YUYV→RGB 平面 + 最近邻缩放 |
| `AlnpuYoloPostProcess()` | `armnnALUtils/DataProcess.hpp` | YOLOv3-tiny 风格后处理（anchor） |
| `AlnpuYolov8PostProcess()` | `armnnALUtils/DataProcess.hpp` | YOLOv8 DFL 后处理 |
| `getFastDecodeOutputYoloWorkLoad()` | `postprocess.hpp` | demo 里实际使用的后处理封装 |
| `udp_send` | `media/udp_send.hpp` | 把检测结果以 JSON 发出去 |

> 这些符号在 `libarmnn.so.32.1` 里也能看到，例如 `AlnpuALHardNPUWorkload`、`AlnpuPooling2dWorkload`、`AlnpuResizeWorkload`、`AlnpuYoloPostProcessWorkloadGet`，说明 Alnpu 后端确实是通过 `/dev/hard_npu`、`/dev/soft_npu`、`/dev/cma_mem` 工作的。

### 5.3 输入数据的规则（最容易出错的地方）

1. **布局：NCHW**，不是 NHWC。
2. **颜色：RGB 平面**，不是 BGR 交错。  
   `prepare_input_data()` 的输入是 OpenCV 的 packed BGR，输出是 `R 平面 + G 平面 + B 平面`。
3. **量化：** 模型输入 tensor 的 `scale` / `zero_point` 必须从 ArmNN 里读：

   ```cpp
   float input_scale = ex.GetInputQuantizationScale(0);
   int   input_zero  = ex.GetInputQuantizationOffset(0);
   ```

   再结合训练时的 `mean` / `scale`（JSON 里的 `input_params`）调用：

   ```cpp
   npu_input_quant_param_init(qp, input_scale, input_zero,
                              ex.GetInputDataType(), img_scale, mean);
   ```

4. **内存：** 输入/输出都放在 CMA。demo 的 `BufferedNPUExecutor` 已经为 8 个 pipeline buffer 分配好了，直接用 `ex.GetInputBuffer(0, idx)->virt_addr` 即可。
5. **同步：** CPU 写完输入后，如遇到旧帧/花屏，可调用 `CmaBuf::sync_device()`；CPU 读 NPU 输出前可调用 `sync_cpu()`。demo 的 CMA 是 coherent 分配，多数情况下不调用也能工作。

### 5.4 demo 的 pipeline

`solution.hpp` 里注册了 6 个任务：

```text
camera → resize → npu → yolo → hdmi → report
```

- `task_camera`：从摄像头拿到一帧（MIPI 是 BGRA，USB 是 JPU 解出的 YUYV）；
- `task_resize`：缩放到模型输入尺寸，并做颜色/量化；
- `task_npu`：调用 `BufferedNPUExecutor::Run()`；
- `task_yolo`：YOLO 后处理，得到 `DetectObject`；
- `task_hdmi`：画框，送 framebuffer/DRM；同时把结果 JSON 通过 UDP 发出去；
- `task_report`：打印每阶段耗时和 FPS。

`MAX_BUF_NUM = 8`，每个任务有独立的线程和产品数限制，目的是让 camera/resize/NPU/后处理重叠执行。

---

## 6. 官方 face_detection demo 怎么用

### 6.1 先确认板子上的设备

```bash
ls -l /dev/hard_npu /dev/soft_npu /dev/cma_mem /dev/jpu /dev/fb0
lsmod | grep -E 'hard_npu|soft_npu|cma_mem|jpu|mipicam'
dmesg | grep -iE 'npu|jpu|cma'
```

如果 `/dev/hard_npu`、`/dev/soft_npu`、`/dev/cma_mem` 不存在，先解决驱动/设备树问题，不要继续。

### 6.2 编译

先把 `face_detection.tar.gz` 解压到 `/home/uisrc`（tar 内自带 `app/` 前缀，
解压后得到 `/home/uisrc/app/face_detection`），再进入该目录。

官方 `build.sh` 默认路径是：

```bash
SCRIPT_DIR=/home/uisrc/app/face_detection
ROOT_DIR=/home/uisrc/uisrc-lab-anlogic
cxx_compiler=/home/uisrc/uisrc-lab-anlogic/tools/aarch64-linux/bin/aarch64-linux-gnu-g++
KERNELDIR=/home/uisrc/uisrc-lab-anlogic/sources/linux
```

根据你的实际路径修改。依赖：

```bash
sudo apt install -y build-essential cmake ninja-build git \
    libncurses5-dev bison flex libssl-dev device-tree-compiler \
    python3-pip gcc-aarch64-linux-gnu
cmake --version   # demo 要求 >= 3.21.2
```

编译：

```bash
cd /home/uisrc/app/face_detection
chmod +x build.sh
./build.sh
```

说明：

- `build.sh` 会编译 `src/npu_flow` 下的应用和 `src/linux_driver` 下的内核模块；
- 如果只是跑应用、不重编内核模块，可以把 `-DBUILD_MODULES:BOOL=ON` 改成 `OFF`，避免依赖完整内核源码；
- 产物在 `build/bin/yolo_demo_hdmi_camera`，运行环境在 `rootfs/root/`。

### 6.3 运行

MIPI 摄像头 + HDMI：

```bash
cd /home/uisrc/app/face_detection/rootfs/root
export LD_LIBRARY_PATH=$PWD/armnn_lib/lib:$PWD/ffmpeg_opencv4.7.0_aarch64/lib:$LD_LIBRARY_PATH

# 停掉桌面，避免和 /dev/fb0 抢
sudo systemctl stop gdm

# 需要 /dev/mipicam；脚本会自动 insmod mipicam.ko
sudo ./scripts/run_mipicam_fb.sh
```

等价的手工命令：

```bash
sudo ./bin/yolo_demo_hdmi_camera \
    -m ./inputs/yolo_face_uint8_15.onnx \
    -u ./inputs/example_yolo_face.json \
    -s 192.168.1.102:12345 \
    -i /dev/mipicam \
    -o /dev/fb0
```

USB 摄像头：

```bash
sudo ./bin/yolo_demo_hdmi_camera \
    -m ./inputs/yolo_face_uint8_15.onnx \
    -u ./inputs/example_yolo_face.json \
    -s 192.168.1.102:12345 \
    -i /dev/video0 \
    -o /dev/fb0 \
    --geometry 1920x1080
```

火焰检测（YOLOv8n，640×640）：

```bash
sudo ./bin/yolo_demo_hdmi_camera \
    -m ./inputs/fire_detect_sim_quant_uint8.onnx \
    -u ./inputs/fire_detect_sim_quant_uint8.json \
    -s 192.168.1.102:12345 \
    -i /dev/video0 \
    -o /dev/fb0 \
    --yolov8 1
```

> 注意：`scripts/run_usbcam_fb_fire_recognition_udp.sh` 里写的是 `yolo_demo_hdmi_camera_udp`，但 `CMakeLists.txt` 只生成 `yolo_demo_hdmi_camera`。直接跑会找不到文件；要么把脚本里的名字改成 `yolo_demo_hdmi_camera`，要么给 CMake 再加一个同名 target/复制一份二进制。

### 6.4 命令行参数

| 参数 | 说明 |
|---|---|
| `-m, --model` | ONNX 模型路径 |
| `-u, --usercfg` | 预处理/后处理 JSON 路径 |
| `-b, --backends` | 后端优先级，默认 `Alnpu,CpuAcc,CpuRef` |
| `-i, --input` | 摄像头设备：`/dev/mipicam`、`/dev/video0`，也可以是 MJPEG 文件 |
| `-o, --output` | 显示设备：`/dev/fb0` 或 `/dev/dri/card0`；空字符串表示不显示 |
| `-s, --server` | **必填**，检测结果 JSON 发往的 `<IP>:<PORT>` |
| `--geometry` | 摄像头/显示分辨率，如 `1920x1080` |
| `--yolov8` | 使用 YOLOv8 后处理；模型名含 `yolov8` 时自动开启 |
| `-l, --logLevel` | 日志等级 |

### 6.5 输出

终端每 10 秒左右打印：

```text
***** Frame Count:..., During:... *****
     frame : ...
    camera : ...
    resize : ...
       npu : ...
      yolo : ...
      hdmi : ...
    report : ...
```

看 `npu` 这一行的耗时和 FPS，就能判断 NPU 是否真的在跑。  
HDMI 上会画人脸框和置信度。

UDP 结果 JSON（发往 `-s`）的格式：

```json
{
  "objects": [
    {"label": 0, "prob": 0.95, "x": 208, "y": 208, "w": 80, "h": 96}
  ],
  "input_width": 416,
  "input_height": 416,
  "timestamp": 1625247600.123456
}
```

注意：**`x/y/w/h` 是模型输入坐标系（416×416）下的中心点坐标**，不是原始 640×480 画面坐标。demo 在 `task_hdmi` 里才把它们换算到显示坐标。如果你要用这个 JSON 做业务，记得自己换算。

### 6.6 模型细节

`yolo_face_uint8_15.onnx`（从 ONNX 文件实际解析）：

| 项目 | 值 |
|---|---|
| 输入 | `images`，`[1, 3, 416, 416]` |
| 输出 1 | `[1, 18, 26, 26]` |
| 输出 2 | `[1, 18, 13, 13]` |
| 类别数 | 1（`face`） |
| 结构 | YOLOv3-tiny 风格，2 个检测头，stride 16/32 |
| 每头 anchor 数 | 3 |
| 每 anchor 输出 | `5 + 1 = 6` → 3×6 = 18 通道 |
| anchors (stride 16) | `4,6, 8,10, 13,17` |
| anchors (stride 32) | `26,35, 60,78, 162,206` |
| 阈值 | `probThreshold=0.35`，`nmsThreshold=0.45` |
| 输入预处理 | mean=0，scale=1/255（见 JSON） |

`fire_detect_sim_quant_uint8.onnx`：

| 项目 | 值 |
|---|---|
| 输入 | `[1, 3, 640, 640]` |
| 输出 | 3 个尺度，每个尺度 64 通道 DFL + 2 类 |
| 类别 | `smoke`, `fire` |
| 后处理 | YOLOv8，需要 `--yolov8 1` |
| 阈值 | `probThreshold=0.20`，`nmsThreshold=0.45` |

---

## 7. 自己写 NPU 程序的最小骨架

下面是最小可编译思路（基于 demo 的头文件）。实际工程里建议直接复用 `BufferedNPUExecutor`、`preprocess`、`postprocess`。

```cpp
#include <opencv2/opencv.hpp>
#include <vector>
#include <string>
#include <array>

#include "flow_common_types.hpp"      // CmaResourceZone, CmaBuf
#include "buffered_executor.hpp"      // BufferedNPUExecutor
#include "preprocess.hpp"             // prepare_input_data, npu_input_quant_param_init
#include "armnnALUtils/DataProcess.hpp" // AlnpuYoloPostProcess

int main() {
    // 1) 初始化 CMA（内部 open /dev/cma_mem）
    CmaResourceZone zone;

    // 2) 加载模型，优先 Alnpu，失败可回退 CPU
    std::string model = "/home/uisrc/app/face_detection/rootfs/root/inputs/yolo_face_uint8_15.onnx";
    std::vector<armnn::BackendId> backends = {"Alnpu", "CpuAcc", "CpuRef"};
    BufferedNPUExecutor ex(model, backends);

    // 3) 读取模型输入尺寸和量化参数
    Size in_size = ex.GetInputAspectRatio(0);              // 416x416
    float input_scale = ex.GetInputQuantizationScale(0);
    int   input_zero  = ex.GetInputQuantizationOffset(0);

    // 4) 训练时的 mean/scale（与 JSON 的 input_params 一致）
    std::array<float, 3> mean      = {0.f, 0.f, 0.f};
    std::array<float, 3> img_scale = {1.f/255.f, 1.f/255.f, 1.f/255.f};
    npu_input_quant_param_t qp;
    npu_input_quant_param_init(qp, input_scale, input_zero,
                               ex.GetInputDataType(), img_scale, mean);

    // 5) 准备一帧 BGR 图像
    cv::Mat bgr = cv::imread("test.jpg");                  // OpenCV 默认 BGR
    cv::Mat resized;
    cv::resize(bgr, resized, cv::Size(in_size.m_width, in_size.m_height));

    // 6) 写入 NPU 输入 CMA 缓冲区（注意：BGR packed -> RGB planar）
    uint8_t *dst = (uint8_t *)ex.GetInputBuffer(0, 0)->virt_addr;
    prepare_input_data(resized.data, resized.rows, resized.cols, qp, dst);

    // 7) 同步、推理
    ex.GetInputBuffer(0, 0).sync_device();
    if (!ex.Run(0)) {
        fprintf(stderr, "NPU run failed\n");
        return -1;
    }

    // 8) 后处理（YOLOv3-tiny 风格，需要 strideAnchorMap）
    std::unordered_map<int, std::vector<int>> anchors = {
        {16, {4, 6, 8, 10, 13, 17}},
        {32, {26, 35, 60, 78, 162, 206}}
    };
    auto objects = AlnpuYoloPostProcess(
        ex.GetOutputTensors(0),
        in_size.m_width, in_size.m_height,
        anchors, 1, 0.35f, 0.45f);

    for (auto &o : objects) {
        printf("face: prob=%.3f center=(%d,%d) size=(%d,%d)\n",
               o.prob, o.x, o.y, o.w, o.h);
    }
    return 0;
}
```

必须遵守的规则：

1. **不要直接 open `/dev/hard_npu` / `/dev/soft_npu`**，ArmNN 已经打开了；驱动是单实例的。
2. **输入必须是 CMA 内存**，并且是 NCHW + RGB 平面 + 量化后的数据。
3. **模型的 scale/zero_point 不要手算**，用 ArmNN 的 `GetInputQuantizationScale/Offset`。
4. **训练预处理参数（mean/scale）必须和 JSON 一致**；换模型时一起换。
5. **输出 tensor 也是量化的**，后处理函数会处理 scale/zero；不要直接当 float 读。
6. **一次只跑一个 NPU 应用**；不要和官方 demo 同时开。

### 7.1 直接用 ioctl 调试（不推荐）

如果只想确认驱动/寄存器是否能访问，可以写一个小工具：

```cpp
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <stdio.h>
#include "hard_npu_module.h"

int main() {
    int fd = open("/dev/hard_npu", O_RDWR);
    if (fd < 0) { perror("open"); return -1; }

    struct hardnpu_reg_info_t info;
    if (ioctl(fd, HARDNPU_IOCTL_GET_REGISTER_INFO, &info) == 0) {
        printf("hard_npu reg phys=0x%llx size=0x%llx\n",
               (unsigned long long)info.addr,
               (unsigned long long)info.size);
    }
    close(fd);
    return 0;
}
```

但**不要用它来手工启动推理**；指令格式不在这个目录里，硬拼没有意义。

---

## 8. 模型与转换

### 8.1 模型要求

- **ONNX 格式**，静态 shape，NCHW；
- **已量化**（INT8/UINT8），文件里通常带 `QuantizeLinear` / `DequantizeLinear` 节点；
- 算子要在 Alnpu 后端支持范围内；不支持的算子会回退到 `CpuAcc`/`CpuRef`，速度会掉；
- 输入尺寸、mean/scale、类别数、anchor 必须和 JSON 一致；
- 不要用动态 batch/动态分辨率。

### 8.2 自定义模型的推荐流程

1. 在 PyTorch/Ultralytics 里训练；
2. 导出 ONNX（优先复用官方模型相同的 opset/导出脚本）；
3. 做 INT8 量化，校准集用你自己的场景图片（100~200 张）；
4. 在 PC 上用 Netron 检查输入/输出 shape 和节点；
5. 在板子上先用 CPU 后端验证：

   ```bash
   ./bin/yolo_demo_hdmi_camera -m your.onnx -u your.json -b CpuRef ...
   ```

6. 再切到 NPU：

   ```bash
   ./bin/yolo_demo_hdmi_camera -m your.onnx -u your.json -b Alnpu,CpuAcc,CpuRef ...
   ```

7. 看日志里的 `npu` 耗时和 CPU 占用，确认没有大量回退。

> 本目录只有**已经转换好的** ONNX，没有模型转换/量化工具。转换工具在米联客的 NPU 开发资料包里，按官方 PDF 使用。

### 8.3 JSON 配置

`example_yolo_face.json` 的结构：

```json
{
  "input_params": {
    "r_mean": 0.0, "g_mean": 0.0, "b_mean": 0.0,
    "r_scale": 0.0039210, "g_scale": 0.0039210, "b_scale": 0.0039210
  },
  "yolo_params": {
    "probThreshold": 0.35,
    "nmsThreshold": 0.45,
    "className": ["face"],
    "strideAnchorMap": [
      {"key": 16, "val": [4, 6, 8, 10, 13, 17]},
      {"key": 32, "val": [26, 35, 60, 78, 162, 206]}
    ]
  }
}
```

换模型时：

- `input_params` 改成训练时的归一化参数；
- `className` 改成你的类别；
- `strideAnchorMap` 改成你的 anchor；YOLOv8 这种 anchor-free 模型可以不要这个字段；
- YOLOv8 模型运行时加 `--yolov8 1`。

### 8.4 MBFace / 人脸识别模型

当前 bitstream 是 `MBFace=0`。如果你要做“识别是谁”，而不是“检测人脸”：

1. 先尝试把 **MobileFaceNet / ArcFace** 之类的轻量 embedding 模型转成量化 ONNX，直接走 Alnpu；
2. 硬核做 Conv/FC，Soft NPU 做 Pool 等；如果层不支持，会回退 CPU；
3. 如果性能/支持度不行，再考虑在 TangDynasty 里把 `NPU_SOFT_0` 的 `MBFace` 设为 1，重新生成 IP、HPF、bitstream 和 `BOOT.bin`。

注意：启用 MBFace 不等于“自动能识别”，它只是给特定网络提供硬件加速选项；你仍然需要 embedding 模型、人脸库和相似度阈值。

---

## 9. 验证与排错

### 9.1 板子侧检查清单

```bash
# 1. 设备节点
ls -l /dev/hard_npu /dev/soft_npu /dev/cma_mem /dev/jpu /dev/fb0

# 2. 驱动
lsmod | grep -E 'hard_npu|soft_npu|cma_mem|jpu|mipicam'
dmesg | grep -iE 'hard_npu|soft_npu|jpu|cma|npu'

# 3. 设备树
ls /proc/device-tree/soc/ | grep -i npu
cat /proc/device-tree/soc/hard_npu@63F00000/compatible 2>/dev/null
cat /proc/device-tree/soc/soft_npu@1f0000000/compatible 2>/dev/null

# 4. framebuffer
cat /sys/class/graphics/fb0/bits_per_pixel
cat /sys/class/graphics/fb0/virtual_size
cat /sys/class/graphics/fb0/stride
```

### 9.2 常见问题

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `/dev/hard_npu` 不存在 | 驱动没编进内核/没加载；DTB 不匹配 | 检查 kernel config、`dmesg`、`/proc/device-tree`；必要时 `insmod` demo 里的 `.ko` |
| `insmod` 报 vermagic 不匹配 | 模块和板子内核版本不一致 | 用板子内核源码重新编译 `linux_driver` |
| CMA 分配失败 | CMA 池太小/泄漏 | 检查 DTS `&cma` 的 `size`；减少 buffer 数；重启 |
| NPU 推理超时 | 中断没来、bitstream 不匹配、NPU 复位失败 | 看 `dmesg`；确认 `BOOT.bin`/bitstream 与 DTB 是同一套；重新上电 |
| 结果全错/乱框 | mean/scale/layout/anchor 不对 | 先用官方模型+官方 JSON 验证；检查 NCHW/RGB/量化 |
| 报 `unsupported network quantization type` | 模型不是量化 ONNX | 用官方量化工具重转 |
| 报 `the number of yolo head ...` | `strideAnchorMap` 和输出头数量不一致 | 改 JSON 的 `strideAnchorMap` |
| FPS 很低 | 大量算子回退 CPU；JPEG 软解；每帧 malloc | 看日志 `npu` 耗时；用 JPU；用 CMA；减少拷贝 |
| HDMI 黑屏/花屏 | fb 分辨率/像素格式不匹配；桌面抢占 | 停 `gdm`；查 `bits_per_pixel`/`stride`；匹配分辨率 |
| 只能打开一次 NPU | 另一个进程占着 | 关掉官方 demo 再跑自己的程序 |
| 模型输入 shape 不对 | 用了别的模型/别的 JSON | 用 Netron 看输入，改 resize 和 JSON |

### 9.3 怎么判断 NPU 真的在跑

- 终端日志里 `npu` 阶段有独立耗时；
- `top` 看 CPU 占用，如果 NPU 正常工作，CPU 不会 100%；
- 对比 `-b CpuRef` 和 `-b Alnpu,CpuAcc,CpuRef` 的 FPS；
- `dmesg | grep -i npu` 没有 timeout；
- 不要只看“程序没崩”，要看 FPS 和结果。

---

## 10. 关键文件索引

| 文件 | 说明 |
|---|---|
| `boot/system.dtb` | 实际设备树，含 hard_npu/soft_npu 地址和中断 |
| `boot/uImage.lz4` | 内核（名字带 lz4，实际是 u-boot legacy uImage） |
| `boot/uInitrd.lz4` | initrd/rootfs，含 `jpu.ko`、`mipicam.ko` |
| `sdk/anlogic-dr1m90-softip.dts` | PL IP 设备树片段（soft_npu、vdma、hdmi、mipi） |
| `sdk/face_detection.tar.gz` | NPU demo（源码、模型、库、脚本） |
| `soc_prj/al_ip/NPU_SOFT_0/.params_NPU_SOFT_0.txt` | Soft NPU IP 参数 |
| `soc_prj/design_0/Design.xml` | Block Design（Video_NPU、PLL_npu 150MHz） |
| `soc_prj/design_0/ip/design_0_Video_NPU_0/` | Video_NPU 实例 RTL |
| `soc_hw/soc_prj.hpf` | 导出给 FutureDynasty 的硬件平台（含 bitstream） |
| `soc_dts/kernel-dts/anlogic-dr1.dts` | Linux 设备树（include softip 片段） |
| `soc_sdk/soc_fsbl/alfsbl_readme.md` | FSBL 说明 |
| demo `src/linux_driver/hard_npu_driver/hard_npu.c` | 硬核驱动 |
| demo `src/linux_driver/soft_npu_driver/soft_npu.c` | Soft NPU 驱动 |
| demo `src/linux_driver/cma_mem_driver/cma_mem.c` | CMA 驱动 |
| demo `src/npu_flow/utils/buffered_executor.*` | NPU 推理封装 |
| demo `src/npu_flow/utils/preprocess.cpp` | 量化/颜色/缩放 |
| demo `src/npu_flow/utils/postprocess.cpp` | YOLO 后处理 |
| demo `src/npu_flow/yolo_demo_hdmi_camera/solution.cpp` | 完整 pipeline |
| demo `src/npu_flow/utils/media/udp_send.hpp` | 结果 JSON UDP 发送 |

---

## 11. 一句话总结

**DR1M90 的 NPU = PS 硬核 + PL 软核；用户态用 ArmNN 的 Alnpu 后端，通过 `/dev/hard_npu`、`/dev/soft_npu`、`/dev/cma_mem` 使用；模型用官方量化 ONNX；先跑通官方 `face_detection`，再改成自己的数据源和模型。**
