# MLK-F3P-CZ02 (DR1M90) UDP 视频接收 + NPU 推理 项目说明书

> **目标**：Zynq-7020（OV5640 JPEG，UDP 发出）→ 网线 → 米联客 DR1M90 开发板（Linux + NPU）接收视频流 → JPU 硬解 → NPU 跑神经网络 → HDMI 输出结果。
> **编写日期**：2026-10-30
> **当前进度**：Ubuntu 虚拟机已就绪；板载系统/NPU 驱动/应用均未开始。

---

## 0. 整体架构（先看这个，别搞错数据流）

```
Zynq-7020 图传板                        米联客 MLK-F3P-CZ02 (DR1M90)
OV5640 → JPEG 编码                       ┌────────────────── PS 端 (ARM Cortex-A9, Linux) ──────────────────┐
lwIP UDP 发送                            │                                                                  │
192.168.1.10  ────网线────►  PS 千兆网口 GEM (MIO16-27, PHY YT8531)   │
(1024 字节/包 JPEG 裸流,                │   → Linux 内核 UDP/IP 协议栈收包                                │
 FFD8/FFD9 分帧)                         │   → 用户态拼 JPEG 帧                                      │
                                          │                                                                  │
                                          │   ┌──────────────── PL 端 (FPGA 硬件 IP) ────────────────┐    │
                                          │   │                                                    │    │
                                          │   │  JPU (硬解 JPEG) ──DMA──► DDR RGB                   │    │
                                          │   │                        ▲                          │    │
                                          │   │  NPU (512 MAC, 硬核算 Conv/FC) ◄───DMA──┘          │    │
                                          │   │                        │                          │    │
                                          │   │  Soft NPU (Pool/Upsample/Yolo后处理)                │    │
                                          │   │                        │                          │    │
                                          │   │  VDMA + hdmitx IP ────► Framebuffer ───────────────┼────┘
                                          │   └────────────────────────────────────────────────────┘
                                          │                                                                  │
                                          │   应用层 (用户态 C++):                                             │
                                          │     recv_udp() → jpu_decode() → npu_infer() → draw_box() → fb  │
                                          └──────────────────────────────────────────────────────────────────┘
```

**关键认知（你之前理解错的地方）**：
- UDP 包是进 **PS 端千兆网口**，由 Linux 内核协议栈处理，**不用在 PL 端做以太网解码**；
- PL 端只放三个固定 IP：**JPU（JPEG 硬解）、NPU（512 MAC 推理）、hdmitx+VDMA（HDMI 输出）**；
- PS 和 PL 之间靠 AXI-DMA 在 DDR 里搬数据，不占 CPU；
- 你写的业务代码全在 **PS 端 Linux 用户态**，用 C++ 调 NPU 驱动 API，不用碰 FPGA 逻辑。

---

## 1. 硬件与网络参数

| 项目 | 值 |
|---|---|
| Zynq 发送板 IP | `192.168.1.10`，本地端口 5002 |
| DR1 接收板 IP | `192.168.1.100/24`（PS 网口 eth0） |
| 数据格式 | 1024 字节/包，无包头 JPEG 裸流（`FFD8` 起 / `FFD9` 止） |
| Zynq 目标 IP | **必须改成 `192.168.1.100`**（改 `udp_perf_server.h` 里 `UDP_DEST_IP_*`，重新编译下载） |
| NPU 规格 | 512 MAC 硬核（Conv/FC）+ 软核（Pool/Upsample/Yolo），INT8/UINT8，~1 TOPS |
| 显示 | PL hdmitx IP → HDMI，最大 1080p60 |

---

## 2. 第一步：按官方 NPU demo 流程把系统烧起来

> 这一步完全照搬官方 PDF《05-5_米联客-安路F3P-CZ02开发板NPU开发》，不自己创新。目标：板子能启动 Linux，NPU 驱动加载，官方 face_detection 能跑。

### 2.1 准备 Ubuntu 虚拟机环境

你已经有 Ubuntu 了，确认装齐：

```bash
# 在 Ubuntu 里
sudo apt install -y build-essential cmake git libncurses5-dev \
                      bison flex libssl-dev device-tree-compiler \
                      python3-pip gcc-aarch64-linux-gnu
# cmake 必须 ≥ 3.21.2（官方 demo 要求）
cmake --version
```

### 2.2 拷贝米联客 SDK 包到虚拟机

把官方资料包 `01-start-02_start_linux-05_application_demo-05-5_NPU演示-demo-soc_prj` 整个拷进 Ubuntu，路径不要有中文空格。

### 2.3 导出硬件文件（在 Windows 上用 TangDynasty）

1. 打开 `demo-soc_prj\soc_prj.al`；
2. `Project → Export Hardware Platform File`，勾选 **Include bitstream**，导出到 `F:\work\soc_hw\system.hpf`；
3. 把 `system.hpf` 拷进 Ubuntu 虚拟机。

### 2.4 生成 FSBL（在 FutureDynasty IDE 里）

1. FD 软件新建 workspace `F:/work/soc_sdk`；
2. `File → New → Platform Project`，名字 `soc_base`，选 `system.hpf`；
3. `File → New → Application Project`，名字 `soc_fsbl`，模板选 **FSBL**；
4. 右键 Build，生成 `soc_fsbl.elf` 和 `system.bit`。

### 2.5 编译 Linux 内核 + 镜像

按官方 PDF 第 9~12 页操作：

```bash
# 在 Ubuntu 虚拟机里
cp soc_fsbl.elf system.bit ~/uisrc-lab-anlogic/boards/files/
cp -r kernel-dts uboot-dts ~/uisrc-lab-anlogic/boards/files/
cp anlogic-dr1m90-softip.dts ~/uisrc-lab-anlogic/sources/linux/arch/arm64/boot/dts/anlogic/

# 加 framebuffer 和 NPU 驱动（按官方 PDF 第 9-11 页 Kconfig/Makefile 改完）
cd ~/uisrc-lab-anlogic/scripts
source drcfg.sh
make_kernel_menuconfig.sh   # 按 PDF 勾选：Anlogic framebuffer / NPU related Modules / JPU anlogic
move_files.sh
make_uboot.sh
make_kernel.sh
create_image.sh             # 选 parameter-tf-fat.txt（序号 0）
```

### 2.6 烧录 TF 卡

把生成的镜像烧到 TF 卡（BalenaEtcher），拨码拨到 **SD Card 模式**（SW1=ON, SW2=OFF, SW3=ON），插卡上电，串口 115200 看启动日志。

### 2.7 跑通官方 face_detection demo

```bash
# 板子上
tar zxvf face_detection.tar.gz
cd face_detection
chmod 755 build.sh
./build.sh
cd rootfs/root
./face_detection   # 接 MIPI 摄像头 + HDMI，应该能看到人脸框
```

**这一步必须先跑通**，确认 NPU 驱动、JPU、Framebuffer、HDMI 全链路正常。跑不通不要往下做。

---

## 3. 第二步：板子联网，改 Zynq 目标 IP

### 3.1 配 DR1 板 PS 网口 IP

```bash
# 板子上，串口登录后
vi /etc/network/interfaces
# auto eth0
# iface eth0 inet static
#     address 192.168.1.100
#     netmask 255.255.255.0
#     gateway 192.168.1.1
ifdown eth0 && ifup eth0
ip addr show eth0
```

### 3.2 改 Zynq 发送端目标 IP

在 PC 的 Vitis 工程里，改 `udp_perf_server.h`：

```c
#define UDP_DEST_IP_0    192
#define UDP_DEST_IP_1    168
#define UDP_DEST_IP_2    1
#define UDP_DEST_IP_3    100   // 原来是 102，改成 DR1 的 IP
```

重新编译、下载 Zynq，串口看到 `UDP video stream started: port 5002 -> 192.168.1.100:5002`。

### 3.3 板子上验证收包

```bash
# 板子上
apt install tcpdump
tcpdump -i eth0 udp port 5002 -c 20
# 看到 length 1024 的包就 OK
```

---

## 4. 第三步：把视频源从 MIPI 摄像头换成 UDP 收包

官方 demo 是读 `/dev/video0`（MIPI 摄像头）。你要改成从 UDP 收 JPEG 流。

### 4.1 在板子上建工程目录

```bash
mkdir -p /root/udp_npu && cd /root/udp_npu
```

### 4.2 UDP 收包 + JPEG 拼帧

参考你 PC 上已经跑通的 `udp_video_station.py` 的拼帧逻辑（FFD8 起 / FFD9 止），在板子上用 C++ 写：

```cpp
// udp_recv.hpp
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string>
#include <deque>

class UdpJpegReceiver {
    int sock_;
    struct sockaddr_in addr_;
    std::string buf_;
public:
    UdpJpegReceiver(int port = 5002) {
        sock_ = socket(AF_INET, SOCK_DGRAM, 0);
        int rcvbuf = 4 * 1024 * 1024;
        setsockopt(sock_, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
        addr_.sin_family = AF_INET;
        addr_.sin_addr.s_addr = htonl(INADDR_ANY);
        addr_.sin_port = htons(port);
        bind(sock_, (struct sockaddr*)&addr_, sizeof(addr_));
    }
    // 收一包，往 buf_ 追加，返回拼好的完整 JPEG（没有就返回空）
    std::string recv_frame() {
        char pkt[1024];
        int n = recvfrom(sock_, pkt, sizeof(pkt), 0, nullptr, nullptr);
        if (n > 0) buf_.append(pkt, n);
        // FFD8 起 / FFD9 止
        size_t s = buf_.find("\xff\xd8");
        if (s == std::string::npos) { buf_.clear(); return ""; }
        size_t e = buf_.find("\xff\xd9", s + 2);
        if (e == std::string::npos) { buf_ = buf_.substr(s); return ""; }
        std::string jpg = buf_.substr(s, e - s + 2);
        buf_ = buf_.substr(e + 2);
        return jpg;
    }
};
```

### 4.3 用 JPU 硬解 JPEG（不要用 CPU 软解）

DR1 内核已经开了 `JPU anlogic`（见官方 PDF 第 11 页）。JPU 通常暴露为 `/dev/video1x`（V4L2 M2M 设备）。

```bash
# 板子上确认 JPU 节点
ls /dev/video*
v4l2-ctl --device=/dev/video11 --info 2>/dev/null   # 看是不是 JPEG 解码器
```

JPU 解码流程（V4L2 M2M）：
1. 把 JPEG 帧喂到 OUTPUT 队列；
2. DST 队列拿解码后的 YUV/RGB 帧（DDR 里的物理地址）；
3. 这个 RGB 帧**直接就是 NPU 的输入**，不用再拷一份。

> 如果官方 demo 里已经有 JPU 解码的封装（face_detection 里读 MIPI 摄像头时应该走了 ISP→JPU 路径），直接复用它的 JPU 模块。

---

## 5. 第四步：接 NPU 推理

### 5.1 先跑官方 face_detection 看 API 怎么调

```bash
cd /root/face_detection
ls src/   # 看官方怎么调 NPU API
cat src/*.cpp | head -200
```

重点看三件事：
1. 怎么初始化 NPU（`hard_npu_driver` open / mmap）；
2. 怎么把一帧图像喂进去（输入 tensor 的地址、shape、量化参数 scale/zero_point）；
3. 怎么拿输出（YOLO 后处理是软核做还是 CPU 做）。

### 5.2 换成自己的模型

推荐 **YOLOv8n INT8，输入 320×320**（512 MAC 算力下能跑 10~15fps）：

```bash
# PC 上（或 Ubuntu 虚拟机里）
pip install ultralytics
yolo export model=yolov8n.pt format=onnx imgsz=320
# 然后用米联客提供的模型转换工具（在 SDK 包里，类似 anlogic_npu_converter）
# 把 ONNX 转成 .nb / .anlogic 格式
# 量化方式 INT8，校准集用你自己数据的代表性图片 100~200 张
```

模型类别建议先做两类：
- `person`（人）
- `fall_down`（跌倒）——你自己采集数据标注训练。

### 5.3 推理循环伪代码

```cpp
#include "udp_recv.hpp"
// #include "npu_api.h"   // 米联客提供的头文件

int main() {
    UdpJpegReceiver udp(5002);
    // NPU_init("yolov8n_fall_int8.anlogic");   // 官方 API 名字以 SDK 为准

    while (true) {
        std::string jpg = udp.recv_frame();
        if (jpg.empty()) continue;

        // 1. JPU 硬解 JPEG → DDR 里 RGB 帧
        Frame rgb = jpu_decode(jpg);   // 物理地址指针，直接给 NPU

        // 2. 缩放到 320×320（JPU 或 PL 缩放 IP 做，不要用 CPU）
        Frame input = resize_to_320(rgb);

        // 3. NPU 推理
        NpuOutput out = npu_infer(input);   // DMA 自动搬，不占 CPU

        // 4. PS 用户态画框（OpenCV 或直接写 Framebuffer）
        draw_boxes(rgb, out);

        // 5. 送 Framebuffer 显示
        fb_show(rgb);
    }
}
```

---

## 6. 第五步：HDMI 显示

官方 demo 用 `/dev/fb0` framebuffer：

```bash
# 板子上确认
ls /dev/fb0
cat /sys/class/graphics/fb0/virtual_size   # 看分辨率
```

应用程序把画好框的 RGB 帧直接 `write()` 到 `/dev/fb0`，PL 的 VDMA + hdmitx IP 自动送 HDMI。不需要你写任何 PL 显示逻辑。

---

## 7. 最终 pipeline 总览

```
[Zynq OV5640]
   │ JPEG 1024B/UDP
   ▼
[DR1 PS GEM 网口] ── Linux 内核 UDP/IP
   │
   ▼
[用户态] udp_recv.cpp 拼 FFD8/FFD9 帧
   │
   ▼
[PL JPU] 硬解 JPEG → DDR RGB         ← 不占 CPU
   │
   ▼
[PL NPU] 512 MAC INT8 YOLOv8n 推理   ← ~10-15fps
   │
   ▼
[用户态] 解析检测结果，画框
   │
   ▼
[PL VDMA+hdmitx] Framebuffer → HDMI
```

---

## 8. 里程碑与排期建议

| 阶段 | 任务 | 预计耗时 |
|---|---|---|
| M1 | 按官方 PDF 烧系统，跑通 face_detection demo | 2~3 天 |
| M2 | 板子配网，Zynq 目标 IP 改成 DR1，tcpdump 收到包 | 半天 |
| M3 | UDP 拼帧 + JPU 解码，能在 HDMI 看到原始视频（不推理） | 1~2 天 |
| M4 | 把 face_detection 的 NPU 调用接到 UDP 源上，跑通人脸检测 | 1 天 |
| M5 | 训练自己的 YOLOv8n 跌倒检测 INT8 模型，用转换工具转格式 | 3~5 天（依赖数据） |
| M6 | 替换模型，调优帧率，写启动脚本 | 1~2 天 |

---

## 9. 常见坑

| 现象 | 原因 | 解决 |
|---|---|---|
| tcpdump 收不到包 | Zynq 目标 IP 没改成 .100 | 改 `udp_perf_server.h` 重编 |
| 收到包但解不出帧 | Zynq DMA 每包 1031 字节 | 已修：`MAX_PKT_LEN=1024` |
| NPU 推理没结果 | 模型没转 INT8 / 量化 scale 不对 | 用官方转换工具重转，看 demo 的量化参数 |
| 帧率上不去 | 用了 CPU 软解 JPEG | 改用 JPU；缩放过 NPU 不要用 OpenCV CPU |
| HDMI 黑屏 | fb0 权限/分辨率 | `chmod 666 /dev/fb0`，看 `fb0/virtual_size` |
| UDP 丢包花屏 | socket 缓冲太小 | `SO_RCVBUF` 加到 4MB，丢旧帧 |
| NPU 驱动没加载 | 内核没开 `hard_npu_driver` | `make_kernel_menuconfig.sh` 里勾选 |

---

## 10. 你现在要做的第一件事

**不要急着写 UDP 代码**。先按官方 PDF 第 2.3~2.7 节，在你的 Ubuntu 虚拟机里把整个系统编出来、烧到板子上、把 `face_detection` 官方 demo 跑起来（接 MIPI 摄像头和 HDMI）。这一步通了，说明：
- NPU 驱动 OK；
- JPU OK；
- Framebuffer/HDMI OK；
- 交叉编译环境 OK。

这一步卡住了后面全是白搭。跑通之后告诉我，我再帮你把 MIPI 摄像头那部分替换成 UDP 收包。
