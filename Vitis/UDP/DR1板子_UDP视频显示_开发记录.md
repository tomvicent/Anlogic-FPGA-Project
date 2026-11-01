# DR1 板子 UDP 视频显示联调开发记录

## 一、当前完成进度

### 已跑通链路
```
PC 摄像头 → OpenCV 读帧 → 转 BGRX8888 格式 → UDP 分包发送 → 米联客 DR1 板子接收 → mmap 直接写 /dev/fb0 → HDMI 显示
```

- 分辨率：640×480
- 帧率：约 15-20 fps（受网络和 Python 性能限制）
- 显示位置：屏幕居中，周围黑边
- 已验证：PC 摄像头实时画面在 DR1 板子 HDMI 上流畅显示

### 最终目标
PC 模拟通了之后，把 PC 换成 Zynq 开发板（OV5640 摄像头），DR1 板子接收并跑 NPU 推理。

---

## 二、网络拓扑

```
PC (Windows)                          DR1 开发板 (Ubuntu 20.04 aarch64)
192.168.137.1  ──── 千兆网线 ────  192.168.137.100
(ICS 共享网络)                        SSH: uisrc@192.168.137.100
```

- PC 通过 Windows ICS 共享网络给 DR1 板子
- DR1 板子无外网，只能通过 SSH/SCP 操作
- UDP 端口：5002

---

## 三、数据格式说明

### 3.1 PC 发送端格式

**像素格式：BGRX8888**（跟 framebuffer 完全一致，零转换直写）

每个像素 4 字节：
| 字节0 | 字节1 | 字节2 | 字节3 |
|-------|-------|-------|-------|
| B     | G     | R     | X(0)  |

**UDP 包结构**：
```
| 包头 6 字节 | 像素数据 N 字节 |
```

包头 6 字节（小端序）：
| 字节偏移 | 含义 | 说明 |
|----------|------|------|
| 0-1      | 帧号 | 递增计数 |
| 2-3      | 行号 | 0~479 |
| 4-5      | 列偏移 | 0 或 400 |

每个 UDP 包发 **400 像素** = 400×4 = 1600 字节 + 6 包头 = 1606 字节
（小于以太网 MTU 1500 字节限制，实际 ~1206/726 字节两种包）

每帧总包数：480 行 × 2 包/行 = 960 包

### 3.2 板子接收端处理逻辑

1. 收到 UDP 包，解析 6 字节包头
2. 根据 row/col 计算在 framebuffer 中的偏移：
   ```
   目标偏移 = (居中Y + row) × stride + (居中X + col) × 4
   ```
3. 直接用 mmap 把 payload 写进 framebuffer 对应位置
4. **不等整帧收齐，来一个包写一个包**（UDP 乱序无所谓，后到的覆盖先到的）

---

## 四、各代码文件功能说明

### PC 端文件（D:\FPGA\Vitis\UDP\上位机\）

| 文件 | 功能 |
|------|------|
| `udp_cam_sender.py` | **当前使用**。读 PC 摄像头，转 BGRX8888，按 400 像素/包 UDP 发送 |
| `udp_rgb_sender.py` | 测试图发送器（四角色块/十字线），不接摄像头，用于验证显示位置 |
| `udp_video_sender_sim.py` | 旧版 JPEG 发送模拟器（FFD8/FFD9 分帧），已弃用 |
| `fb_rgb_viewer.py` | **板子端接收显示脚本**，mmap 写 /dev/fb0 |

### 板子端文件（/home/uisrc/）

| 文件 | 功能 |
|------|------|
| `fb_rgb_viewer.py` | UDP 接收 + mmap 直写 framebuffer。无 OpenCV/PIL 依赖，纯 Python 标准库 |

---

## 五、遇到的问题及解决方法

### 问题 1：UDP sendto 报错 WinError 10040
- **原因**：单包太大（整行 1920 字节），超过以太网 MTU
- **解决**：每包只发 400 像素（~1600 字节），自动分包

### 问题 2：板子收不到包
- **原因**：Windows 防火墙拦截 / 发送端 IP 不对
- **解决**：确认目标 IP 是 192.168.137.100，端口 5002

### 问题 3：Xorg 桌面抢写 framebuffer 导致花屏
- **原因**：HDMI 上有 GNOME 桌面在跑，直接写 fb0 会跟桌面冲突
- **解决**：先 `sudo systemctl stop gdm` 停掉桌面，独占 framebuffer

### 问题 4：Python 逐像素写 framebuffer 太慢（卡顿/断断续续）
- **原因**：30 万像素逐像素循环 + 每次 write 系统调用
- **解决**：
  1. 发送端直接发 BGRX8888 格式，板子不需要颜色转换
  2. 用 `mmap` 映射 framebuffer 内存，直接写内存代替 write() 系统调用
  3. 收到包就写，不等整帧收齐

### 问题 5：板子没有 OpenCV/PIL/GStreamer/ffmpeg
- **原因**：板子无外网，apt 装不了
- **解决**：绕开解码，发送端直接发原始像素格式，板子零处理直写 fb0

### 问题 6：scp 命令在 cmd 里报错 `& was unexpected`
- **原因**：cmd 不支持 PowerShell 的 `&` 调用操作符
- **解决**：用全路径直接调用 `"C:\Windows\System32\OpenSSH\scp.exe"`

---

## 六、操作命令速查

### PC 端
```powershell
# 启动摄像头发送
cd D:\FPGA\Vitis\UDP\上位机
python udp_cam_sender.py

# 传文件到板子
"C:\Windows\System32\OpenSSH\scp.exe" 文件 uisrc@192.168.137.100:/home/uisrc/
```

### 板子端（SSH）
```bash
# 停桌面独占 framebuffer
sudo systemctl stop gdm

# 启动接收显示
sudo python3 /home/uisrc/fb_rgb_viewer.py

# 恢复桌面
sudo systemctl start gdm
```

---

## 七、后续待办

1. **接 Zynq 真实板**：把 PC 换成 Zynq，注意 Zynq 发的是 JPEG 流不是原始 BGRX
2. **JPEG 解码问题**：板子上需要解决 JPEG → BGRX 的解码（可能用 JPU 硬件或 djpeg）
3. **NPU 推理**：视频显示跑通后，接入 NPU 跑神经网络
4. **性能优化**：当前 Python 写 fb0 还是偏慢，后续可以用 C 程序优化
