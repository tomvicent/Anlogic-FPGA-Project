# UDP 视频收发联调指南（PC 模拟 Zynq → DR1 板子）

> 目的：在真 Zynq 板子接进来之前，先用 PC 模拟 OV5640 发 UDP JPEG 流，
> 在 DR1M90 板子上收、拼帧、解码、显示。跑通后把 PC 换成 Zynq 即可。

## 1. 文件说明

| 文件 | 跑在哪 | 作用 |
|---|---|---|
| `udp_video_sender_sim.py` | **PC（Windows/Linux）** | 读本地视频/摄像头，JPEG 编码，按 1024B 分包发 UDP，模拟 Zynq |
| `dr1_udp_recv.py` | **DR1 板子 Linux** | 收 UDP，拼 FFD8/FFD9 帧，OpenCV 解码显示 |

两边都用 Python3 + OpenCV，**完全复刻 Zynq 的发送格式**：1024 字节/包，无包头 JPEG 裸流。

## 2. 网络拓扑

```
PC (192.168.1.101)                          DR1 板子 (192.168.1.100)
udp_video_sender_sim.py                     dr1_udp_recv.py
    │                                            ▲
    │  UDP 1024B/包, JPEG 裸流                    │
    └──────────────────────────────────────────► │
                  目标 192.168.1.100:5002
```

> 实际 IP 以你板子的 `ip addr` 为准。

## 3. PC 端准备

PC 上要装 Python3 + OpenCV：

```powershell
# Windows PowerShell
pip install opencv-python numpy
```

## 4. DR1 板子端准备

ssh 进板子（或直接在板子桌面开终端）：

```bash
# 板子上
sudo apt install -y python3 python3-opencv python3-numpy

# 把 dr1_udp_recv.py 拷到板子上（用 scp 或 U盘）
# PC PowerShell:
# scp dr1_udp_recv.py root@192.168.1.100:/root/
```

## 5. 联调步骤

### 第 1 步：先在 PC 本机环回测试（不用板子）

PC 上同时开两个终端：

终端 A（收）：
```powershell
cd D:\FPGA\Vitis\UDP\上位机
python dr1_udp_recv.py --port 5002 --host 127.0.0.1
```

终端 B（发）：
```powershell
cd D:\FPGA\Vitis\UDP\上位机
python udp_video_sender_sim.py --dst 127.0.0.1 --port 5002
```

能看到弹窗里移动的绿圆和帧号，说明收发代码本身没问题。

### 第 2 步：PC → DR1 板子

1. 确认 PC 和 DR1 板子网线直连（或同一交换机），同一网段；
2. 查板子 IP：板子上 `ip addr show eth0`，假设是 `192.168.1.100`；
3. PC PowerShell ping 一下：`ping 192.168.1.100`，通了再继续；
4. **板子上先启动接收端**：
   ```bash
   ssh root@192.168.1.100
   cd /root
   python3 dr1_udp_recv.py --port 5002
   ```
   看到 `监听 0.0.0.0:5002, 等发送端推流...`。
5. **PC 上启动发送端**：
   ```powershell
   cd D:\FPGA\Vitis\UDP\上位机
   # 方式 A：用内置测试图（最简单，先跑这个）
   python udp_video_sender_sim.py --dst 192.168.1.100 --port 5002

   # 方式 B：用本地视频文件
   python udp_video_sender_sim.py --video test.mp4 --dst 192.168.1.100 --port 5002 --loop

   # 方式 C：用 PC 摄像头
   python udp_video_sender_sim.py --camera 0 --dst 192.168.1.100 --port 5002
   ```
6. 板子上 HDMI 显示器应该能看到画面（或 `--headless` 模式下终端打印 fps）。

### 第 3 步：换成真 Zynq 板子

跑通上面之后，**把 PC 发送端停掉，接真 Zynq**：

1. Zynq 工程里把 `UDP_DEST_IP_*` 改成 DR1 板子的 IP（比如 `192.168.1.100`）；
2. Zynq 重新编译下载，串口看到 `UDP video stream started: port 5002 -> 192.168.1.100:5002`；
3. DR1 板子上 `dr1_udp_recv.py` **不用改一行代码**，直接就能收到。

因为 PC 模拟器发的包格式跟 Zynq 完全一致（1024B/包 JPEG 裸流）。

## 6. 常用命令速查

### PC 发送端
```powershell
# 内置测试图（无视频文件无摄像头时用）
python udp_video_sender_sim.py --dst 192.168.1.100 --port 5002

# 本地视频循环推流
python udp_video_sender_sim.py --video test.mp4 --dst 192.168.1.100 --port 5002 --loop

# 调分辨率（跟 OV5640 对齐用 640x480）
python udp_video_sender_sim.py --dst 192.168.1.100 --size 640x480 --quality 70

# 改 JPEG 质量（数字越小包越小，帧率越高）
python udp_video_sender_sim.py --dst 192.168.1.100 --quality 50
```

### DR1 接收端
```bash
# 接 HDMI 显示
python3 dr1_udp_recv.py --port 5002

# headless 模式（无显示器，只看 fps 统计）
python3 dr1_udp_recv.py --port 5002 --headless

# 把每帧 JPEG 存盘（调试拼帧问题用）
python3 dr1_udp_recv.py --port 5002 --jpeg-dir ./frames

# 把结果录成 mp4（无显示器也能回 PC 看）
python3 dr1_udp_recv.py --port 5002 --save out.mp4 --headless
```

## 7. 排错

| 现象 | 原因 | 解决 |
|---|---|---|
| 板子上 `recvfrom` 一直阻塞 | IP/端口不对，或防火墙 | 板子上 `tcpdump -i eth0 udp port 5002` 看包到没到 |
| PC 上 ping 不通板子 | 网线/IP 网段 | PC 网口设成 `192.168.1.101/24`，板子 `192.168.1.100/24` |
| 收到包但解不出帧 | 拼帧逻辑 bug | 用 `--jpeg-dir` 存几帧，PC 上手动打开看是不是完整 JPEG |
| 画面卡顿/丢帧 | 网口缓冲小 | 代码里已设 4MB RCVBUF；PC 端 `--quality 50` 降码率 |
| OpenCV 没装 | 板子没装 python3-opencv | `sudo apt install python3-opencv` |
| `cv2.imshow` 报错 | 板子没显示器/DISPLAY 没设 | 加 `--headless`，或 `export DISPLAY=:0` |

## 8. 下一步

UDP 收发跑通后，就可以在 `dr1_udp_recv.py` 的 `img = cv2.imdecode(...)` 这一行后面加 NPU 推理调用了：

```python
# 伪代码：拼帧解码出 img 之后
img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
input_tensor = preprocess(img_rgb)        # resize 到 320x320, 归一化
boxes = npu_yolo_infer(input_tensor)      # 调 NPU
draw_boxes(img, boxes)                    # 画框
cv2.imshow("DR1 UDP Receiver", img)
```

到这一步就是真正的 AI 视觉 pipeline 了。
