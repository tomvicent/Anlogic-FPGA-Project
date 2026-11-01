# Zynq OV5640 UDP → DR1M90 NPU 人脸识别项目实施方案

> **目标**：Zynq-7020 采集 OV5640 JPEG → UDP 发送 → DR1M90（Linux）接收 → JPU/CPU 解码 → NPU 推理 → HDMI 显示检测/识别结果。  
> **编写日期**：2026-10-30  
> **说明**：本文在早期方案基础上，按 `Linux/npu` 目录里的实际 demo、驱动、模型和 Zynq 发送端源码更新；
> 代码/命令未在板子上逐条实测，IP、路径、脚本名请以实际环境为准。  
> **关联文档**：
> - `Linux/npu/NPU硬核使用指南.md`（NPU 驱动、ArmNN、demo 的详细说明）
> - `Vitis/UDP/UDP_CAMERA_开发记录.md`（Zynq 发送端实现）
> - `Vitis/UDP/DR1板子_UDP视频AI推理_项目说明书.md`（早期方案）
> - `Vitis/UDP/DR1板子_UDP视频显示_开发记录.md`（PC→DR1 原始 BGRX 显示联调）
> - `Vitis/UDP/上位机/README.md`（PC 端 JPEG 接收）

---

## 0. 先对齐 5 个概念（不然后面一定走弯路）

1. **NPU 不在 Zynq 上，在 DR1M90 上。**  
   Zynq 的 PL 只做 OV5640 采集、FIFO、AXI DMA 和 lwIP UDP 发送。  
   NPU 加速发生在 DR1M90：PS 里的硬核 NPU + PL 里的 Soft NPU（`Video_NPU`）。

2. **UDP 包进入的是 DR1M90 的 PS 千兆网口，由 Linux 内核协议栈收包。**  
   不需要在 PL 里实现以太网 MAC/协议栈；PL 里放的是 JPU、NPU、VDMA、HDMI 这些固定 IP。

3. **“人脸检测”≠“人脸识别”。**  
   官方 demo 自带的 `yolo_face_uint8_15.onnx` 只输出人脸框（1 类 `face`），它不知道“这是谁”。  
   要识别身份，需要第二阶段：人脸对齐 + embedding 模型（MobileFaceNet/ArcFace）+ 人脸库比对。

4. **Zynq 现在发的是 JPEG，不是原始 RGB。**  
   DR1 必须先把 JPEG 解码成 BGR/YUV，才能喂 NPU。  
   之前 PC→DR1 的 BGRX 直写 fb0 只是“显示联调”，协议和 JPEG 流不一样，不要混用。

5. **先跑通官方 demo，再改代码。**  
   在 DR1 上接 MIPI/USB 摄像头，把 `face_detection` 跑出人脸框，证明 NPU 驱动、JPU、HDMI、交叉编译都正常。  
   这一步不通，后面换 UDP 数据源只会把问题搅在一起。

> **关于模型选择的提醒**：`DR1板子_UDP视频AI推理_项目说明书.md` 里建议自己训练
> YOLOv8n 320×320。那是 M5 之后的事，而且需要额外的模型转换/量化风险。
> **M0~M4 请先用官方自带的 `yolo_face_uint8_15.onnx`（416×416）把链路跑通**，
> 不要一上来就换模型；否则 NPU 驱动问题和模型转换问题会混在一起，很难定位。

---

## 1. 系统总览

```text
┌──────────────────────────── Zynq-7020（图传板） ────────────────────────────┐
│  OV5640（硬件 JPEG 模式，640×480）                                          │
│      │ DVP 8-bit JPEG 字节流                                               │
│      ▼                                                                      │
│  ov5640_data_8b → Video In to AXI4-Stream → AXIS FIFO                      │
│      │                                                                      │
│      ▼                                                                      │
│  AXI DMA（S2MM）→ DDR 缓冲区                                               │
│      │                                                                      │
│      ▼                                                                      │
│  lwIP UDP：1024 字节/包，无包头，目标 192.168.1.100:5002                   │
└──────────────────────────────────────────────────────────────────────────────┘
                                   │ 网线
                                   ▼
┌──────────────────────────── DR1M90（MLK-F3P-CZ02） ─────────────────────────┐
│  PS：Linux（Ubuntu 20.04 / Anlogic Linux）                                  │
│      eth0（YT8531，1Gbps）                                                  │
│        │                                                                    │
│        ▼                                                                    │
│  用户态 UDP 收包 → 按 FFD8/FFD9 拼完整 JPEG                                 │
│        │                                                                    │
│        ├── 方案 A（先做）：OpenCV cv::imdecode → BGR                         │
│        └── 方案 B（提速）：JPU 硬解 → YUV422                                 │
│        │                                                                    │
│        ▼                                                                    │
│  resize / 量化 → NPU（Alnpu 后端）→ YOLO 后处理                             │
│        │                                                                    │
│        ├── 画框 → /dev/fb0 → HDMI                                          │
│        └── 结果 JSON → UDP → PC/Zynq（可选）                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 网络与协议参数

| 项目 | 当前值 | 说明 |
|---|---|---|
| Zynq 板 IP | `192.168.1.10/24` | `main.c` 里写死 |
| Zynq 目标 IP | `192.168.1.102` | `udp_perf_server.h` 里写死，**要改成 DR1 的 IP** |
| DR1 板 IP | 建议 `192.168.1.100/24` | 以板子 `ip addr` 为准 |
| PC（调试）IP | `192.168.1.102/24` | 和 Zynq 目标 IP 一致时可直接用 PC 接收 |
| 端口 | 5002 | 收发同端口 |
| 每包负载 | 1024 字节 | 无包头 |
| 数据内容 | JPEG 裸流 | `FF D8` 开头，`FF D9` 结尾，帧长可变 |
| 摄像头分辨率 | 640×480 | `main.c` 里 `cmos_h_pixel=640`、`cmos_v_pixel=480` |
| 帧率 | 约 15~30 fps | 取决于 JPEG 质量、网口、接收端 |

> 两套 IP 方案，二选一，不要混：
>
> - **直连方案（推荐）**：Zynq `192.168.1.10`，DR1 `192.168.1.100`，PC 可选 `192.168.1.102`；三者同一交换机或 Zynq↔DR1 直连。
> - **PC ICS 方案**：DR1 `192.168.137.100`，PC `192.168.137.1`，Zynq 需要改成 `192.168.137.x` 并把目标 IP 改成 DR1。  
>   之前的显示联调用的是 ICS，地址是 `192.168.137.x`，现在 Zynq 发送端默认是 `192.168.1.x`，_**上电前先统一网段**_。

---

## 2. 当前基础与缺口

### 2.1 已经跑通的

| 链路 | 状态 | 证据 |
|---|---|---|
| Zynq OV5640 JPEG → UDP → PC | 已跑通 | `UDP_CAMERA_开发记录.md`、`上位机/README.md` |
| PC 摄像头 → UDP BGRX → DR1 fb0 | 已跑通 | `DR1板子_UDP视频显示_开发记录.md` |
| DR1 Linux、SSH、HDMI/fb0 | 已跑通 | 同上 |
| DR1 NPU 官方 demo | **未开始/未验证** | 早期方案文档写明“板载系统/NPU 驱动/应用均未开始” |

### 2.2 还缺的

1. DR1 上 NPU 驱动/设备节点确认；
2. 官方 `face_detection` demo 在 DR1 上跑通；
3. DR1 接收 Zynq 的 JPEG 流并用 C++ 拼帧；
4. 把 demo 的摄像头输入替换成 UDP 输入；
5. 640×480 画面适配 1920×1080 framebuffer；
6. 性能/丢包/稳定性；
7. （可选）真正的人脸识别模型和流程。

---

## 3. 推荐路线：M0 → M6

> 不要跳步。每一步都有明确的验收标准，过不了就停下来查。

### M0：在 DR1 上跑通官方 face_detection

**目标**：不接 Zynq，先用 MIPI 或 USB 摄像头，让官方 demo 在 HDMI 上出人脸框。

步骤：

```bash
# 1. 把 face_detection.tar.gz 拷到板子
# PC:
scp D:\FPGA\Linux\npu\sdk\face_detection.tar.gz uisrc@192.168.1.100:/home/uisrc/

# 2. 板子上解压（注意：tar 里自带 app/ 前缀，解压到 /home/uisrc 才会得到
#    /home/uisrc/app/face_detection，和 build.sh 里的路径一致）
cd /home/uisrc
tar zxvf face_detection.tar.gz
cd /home/uisrc/app/face_detection

# 3. 编译（在 Ubuntu VM 里做；如果板子上已经有 rootfs/root 可跳过）
#    ./build.sh 会生成 build/bin/yolo_demo_hdmi_camera 和 rootfs/root/
#    注意 build.sh 里的路径/编译器要改成你的实际路径
#    见《NPU硬核使用指南》第 6 节

# 4. 确认设备节点
ls -l /dev/hard_npu /dev/soft_npu /dev/cma_mem /dev/jpu /dev/fb0
lsmod | grep -E 'npu|cma|jpu|mipicam'
dmesg | grep -iE 'npu|jpu|cma'

# 5. 进入运行目录（build.sh 生成的 rootfs/root）
cd /home/uisrc/app/face_detection/rootfs/root
export LD_LIBRARY_PATH=$PWD/armnn_lib/lib:$PWD/ffmpeg_opencv4.7.0_aarch64/lib:$LD_LIBRARY_PATH

# 6. 跑 MIPI 摄像头（或 USB）
sudo systemctl stop gdm
sudo ./scripts/run_mipicam_fb.sh
# 或：
# sudo ./bin/yolo_demo_hdmi_camera \
#   -m ./inputs/yolo_face_uint8_15.onnx \
#   -u ./inputs/example_yolo_face.json \
#   -s 192.168.1.102:12345 -i /dev/mipicam -o /dev/fb0
```

**验收标准**：

- HDMI 上能看到实时画面和人脸框；
- 终端日志里有 `npu` 阶段的独立耗时，FPS 合理；
- `dmesg` 没有 NPU timeout / JPU error；
- 不接网线也能跑（这一步只验证 NPU/JPU/显示）。

> 这一步如果卡住，先查《NPU硬核使用指南》第 9 节，不要继续写 UDP 代码。

---

### M1：网络打通

**目标**：DR1 能收到 Zynq 的 1024 字节 JPEG 包。

1. 统一网段（以直连方案为例）：
   - Zynq：`192.168.1.10/24`
   - DR1：`192.168.1.100/24`
   - PC（可选）：`192.168.1.102/24`

2. 改 Zynq 目标 IP：

   ```c
   // Vitis/UDP/prj/udp_camera/vitis/udp_camera/src/udp_perf_server.h
   #define UDP_DEST_IP_0   192
   #define UDP_DEST_IP_1   168
   #define UDP_DEST_IP_2   1
   #define UDP_DEST_IP_3   100   // 原来是 102，改成 DR1 的 IP
   ```

   重新编译、下载 Zynq。串口应打印：

   ```text
   UDP video stream started: port 5002 -> 192.168.1.100:5002
   ```

3. DR1 上抓包：

   ```bash
   # 板子上
   sudo ip addr add 192.168.1.100/24 dev eth0 2>/dev/null || true
   sudo ip link set eth0 up
   ping -c 3 192.168.1.10
   sudo tcpdump -i eth0 udp port 5002 -c 20
   ```

   看到 1024 字节左右的 UDP 包就说明链路通了。

4. 如果板子没有 `tcpdump`，用 Python 数包：

   ```python
   import socket, time
   s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
   s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4*1024*1024)
   s.bind(("0.0.0.0", 5002))
   s.settimeout(3)
   n = 0; total = 0; t0 = time.time()
   while n < 50:
       try:
           d, _ = s.recvfrom(2048)
       except socket.timeout:
           break
       n += 1; total += len(d)
   print("packets", n, "bytes", total, "elapsed", time.time()-t0)
   ```

**验收标准**：DR1 持续收到 1024 字节包，速率与 Zynq 串口打印的 `tx` 计数一致。

---

### M2：DR1 收 JPEG、拼帧、存盘（先不接 NPU）

**目标**：证明 DR1 能把 1024 字节裸流拼成完整 JPEG。  
先不引入 OpenCV，用 Python 标准库存 10 帧，scp 回 PC 用图片查看器打开。

```python
# /home/uisrc/jpeg_saver.py
import socket

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
s.bind(("0.0.0.0", 5002))
print("listening 5002 ...")

buf = b""
n = 0
while n < 10:
    pkt, _ = s.recvfrom(2048)
    buf += pkt

    # 找 FFD8
    start = buf.find(b"\xff\xd8")
    if start < 0:
        buf = buf[-1:]          # 保留最后一个字节，防止 FFD8 被切断
        continue
    if start > 0:
        buf = buf[start:]       # 丢掉帧头前的垃圾

    # 找 FFD9
    end = buf.find(b"\xff\xd9", 2)
    if end < 0:
        if len(buf) > 4 * 1024 * 1024:
            buf = b""           # 防止异常流把内存吃光
        continue

    jpg = buf[:end + 2]
    buf = buf[end + 2:]
    name = f"/tmp/frame_{n:03d}.jpg"
    with open(name, "wb") as f:
        f.write(jpg)
    print(name, len(jpg))
    n += 1
```

运行：

```bash
python3 /home/uisrc/jpeg_saver.py
# 然后 scp /tmp/frame_*.jpg 回 PC 查看
```

**验收标准**：

- 10 张 JPEG 都能在 PC 上正常打开；
- 连续帧之间画面在变化；
- 如果没有一帧完整，说明包丢失/字节流被破坏，先查 Zynq 的 `MAX_PKT_LEN` 和 UDP 发送长度是否都是 1024。

> 这一步只验证“收包 + 拼帧”，不验证颜色、不验证 NPU。

---

### M3：把 UDP 变成 demo 的“摄像头”

**目标**：不接 MIPI/USB 摄像头，让 `yolo_demo_hdmi_camera` 从 UDP 拿帧，HDMI 上出现人脸框。

核心改动只有 3 处：

1. 新增 `udp_camera_t`（实现 `icamera` 接口）；
2. `main.cpp` 里当输入是 `udp` 时创建它；
3. `solution::task_resize` 里增加 `channel()==3` 的分支。

#### 3.1 `udp_camera.hpp` / `udp_camera.cpp`

放到 `src/npu_flow/utils/media/` 下（`CMakeLists.txt` 的 `file(GLOB ... utils/media/*.cpp)` 会自动收录）。

```cpp
// udp_camera.hpp
#pragma once
#include "icamera.hpp"
#include <opencv2/opencv.hpp>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>
#include <string>
#include <cerrno>

class udp_camera_t : public icamera {
public:
    udp_camera_t(int w, int h, int port = 5002) : m_w(w), m_h(h) {
        m_fd = ::socket(AF_INET, SOCK_DGRAM, 0);
        if (m_fd < 0) { perror("socket"); return; }

        int rcvbuf = 4 * 1024 * 1024;
        setsockopt(m_fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(port);
        if (bind(m_fd, (sockaddr *)&addr, sizeof(addr)) < 0) {
            perror("bind");
            ::close(m_fd);
            m_fd = -1;
        }
    }

    ~udp_camera_t() override {
        if (m_fd >= 0) ::close(m_fd);
    }

    void open(const char *) override {}          // 构造时已经打开
    bool is_open() override { return m_fd >= 0; }
    int width() override { return m_w; }
    int height() override { return m_h; }
    int channel() override { return 3; }         // BGR，3 字节/像素
    size_t buffer_size() override { return (size_t)m_w * m_h * 3; }

    void SubmitAndStart(uint64_t /*dma_rx_buf*/, void *rx_buf) override {
        m_err = 0;
        while (is_open()) {
            std::string jpg = recv_one_frame();
            if (jpg.empty()) break;             // socket 出错/关闭
            if (jpg.size() < 4) continue;

            cv::Mat raw(1, (int)jpg.size(), CV_8UC1, (void *)jpg.data());
            cv::Mat bgr = cv::imdecode(raw, cv::IMREAD_COLOR);
            if (bgr.empty()) {
                // UDP 丢包导致的坏帧：丢掉，继续等下一帧，不要停整个程序
                continue;
            }

            cv::Mat dst(m_h, m_w, CV_8UC3, rx_buf);
            if (bgr.size() == dst.size()) {
                bgr.copyTo(dst);
            } else {
                cv::resize(bgr, dst, dst.size());
            }
            return;
        }
        m_err = -1;
    }

    int WaitFinish() override { return m_err; }

private:
    int m_fd = -1;
    int m_w = 640, m_h = 480;
    int m_err = 0;
    std::string m_buf;

    std::string recv_one_frame() {
        char pkt[2048];
        while (is_open()) {
            ssize_t n = ::recv(m_fd, pkt, sizeof(pkt), 0);
            if (n < 0) {
                if (errno == EINTR) continue;
                perror("recv");
                return {};
            }
            m_buf.append(pkt, (size_t)n);

            // 上限保护，防止异常流撑爆内存
            if (m_buf.size() > 4 * 1024 * 1024) {
                size_t s = m_buf.find("\xff\xd8");
                m_buf = (s == std::string::npos) ? std::string() : m_buf.substr(s);
                if (m_buf.size() > 4 * 1024 * 1024) m_buf.clear();
            }

            size_t start = m_buf.find("\xff\xd8");
            if (start == std::string::npos) {
                if (!m_buf.empty()) m_buf.erase(0, m_buf.size() - 1);
                continue;
            }
            if (start > 0) m_buf.erase(0, start);

            size_t end = m_buf.find("\xff\xd9", 2);
            if (end == std::string::npos) continue;

            std::string jpg = m_buf.substr(0, end + 2);
            m_buf.erase(0, end + 2);
            return jpg;
        }
        return {};
    }
};
```

> **注意**：
> - 这个类假设 UDP 端口是 5002、摄像头是 640×480；和 Zynq 发送端保持一致。
> - `cv::imdecode` 用的是 demo 自带的 OpenCV（`LD_LIBRARY_PATH` 要指到 `ffmpeg_opencv4.7.0_aarch64/lib`）。
> - 如果 JPEG 解码失败（丢包导致帧不完整），`imdecode` 返回空，这一帧被丢弃，下一帧重新同步。
> - 如果实际解码尺寸不是 640×480，`cv::resize` 会兜底；但最好让 Zynq 和 `udp_camera_t` 一致。

#### 3.2 `main.cpp` 里选择 UDP 源

在 `main.cpp` 的 `enumerate_device` 处改成：

```cpp
std::shared_ptr<icamera> m_camera;
std::string input = parser.get<std::string>("input");

if (input == "udp") {
    // 640x480、端口 5002，按你的实际情况改
    m_camera = std::make_shared<udp_camera_t>(640, 480, 5002);
} else {
    m_camera = icamera::enumerate_device(
        input.c_str(),
        parser.get<std::string>("geometry").c_str());
}
```

并在文件顶部：

```cpp
#include "udp_camera.hpp"
```

`cfg.input = input;` 保持不变。

#### 3.3 `solution.cpp` 里增加 3 通道分支

原始代码只处理 `channel()==4`（MIPI BGRA）和 `channel()==2`（USB/JPU YUYV）。  
我们的 UDP 摄像头是 BGR 3 通道，需要加：

```cpp
void solution::task_resize(std::shared_ptr<task_context> p) {
    LOG_TRACE("idx{}: task_resize()", p->work_idx);
    p->time_infos.push_back({"resize", std::chrono::system_clock::now()});
    cv::Mat pic(m_camera->height(), m_camera->width(),
                CV_8UC(m_camera->channel()), m_cmabuf[p->work_idx]->virt_addr);

    switch (m_camera->channel()) {
    case 3: {
        cv::Mat tmp;
        cv::resize(pic, tmp, {(int)get_input_width(), (int)get_input_height()});
        // pic 是 BGR packed，prepare_input_data 会转成 RGB planar 并量化
        prepare_input_data(tmp.data, tmp.rows, tmp.cols, m_npu_quant_param,
                           (uint8_t *)m_executor->GetInputBuffer(0, p->work_idx)->virt_addr);
    } break;
    case 4: {
        // 原来的 MIPI 分支
        cv::Mat tmp;
        cv::resize(pic, tmp, {(int)get_input_width(), (int)get_input_height()});
        cv::cvtColor(tmp, tmp, cv::COLOR_BGRA2BGR);
        prepare_input_data(tmp.data, tmp.rows, tmp.cols, m_npu_quant_param,
                           (uint8_t *)m_executor->GetInputBuffer(0, p->work_idx)->virt_addr);
    } break;
    case 2:
        // 原来的 USB/JPU YUYV 分支
        soft_resize_yuv422_to_rgb_plane(
            pic.data,
            (uint8_t *)m_executor->GetInputBuffer(0, p->work_idx)->virt_addr,
            pic.rows, pic.cols, get_input_height(), get_input_width());
        break;
    default:
        throw std::runtime_error("not support channel");
    }

    p->time_infos.back().end = std::chrono::system_clock::now();
}
```

同时在 `task_camera` 里，CPU 写完 UDP 解码结果后，建议加一次同步（demo 的 CMA 通常是 coherent，加一次更稳）：

```cpp
if (m_camera->WaitFinish()) {
    LOG_ERROR("m_camera->WaitFinish timeout");
    m_stop_flag = true;
}
m_cmabuf[p->work_idx].sync_device();    // CPU 写 -> NPU/HDMI DMA 读
                                       // 注意：CmaBuf 的 sync_device 是对象方法，用 "." 不是 "->"
```

#### 3.4 显示：640×480 不能直接 memcpy 到 1920×1080 的 fb

这是最容易踩的坑。

- `driver/anlogic-vdmafb.c` 里 `bits_per_pixel = 24`、`line_length = hactive * 3`、RGB888；
- 但你之前 PC→DR1 的 `fb_rgb_viewer.py` 用的是 `1920×1080×4`（BGRX 32bpp）；
- demo 的 `hdmi_framebuffer_t::show()` 在 `channel==3` 时直接 `memcpy(width*height*3)`，**它假设源图尺寸 == fb 尺寸**；如果源图是 640×480、fb 是 1920×1080，会越界读/显示错位。

所以先查实际 fb 格式：

```bash
cat /sys/class/graphics/fb0/bits_per_pixel
cat /sys/class/graphics/fb0/virtual_size
cat /sys/class/graphics/fb0/stride
```

然后二选一：

**方案 1（推荐）：用 letterbox 函数把 640×480 画到 1920×1080 中间。**

```cpp
// fb_display.hpp
#pragma once
#include <opencv2/opencv.hpp>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>
#include <unistd.h>
#include <cstring>
#include <cstdio>
#include <algorithm>

class FbDisplay {
public:
    bool open(const char *dev = "/dev/fb0") {
        fd_ = ::open(dev, O_RDWR);
        if (fd_ < 0) { perror("open fb"); return false; }
        ioctl(fd_, FBIOGET_VSCREENINFO, &var_);
        ioctl(fd_, FBIOGET_FSCREENINFO, &fix_);
        size_ = fix_.smem_len;
        mem_ = (uint8_t *)mmap(nullptr, size_, PROT_READ | PROT_WRITE,
                               MAP_SHARED, fd_, 0);
        if (mem_ == MAP_FAILED) { perror("mmap fb"); return false; }
        printf("fb %dx%d bpp=%d stride=%d\n",
               var_.xres, var_.yres, var_.bits_per_pixel, fix_.line_length);
        return true;
    }

    void show_letterbox(const cv::Mat &bgr) {
        if (!mem_) return;
        const int W = var_.xres, H = var_.yres;
        const double scale = std::min((double)W / bgr.cols, (double)H / bgr.rows);
        const int dw = std::max(1, (int)(bgr.cols * scale));
        const int dh = std::max(1, (int)(bgr.rows * scale));
        const int x0 = (W - dw) / 2;
        const int y0 = (H - dh) / 2;

        cv::Mat scaled;
        cv::resize(bgr, scaled, cv::Size(dw, dh));

        static bool cleared = false;
        if (!cleared) { std::memset(mem_, 0, size_); cleared = true; }

        const int bpp = var_.bits_per_pixel;
        const int stride = fix_.line_length;
        for (int y = 0; y < dh; ++y) {
            const uint8_t *src = scaled.ptr<uint8_t>(y);
            uint8_t *dst = mem_ + (size_t)(y0 + y) * stride + (size_t)x0 * (bpp / 8);
            if (bpp == 24) {
                // little-endian RGB888 内存顺序为 B,G,R，和 OpenCV BGR 一致
                std::memcpy(dst, src, (size_t)dw * 3);
            } else if (bpp == 32) {
                for (int x = 0; x < dw; ++x) {
                    dst[x * 4 + 0] = src[x * 3 + 0];
                    dst[x * 4 + 1] = src[x * 3 + 1];
                    dst[x * 4 + 2] = src[x * 3 + 2];
                    dst[x * 4 + 3] = 0;
                }
            }
        }
    }

private:
    int fd_ = -1;
    uint8_t *mem_ = nullptr;
    size_t size_ = 0;
    fb_var_screeninfo var_{};
    fb_fix_screeninfo fix_{};
};
```

在 `solution::task_hdmi` 里，把 `m_hdmi->show(...)` 替换成：

```cpp
if (m_camera->channel() == 3) {
    static FbDisplay fb;
    static bool inited = false;
    if (!inited) { fb.open("/dev/fb0"); inited = true; }
    fb.show_letterbox(pic);     // pic 是已经画好框的 640×480 BGR
} else {
    m_hdmi->show(m_cmabuf[p->work_idx]->phys_addr,
                 m_cmabuf[p->work_idx]->virt_addr,
                 m_camera->channel());
}
```

> 如果显示出来红蓝反了，把 `bpp==24/32` 分支里的 R/B 交换，或者按 `var_.red.offset/green.offset/blue.offset` 做通用转换。  
> 如果不想改代码，也可以把 DTS 的 `native-mode` 改成 `timing_800x480`，并把摄像头输出改成 800×480；但 Zynq 当前是 640×480，改 DTS 不如 letterbox 灵活。

**方案 2：把 fb 分辨率改成和摄像头一致。**  
改 `sdk/anlogic-dr1m90-softip.dts` 里的 `native-mode` 和 `axi_dynclk` 的 `expclk`，重新编译 DTB/BOOT，风险比方案 1 大，不推荐先做。

#### 3.5 运行

```bash
cd /home/uisrc/app/face_detection/rootfs/root
export LD_LIBRARY_PATH=$PWD/armnn_lib/lib:$PWD/ffmpeg_opencv4.7.0_aarch64/lib:$LD_LIBRARY_PATH

sudo systemctl stop gdm

sudo ./bin/yolo_demo_hdmi_camera \
    -m ./inputs/yolo_face_uint8_15.onnx \
    -u ./inputs/example_yolo_face.json \
    -s 192.168.1.102:12345 \
    -i udp \
    -o /dev/fb0 \
    --geometry 1920x1080
```

说明：

- `-i udp` 只是给 `main.cpp` 一个选择信号；真正的端口/分辨率在 `udp_camera_t(640, 480, 5002)` 里；
- `--geometry 1920x1080` 是 HDMI 显示分辨率，不是 UDP 摄像头分辨率；
- `-s` 是检测结果 JSON 的接收端，可以填 PC，也可以填 Zynq（如果 Zynq 有监听程序）。

**验收标准**：

- HDMI 上能看到 Zynq 的实时画面（可能有几十毫秒延迟）；
- 画面里有人脸时出现 `face: xx%` 框；
- 终端 `npu` 阶段有耗时，FPS ≥ 10（640×480 目标 15~30）；
- 拔掉网线/停 Zynq 后程序不会崩溃（最多停在 `recv` 等待）；
- 没有 `imdecode` 失败导致的持续黑屏（偶发丢帧正常）。

---

### M4：性能与稳定性

#### 4.1 先用 imdecode，再考虑 JPU

- 640×480 JPEG，A53 用 OpenCV `imdecode` 通常几毫秒到十几毫秒；
- 如果 FPS 够，不必上 JPU；
- 如果要 1080p 或更高帧率，再按 demo 的 `usb_camera_t` 方式接 JPU：
  - `jpu_decoder_gift` 输出 YUV422 YUYV；
  - `udp_camera_t` 的 `channel()` 改成 2；
  - `task_resize` 走已有的 `case 2`（`soft_resize_yuv422_to_rgb_plane`）；
  - 注意 JPU 只支持特定 JPEG 格式/尺寸，先确认 OV5640 的 JPEG 能被 JPU 解。

> JPU 的接入代码可以参考 `utils/media/usb_camera.cpp`：  
> `cma_buffer_t bf; bf.phys_addr = ...; impl->buf.import(bf); impl->gift.emplace_jpeg_bits_from(...); impl->gift.decode_frame_to(...)`。  
> 把 `stream_input` 换成 UDP 队列即可。

#### 4.2 丢帧策略

- UDP 没有重传，丢一个包就会坏一帧；
- 当前 `udp_camera_t` 在 `imdecode` 失败时丢帧，等待下一个 `FFD8`；
- 如果 NPU 比相机慢，不要让队列无限增长：
  - 只保留“最新一帧”；
  - 或者 pipeline 满时丢弃最旧的帧；
  - demo 的 `m_buf_nums=8`，如果 `main_loop` 的 60Hz 触发比 NPU 快，`work_buffer_idx` 会追上 `m_last_work_buffer_idx` 并抛 `"buff nums is not enough"`。  
    解决：把 `main_loop` 的 `sleep_until(now + 13ms)` 改成按实际帧率（例如 33ms/66ms），或在 `task_camera` 里阻塞等新帧。

#### 4.3 加包序号（可选，但推荐）

当前 Zynq 的包没有序号，收端只能靠 `FFD8/FFD9`。要判断“这帧是不是缺包”，可以在 Zynq 端加 8 字节包头：

```text
magic   u16 = 0xB7C5
frame   u16 = 帧号
index   u16 = 包序号
flags   u16 = bit0 FIRST, bit1 LAST
payload ...
```

- 在 `udp_tx_data()` 里分配 `len + 8` 的 pbuf，先写头，再拷 JPEG 数据；
- DR1 收端解析头，记录本帧已收到的包号；
- 如果 `flags` 有 LAST 但包号不连续，整帧丢弃；
- 包头不改变 JPEG 字节流，拼帧仍然按 `FFD8/FFD9`。

> 注意：这和 PC 端 raw BGRX 的 6 字节头（帧号/行号/列偏移）不是一套协议，不要混。

#### 4.4 CPU/内存

- CMA 池 128 MB，足够 8 个 640×480×3 的 buffer + NPU tensor；
- 不要在每帧里 `malloc`/`free`；
- OpenCV `cv::resize` 的目标 `cv::Mat` 如果是临时对象，会每帧分配；可以复用 `cv::Mat`；
- 画框后直接写 fb，不要 `cv::imshow`（板子上没有 X11 或会冲突）；
- 如果 CPU 占用高，检查是不是 `-b` 没写 `Alnpu`，大量算子回退到 CPU。

#### 4.5 性能预算（实测为准）

| 阶段 | 640×480 估算 | 备注 |
|---|---|---|
| 网络收包 | < 1 ms/帧 | 1Gbps 网口，JPEG 几十 KB/帧 |
| JPEG 解码（CPU） | 3~10 ms | OpenCV `imdecode`，A53 |
| JPEG 解码（JPU） | 1~3 ms | 需接 JPU |
| resize 640×480→416×416 | 1~3 ms | OpenCV |
| NPU 推理（YOLOv3-tiny face 416） | 20~60 ms | 以 demo 日志为准 |
| YOLO 后处理 + NMS | 1~3 ms | 1 类，候选框少 |
| 画框 + fb letterbox | 1~5 ms | 1920×1080 画布 |
| **合计** | **约 30~80 ms** | 约 **12~30 fps**，以实测为准 |

---

### M5：从“检测”升级到“识别”（可选）

官方 demo 只做检测。要识别“是谁”，增加第二阶段：

```text
UDP JPEG
  → 解码
  → 人脸检测（YOLO face，已跑通）
  → 人脸对齐（5 关键点 / 或按框裁剪）
  → 人脸 embedding（MobileFaceNet / ArcFace，112×112）
  → 与人脸库比对（余弦相似度）
  → 输出 identity + score
```

#### 5.1 现实的做法

1. **先做检测 + 裁剪 + 保存人脸图**，确认框稳定；
2. 收集每个人 10~20 张人脸图，做一个小人脸库；
3. 选一个轻量 embedding 模型（MobileFaceNet 约 1M 参数，112×112 输入）；
4. 把模型转成量化 ONNX，先 `-b CpuRef` 验证，再 `-b Alnpu,...`；
5. 如果 Alnpu 不支持某些层，会回退 CPU，先接受，后续再优化；
6. 余弦相似度阈值先用 0.5~0.7 之间调，按你的模型/数据定；
7. 做人脸库时保存 embedding，不要保存原始图片（隐私/空间）。

#### 5.2 关于 NPU 的 MBFace 选项

- 当前 bitstream：`MBFace=0`；
- 这不代表“不能跑人脸识别模型”，只代表软核没有为 MBFace 做专门优化；
- 先尝试通用 MobileFaceNet/ArcFace 量化 ONNX，走硬核 Conv/FC + Soft NPU Pool；
- 如果层不支持或性能差，再在 TangDynasty 里把 `NPU_SOFT_0` 的 `MBFace` 设为 1，重新生成 IP/HPF/bitstream/BOOT.bin；
- 换 bitstream 后，板子的 `BOOT.bin`、`system.dtb` 必须同步更新，否则地址/中断可能对不上。

#### 5.3 没有人脸关键点怎么办

YOLO face 只给框，不给 5 点。可选：

- 用框的中心区域裁剪，留 20% margin，直接送 embedding（精度会低一些，但能 demo）；
- 或者换一个带关键点的人脸检测模型（SCRFD/RetinaFace），先确认能转 ONNX、能在 Alnpu 上跑；
- 或者用 OpenCV/传统方法做粗略对齐（眼睛检测），但稳定性一般。

#### 5.4 识别输出

```json
{
  "faces": [
    {"bbox": [x, y, w, h], "identity": "Tom", "score": 0.82}
  ],
  "timestamp": 1625247600.123456
}
```

可以先在 HDMI 上画 `Tom 82%`，再把 JSON 发给 PC/Zynq。

---

### M6：产品化

- 用 `systemd` 把应用做成开机自启；
- 启动前 `systemctl stop gdm` 或直接用 DRM/无桌面系统；
- 网络用 `/etc/network/interfaces` 或 `systemd-networkd` 配静态 IP；
- 加看门狗：UDP 超过 N 秒没有新帧时清屏/重连；
- 日志写到文件/串口，保留每阶段 FPS；
- 如果要用 QT/Web 显示，建议把“NPU 推理”和“界面”分成两个进程，通过共享内存/UDP 传结果，避免界面阻塞推理。

---

## 4. Zynq 端要改什么

### 4.1 只改目标 IP（最小改动）

```c
// udp_perf_server.h
#define UDP_DEST_IP_3   100   // DR1 的 IP 最后一段
```

重新编译下载。串口确认：

```text
Target IP : 192.168.1.100 (port 5002), 1024 bytes/datagram
```

### 4.2 可选：加包序号（推荐）

在 `udp_tx_data()` 里：

```c
// 伪代码
u8 header[8];
header[0] = 0xC5; header[1] = 0xB7;      // magic 0xB7C5，小端
header[2] = frame_id & 0xFF;
header[3] = frame_id >> 8;
header[4] = pkt_idx & 0xFF;
header[5] = pkt_idx >> 8;
header[6] = flags & 0xFF;                // FIRST/LAST
header[7] = flags >> 8;

struct pbuf *ptr = pbuf_alloc(PBUF_TRANSPORT, len + 8, PBUF_POOL);
pbuf_take(ptr, header, 8);               // 先写头
pbuf_take_at(ptr, buffer_ptr, len, 8);   // 再写 JPEG 数据
udp_send(pcb, ptr);
```

> `pbuf_take_at` 的具体用法以 lwIP 版本为准；也可以分配两块 pbuf 用 `pbuf_chain`，或者先 memcpy 到一个 `len+8` 的临时缓冲。

### 4.3 可选：控制发送速率

Zynq 现在 DMA 一完成就发，发送速率可能高于 DR1 的 NPU 处理速度。  
两种做法：

- Zynq 端按帧率节流（例如每 33ms 发一帧）；
- DR1 端只保留最新帧，旧帧丢弃。

推荐 DR1 端丢弃，因为网络/发送端不需要知道接收端算力。

### 4.4 不要改的东西

- OV5640 的 JPEG 模式配置；
- `MAX_PKT_LEN = 1024` 和 `UDP_VIDEO_PKT_LEN = 1024` 必须一致；
- `xemacif_input(netif)` 必须持续调用（ARP/收包）；
- DMA 缓存失效 `Xil_DCacheInvalidateRange()` 不要删。

---

## 5. 部署与运行速查

### 5.1 PC → DR1（调试）

```bash
# PC 上
scp -r D:\FPGA\Linux\npu\sdk\face_detection.tar.gz uisrc@192.168.1.100:/home/uisrc/

# DR1 上（tar 内自带 app/ 前缀，解压到 /home/uisrc）
cd /home/uisrc
tar zxvf face_detection.tar.gz
cd /home/uisrc/app/face_detection/rootfs/root
export LD_LIBRARY_PATH=$PWD/armnn_lib/lib:$PWD/ffmpeg_opencv4.7.0_aarch64/lib:$LD_LIBRARY_PATH
sudo systemctl stop gdm
```

### 5.2 修改并编译

```bash
# Ubuntu VM 里
cd /home/uisrc/app/face_detection
# 把 udp_camera.hpp/cpp 放到 src/npu_flow/utils/media/
# 修改 main.cpp / solution.cpp
./build.sh

# 把新的 rootfs/root/bin/yolo_demo_hdmi_camera 和源码拷到板子
```

### 5.3 板子运行

```bash
cd /home/uisrc/app/face_detection/rootfs/root
export LD_LIBRARY_PATH=$PWD/armnn_lib/lib:$PWD/ffmpeg_opencv4.7.0_aarch64/lib:$LD_LIBRARY_PATH
sudo systemctl stop gdm
sudo ./bin/yolo_demo_hdmi_camera \
  -m ./inputs/yolo_face_uint8_15.onnx \
  -u ./inputs/example_yolo_face.json \
  -s 192.168.1.102:12345 \
  -i udp -o /dev/fb0 --geometry 1920x1080
```

### 5.4 检查 NPU 是否真的在跑

```bash
ls -l /dev/hard_npu /dev/soft_npu /dev/cma_mem
dmesg | grep -iE 'npu|jpu|cma'
# 看 demo 日志里的 npu 阶段耗时
```

如果日志里 `npu` 时间和 `cpu` 差不多，或者 CPU 100%，检查：

- `-b` 是否包含 `Alnpu`；
- 模型是否量化；
- 是否有大量不支持的算子回退；
- `/dev/hard_npu` 是否被别的进程占用。

---

## 6. 常见问题对照

| 现象 | 原因 | 处理 |
|---|---|---|
| `ping` 不通 Zynq | 网段/网线/IP 没改 | 统一 `192.168.1.x`；改 `UDP_DEST_IP_3` 重编 Zynq |
| DR1 收不到包 | 防火墙、IP、端口 | DR1 `tcpdump -i eth0 udp port 5002`；PC 也试收 |
| 有包但拼不出 JPEG | Zynq 的 DMA 长度 ≠ UDP 发送长度 | `MAX_PKT_LEN` 和 `UDP_VIDEO_PKT_LEN` 都必须是 1024 |
| 偶尔花屏/解码失败 | UDP 丢包 | 加包序号/丢整帧；降 JPEG 质量；用千兆网 |
| HDMI 黑屏 | fb 被桌面占用 / 分辨率不匹配 | `systemctl stop gdm`；查 `bits_per_pixel`/`virtual_size` |
| HDMI 图像错位/越界 | 用 640×480 直接 memcpy 到 1920×1080 fb | 用本文的 `FbDisplay::show_letterbox` |
| 红蓝反了 | fb 是 RGB，源是 BGR | 交换 R/B 或按 `fb_var_screeninfo` 的 offset 转换 |
| NPU 日志没有 `npu` 耗时 | 没走 Alnpu / 模型不对 | `-b Alnpu,CpuAcc,CpuRef`；用官方模型先验证 |
| 程序跑一会抛 `buff nums is not enough` | 生产快于消费，8 个 buffer 用完 | 降 `main_loop` 频率 / 丢旧帧 / 增大 buffer |
| 摄像头有画面但没人脸框 | 模型/阈值/预处理不对 | 先用官方 demo + 官方模型确认；再查 mean/scale |
| 识别结果乱 | 没做对齐/阈值不对/模型没量化好 | 先只做检测；再做对齐和 embedding；调阈值 |

---

## 7. 最小验收清单

按顺序打勾：

- [ ] DR1 上 `/dev/hard_npu`、`/dev/soft_npu`、`/dev/cma_mem` 存在；
- [ ] 官方 `face_detection` 接 MIPI/USB 摄像头能在 HDMI 出人脸框；
- [ ] Zynq 改目标 IP 后，DR1 `tcpdump` 能看到 1024 字节包；
- [ ] DR1 的 `jpeg_saver.py` 能存出 10 张完整 JPEG；
- [ ] `udp_camera_t` 能让 demo 从 UDP 拿到画面；
- [ ] HDMI 上能看到 Zynq 实时画面（先不要求框）；
- [ ] 接入 `yolo_face_uint8_15.onnx` 后能出人脸框；
- [ ] 终端 `npu` 阶段有独立耗时，FPS ≥ 10；
- [ ] 连续跑 10 分钟不崩、不内存泄漏；
- [ ] （可选）检测结果 JSON 能发到 PC；
- [ ] （可选）第二阶段 embedding 识别能跑通。

---

## 8. 参考文件

| 文件 | 用途 |
|---|---|
| `Linux/npu/NPU硬核使用指南.md` | NPU 地址、驱动、ArmNN、demo 细节 |
| `Linux/npu/sdk/face_detection.tar.gz` | 官方 NPU demo、模型、库 |
| `Vitis/UDP/prj/udp_camera/vitis/udp_camera/src/main.c` | Zynq 采集/DMA/UDP 主循环 |
| `Vitis/UDP/prj/udp_camera/vitis/udp_camera/src/udp_perf_server.h` | Zynq IP/端口/包长配置 |
| `Vitis/UDP/UDP_CAMERA_开发记录.md` | OV5640 JPEG、DMA、lwIP 细节 |
| `Vitis/UDP/DR1板子_UDP视频显示_开发记录.md` | PC→DR1 BGRX 显示联调 |
| `Vitis/UDP/上位机/README.md` | PC 端 JPEG 接收格式 |
| `Vitis/UDP/上位机/udp_video_station.py` | PC 端 JPEG 拼帧/显示参考 |
| `Linux/npu/driver/anlogic-vdmafb.c` | fb 是 24bpp RGB888 的证据 |
| `Linux/npu/sdk/anlogic-dr1m90-softip.dts` | soft_npu/vdma/hdmi 设备树 |

---

## 9. 一句话路线

**先在 DR1 上用官方 demo 证明 NPU 能用 → 再把 Zynq 的 JPEG UDP 流接进来 → 用 `udp_camera_t` + `task_resize` 的 3 通道分支跑通检测 → 最后才是识别模型和性能优化。**
