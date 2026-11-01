# ZYNQ 7020 FPGA / SoC 项目

基于 Xilinx ZYNQ-7020（ALIENTEK 领航者开发板）的 FPGA / SoC 学习与工程代码集合，包含 Verilog/SystemVerilog/VHDL 源码、Vivado 工程配置、Vitis 裸机与 Linux 相关代码，以及各阶段的设计文档。

## 目录结构

| 目录 | 说明 |
| --- | --- |
| `rtl/` | 通用 RTL 模块（时钟复位生成、顶层骨架等） |
| `ZYNQ/LED`、`ZYNQ/breath_led` | LED、呼吸灯示例（`rtl` / `sim` / `prj` / `doc`） |
| `ZYNQ/TFT_LCD_OLED` | TFT、OLED、I²C、EEPROM 相关代码与资料 |
| `ZYNQ/camera` | OV5640 摄像头采集工程 |
| `ZYNQ/doc` | 架构、需求、硬件参考资料 |
| `TD_Project/RS485`、`TD_Project/UART_PS`、`TD_Project/Camera` | PS 端外设工程（RS485、UART、摄像头） |
| `Vitis/LCD` | PS + PL 的 LCD 显示工程 |
| `Vitis/UDP` | UDP 视频传输工程（源码、上位机工具与开发记录） |
| `Vitis/RS485`、`Vitis/camera`、`Vitis/emio_gpio` | 其余 Vitis 例程 |
| `Linux/npu` | NPU 硬件加速与 Linux 用户态应用（驱动、SDK、设备树、工程文档） |
| `Linux/sdcard_image` | SD 卡镜像制作脚本 |
| `ZYNQ IO.xlsx` | ZYNQ 引脚分配表 |

## 工具链

- Vivado 2020.2（工程文件 `*.xpr`）
- Vitis 2020.2（裸机应用与 BSP）
- PetaLinux / 交叉编译工具链（`Linux/npu`）
- ModelSim（`sim` 目录下的 testbench）

## 关于本仓库的内容范围

为控制仓库体积，本仓库**不包含**以下内容，均可在本地用工具链重新生成或从原厂资料获取：

- Vivado/Vitis 构建产物：`*.runs`、`*.cache`、`*.gen`、`*.hw`、`*.ip_user_files`、`*.sim`、`*.dcp`、`*.bit`、`*.jou`、`*.log`
- 仿真波形 `*.vcd`、ModelSim 数据库 `*.wdb` / `*.qpg` / `*.qtl`
- 大体积镜像包（`sdcard_image.tar.gz`、`rootfs.tar.gz`、`uInitrd.lz4`）
- 第三方厂商资料（开发板原理图、芯片数据手册、厂商示例工程 `Example/`）

## 许可

本仓库中的第三方资料版权归各自厂商所有；其余代码仅用于学习交流。
