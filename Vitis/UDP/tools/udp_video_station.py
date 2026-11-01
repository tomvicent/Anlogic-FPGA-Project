#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP 视频传输上位机 (UDP Video Station)  v1.0
================================================
· 接收：UDP 以太网接收视频帧（JPEG 分片 / 单包 JPEG / 原始 RAW 行分片），
        实时预览、帧率/码率/丢帧统计、录像（AVI）、抓拍（PNG）。
· 发送：摄像头 / 视频文件 / 图片目录 / 内置测试图 经 UDP 发送，
        可对接 FPGA、Zynq、STM32、Jetson、RK3566 等设备的图传链路。
· 自检：命令行 --selftest 时不开界面，本机环回验证“分片->重组->解码”链路。

依赖：PySide6-Essentials、opencv-python-headless、numpy、pillow
"""

import argparse
import glob
import os
import queue
import socket
import struct
import sys
import threading
import time
import traceback

import cv2
import numpy as np

APP_NAME = "UDP 视频传输上位机"
APP_VER = "1.0"

# ============================================================
# 通信协议（收发两端共用）
# ============================================================
#  分片头 12 字节（小端）：
#    offset 0  : uint16 magic       固定 0xB7C5
#    offset 2  : uint16 frame_id    帧号，每帧 +1（uint16 回绕）
#    offset 4  : uint16 pkt_index   分片序号，从 0 开始
#    offset 6  : uint16 pkt_total   本帧分片总数
#    offset 8  : uint16 payload_len 本包负载字节数
#    offset 10 : uint8  flags       bit0=首片 bit1=末片 bit2=原始RAW
#    offset 11 : uint8  reserved    保留，填 0
MAGIC = 0xB7C5
HDR = struct.Struct("<HHHHHBB")

FLAG_FIRST = 0x01
FLAG_LAST = 0x02
FLAG_RAW = 0x04

MODE_FRAG = "JPEG 分片(带头)"
MODE_SINGLE = "JPEG 单包(无头)"
MODE_RAW = "原始 RAW(行分片)"
MODE_AUTO = "自动识别(分片/单包)"
MODE_STREAM = "JPEG 裸流(FFD8/FFD9 拼帧)"
MODE_JPEG_RAW = "JPEG 裸流(直接发)"
MODE_RGB888 = "RGB888 裸数据"
MODE_RGB565 = "RGB565 裸数据"

RX_MODES = [MODE_STREAM, MODE_FRAG, MODE_AUTO, MODE_SINGLE, MODE_RAW]
TX_MODES = [MODE_FRAG, MODE_SINGLE, MODE_JPEG_RAW, MODE_RGB888, MODE_RGB565, MODE_RAW]

PIX_BGR = "BGR888"
PIX_YUYV = "YUYV422"

# 配置文件路径
CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "udp_station_config.json")

DEFAULT_PORT = 5002
DEFAULT_CHUNK = 1400          # 以太网 MTU 1500 - IP/UDP 头 28 - 协议头 12
DEFAULT_JPEG_Q = 80


def fmt_rate(v):
    if v >= 1024 * 1024:
        return "%.2f MB/s" % (v / 1024.0 / 1024.0)
    if v >= 1024:
        return "%.1f KB/s" % (v / 1024.0)
    return "%.0f B/s" % v


def local_ips():
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    try:
        host = socket.gethostname()
        for ip in socket.gethostbyname_ex(host)[2]:
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    return ips or ["127.0.0.1"]


# ============================================================
# 分片重组器
# ============================================================
class FragAssembler:
    """把带 12 字节头的分片重组成完整帧负载，并统计丢帧/包数/字节数。"""

    def __init__(self, timeout=0.60):
        self.timeout = timeout
        self.fid = None
        self.total = 0
        self.parts = {}
        self.t0 = 0.0
        self.frames_ok = 0
        self.frames_dropped = 0
        self.packets = 0
        self.bytes = 0
        self.last_ok_ts = 0.0

    def _abort(self):
        if self.parts:
            self.frames_dropped += 1
        self.fid = None
        self.total = 0
        self.parts = {}
        self.t0 = 0.0

    def push(self, fid, idx, total, payload):
        now = time.monotonic()
        if total <= 0 or idx >= total:
            return None
        if self.fid != fid or self.total != total:
            if self.fid is not None:
                self._abort()
            self.fid = fid
            self.total = total
            self.t0 = now
            self.parts = {}
        self.packets += 1
        self.bytes += len(payload)
        self.parts[idx] = payload
        if len(self.parts) >= total:
            data = b"".join(self.parts[i] for i in range(total))
            self.parts = {}
            self.fid = None
            self.frames_ok += 1
            self.last_ok_ts = now
            return data
        return None

    def tick(self):
        if self.parts and (time.monotonic() - self.t0) > self.timeout:
            self._abort()


class JpegStreamAssembler:
    """把“无包头、按固定字节数切包”的 JPEG 字节流按 FFD8(SOI)/FFD9(EOI) 拼回整帧。

    对应 Zynq/lwIP 例程的发送方式：每包 1024 字节原始摄像头字节流，
    包边界与帧边界无关，一帧可能跨多个包，一个包里也可能含帧尾 + 下一帧帧头。
    """

    SOI = b"\xff\xd8"
    EOI = b"\xff\xd9"

    def __init__(self, max_frame=4 * 1024 * 1024, max_buffer=6 * 1024 * 1024):
        self.buf = bytearray()
        self.max_frame = max_frame
        self.max_buffer = max_buffer
        self.frames = 0          # 成功切出的完整 JPEG 帧数
        self.junk_bytes = 0      # 帧头之前被丢弃的无效字节
        self.overflow = 0        # 单帧超长被清空的次数
        self.bytes = 0
        self.last_frame_len = 0

    def push(self, data):
        """喂入一段字节流，返回本轮切出的完整 JPEG 帧列表。"""
        frames = []
        self.bytes += len(data)
        self.buf.extend(data)

        while True:
            start = self.buf.find(self.SOI)
            if start < 0:
                # 没有帧头：保留末尾 1 字节（可能是被切开的 0xFF）
                keep = 1 if self.buf.endswith(b"\xff") else 0
                drop = len(self.buf) - keep
                if drop > 0:
                    self.junk_bytes += drop
                    del self.buf[:drop]
                break

            if start > 0:
                self.junk_bytes += start
                del self.buf[:start]

            end = self.buf.find(self.EOI, 2)
            if end < 0:
                if len(self.buf) > self.max_frame:
                    # 一帧异常长，丢掉这段，重新找帧头
                    self.overflow += 1
                    self.junk_bytes += len(self.buf)
                    self.buf.clear()
                break

            end += 2
            if end > self.max_buffer:
                self.junk_bytes += end
                del self.buf[:end]
                self.overflow += 1
                continue

            frames.append(bytes(self.buf[:end]))
            self.last_frame_len = end
            self.frames += 1
            del self.buf[:end]

        return frames


# ============================================================
# 接收端
# ============================================================
class UdpReceiver:
    def __init__(self, port, mode, bind_ip="0.0.0.0", rcvbuf_kb=4096,
                 raw_w=1280, raw_h=720, raw_pix=PIX_BGR,
                 peer_ip="", peer_port=0,
                 on_frame=None, on_log=None):
        self.port = int(port)
        self.mode = mode
        self.bind_ip = bind_ip or "0.0.0.0"
        self.rcvbuf = max(64, int(rcvbuf_kb)) * 1024
        self.raw_w = int(raw_w)
        self.raw_h = int(raw_h)
        self.raw_pix = raw_pix
        self.peer_ip = (peer_ip or "").strip()
        self.peer_port = int(peer_port or 0)
        self.on_frame = on_frame
        self.on_log = on_log

        self._run = threading.Event()
        self._thr = None
        self.actual_port = 0
        self.asm = FragAssembler()
        self.stream = JpegStreamAssembler()
        self.sock = None
        self.last_peer = "-"
        self.decode_fail = 0
        self.frames = 0
        self.byte_count = 0
        self._t_stat = 0.0
        self._n_frames_stat = 0
        self._n_bytes_stat = 0
        self.w, self.h = 0, 0
        self.bitrate = 0.0
        self.fps = 0.0
        self.last_frame_ts = 0.0
        self.pkt_rate = 0.0
        self._n_pkt_stat = 0
        self.rx_packets = 0
        self.filtered = 0
        self._filter_logged = False

    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, self.rcvbuf)
        except OSError:
            pass
        self.sock.bind((self.bind_ip, self.port))
        self.sock.settimeout(0.35)
        self.actual_port = self.sock.getsockname()[1]
        self._run.set()
        self._t_stat = time.monotonic()
        self._thr = threading.Thread(target=self._loop, name="udp-rx", daemon=True)
        self._thr.start()
        peer_desc = "-"
        if self.peer_ip or self.peer_port:
            peer_desc = "%s:%s" % (self.peer_ip or "*", self.peer_port or "*")
        self._log("接收已启动：本地 %s:%d  远程过滤=%s  协议=%s  RCVBUF=%dKB"
                  % (self.bind_ip, self.actual_port, peer_desc, self.mode, self.rcvbuf // 1024))
        return self.actual_port

    def stop(self):
        self._run.clear()
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None
        if self._thr:
            self._thr.join(timeout=1.5)
        self._log("接收已停止：收帧 %d，丢帧 %d，解码失败 %d"
                  % (self.frames, self.asm.frames_dropped, self.decode_fail))

    @property
    def running(self):
        return self._run.is_set()

    def _log(self, msg):
        if self.on_log:
            self.on_log(msg)

    def _loop(self):
        while self._run.is_set():
            try:
                data, addr = self.sock.recvfrom(65535)
            except socket.timeout:
                self.asm.tick()
                self._emit_stats()
                continue
            except OSError:
                break

            # 远程主机过滤：只接受指定来源地址/端口
            if self.peer_ip and addr[0] != self.peer_ip:
                self.filtered += 1
                if not self._filter_logged:
                    self._filter_logged = True
                    self._log("已丢弃非目标来源的数据包（来源 %s，仅接受 %s）" % (addr[0], self.peer_ip))
                continue
            if self.peer_port and addr[1] != self.peer_port:
                self.filtered += 1
                if not self._filter_logged:
                    self._filter_logged = True
                    self._log("已丢弃非目标来源的数据包（来源端口 %d，仅接受 %d）" % (addr[1], self.peer_port))
                continue

            self.last_peer = "%s:%d" % (addr[0], addr[1])
            self.byte_count += len(data)
            self.rx_packets += 1
            try:
                self._handle_packet(data)
            except Exception:
                self.decode_fail += 1
                self._log("处理数据包异常：%s" % traceback.format_exc(limit=1).strip())
            self._emit_stats()
        self._emit_stats(force=True)

    def _handle_packet(self, data):
        if self.mode == MODE_STREAM:
            for buf in self.stream.push(data):
                frame = self._decode(buf)
                if frame is not None:
                    self._deliver(frame)
            return

        if self.mode == MODE_SINGLE:
            frame = self._decode(data)
            if frame is not None:
                self._deliver(frame)
            return

        has_hdr = len(data) >= HDR.size and struct.unpack("<H", data[:2])[0] == MAGIC
        if not has_hdr:
            # 自动识别模式下，无协议头的包按整帧 JPEG 尝试解码
            if self.mode == MODE_AUTO:
                frame = self._decode(data)
                if frame is not None:
                    self._deliver(frame)
            return

        magic, fid, idx, total, plen, flags, _res = HDR.unpack(data[:HDR.size])
        payload = data[HDR.size: HDR.size + plen]
        if len(payload) < plen:
            payload = data[HDR.size:]

        buf = self.asm.push(fid, idx, total, payload)
        if buf is None:
            return

        if self.mode == MODE_RAW or (flags & FLAG_RAW):
            frame = self._decode_raw(buf)
        else:
            frame = self._decode(buf)
        if frame is not None:
            self._deliver(frame)

    def _decode(self, buf):
        try:
            img = cv2.imdecode(np.frombuffer(buf, dtype=np.uint8), cv2.IMREAD_COLOR)
        except Exception:
            img = None
        if img is None:
            self.decode_fail += 1
            return None
        return img

    def _decode_raw(self, buf):
        w, h, pix = self.raw_w, self.raw_h, self.raw_pix
        need = w * h * (2 if pix == PIX_YUYV else 3)
        if len(buf) < need:
            self.decode_fail += 1
            if self.decode_fail % 30 == 1:
                self._log("RAW 长度不足：收到 %d / 需要 %d（检查分辨率与像素格式）"
                          % (len(buf), need))
            return None
        raw = np.frombuffer(buf[:need], dtype=np.uint8)
        try:
            if pix == PIX_YUYV:
                img = cv2.cvtColor(raw.reshape(h, w, 2), cv2.COLOR_YUV2BGR_YUYV)
            else:
                img = raw.reshape(h, w, 3).copy()
        except Exception:
            self.decode_fail += 1
            return None
        return img

    def _deliver(self, frame):
        self.frames += 1
        self.h, self.w = frame.shape[:2]
        self.last_frame_ts = time.monotonic()
        if self.frames == 1:
            self._log("收到首个有效帧：%dx%d" % (self.w, self.h))
        if self.on_frame:
            self.on_frame(frame)

    def _emit_stats(self, force=False):
        now = time.monotonic()
        if not force and (now - self._t_stat) < 0.4:
            return
        dt = max(now - self._t_stat, 1e-6)
        self.fps = (self.frames - self._n_frames_stat) / dt
        self.bitrate = (self.byte_count - self._n_bytes_stat) / dt
        self.pkt_rate = (self.rx_packets - self._n_pkt_stat) / dt
        self._n_frames_stat = self.frames
        self._n_bytes_stat = self.byte_count
        self._n_pkt_stat = self.rx_packets
        self._t_stat = now

    def snapshot(self):
        total_units = self.asm.frames_ok + self.asm.frames_dropped
        drop_rate = (100.0 * self.asm.frames_dropped / total_units) if total_units else 0.0
        dropped = self.asm.frames_dropped
        if self.mode == MODE_STREAM:
            dropped = self.stream.overflow
            drop_rate = 0.0
        latency = (time.monotonic() - self.last_frame_ts) * 1000.0 if self.last_frame_ts else 0.0
        return {
            "peer": self.last_peer,
            "fps": self.fps,
            "bitrate": self.bitrate,
            "frames": self.frames,
            "dropped": dropped,
            "drop_rate": drop_rate,
            "packets": self.rx_packets,
            "pkt_rate": self.pkt_rate,
            "decode_fail": self.decode_fail,
            "size": "%dx%d" % (self.w, self.h) if self.w else "-",
            "latency": latency,
            "running": self.running,
        }


# ============================================================
# 发送端
# ============================================================
class UdpSender:
    SRC_TEST = "内置测试图"
    SRC_CAM = "摄像头"
    SRC_FILE = "视频文件"
    SRC_DIR = "图片目录"

    def __init__(self, dst_ip, dst_port, chunk=DEFAULT_CHUNK, fps=25.0, quality=DEFAULT_JPEG_Q,
                 source=SRC_TEST, source_arg="0", loop=True, mode=MODE_FRAG,
                 raw_w=1280, raw_h=720, raw_pix=PIX_BGR, bind_ip="0.0.0.0",
                 broadcast=False, on_log=None):
        self.dst_ip = dst_ip
        self.dst_port = int(dst_port)
        self.chunk = max(64, int(chunk))
        self.fps = max(0.2, float(fps))
        self.quality = int(min(100, max(10, quality)))
        self.source = source
        self.source_arg = source_arg
        self.loop = loop
        self.mode = mode
        self.raw_w = int(raw_w)
        self.raw_h = int(raw_h)
        self.raw_pix = raw_pix
        self.bind_ip = (bind_ip or "0.0.0.0").strip()
        self.broadcast = broadcast
        self.on_log = on_log

        self._run = threading.Event()
        self._thr = None
        self.sock = None
        self.frame_id = 0
        self.frames = 0
        self.packets = 0
        self.bytes = 0
        self.fps_real = 0.0
        self.bitrate = 0.0
        self._n_frames_stat = 0
        self._n_bytes_stat = 0
        self._t_stat = 0.0
        self.error = ""
        self._mtu_warned = False

    @property
    def running(self):
        return self._run.is_set()

    def _log(self, msg):
        if self.on_log:
            self.on_log(msg)

    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        if self.broadcast:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
        except OSError:
            pass
        if self.bind_ip and self.bind_ip != "0.0.0.0":
            self.sock.bind((self.bind_ip, 0))
        self._run.set()
        self._t_stat = time.monotonic()
        self._thr = threading.Thread(target=self._loop, name="udp-tx", daemon=True)
        self._thr.start()
        self._log("发送已启动：本地 %s -> 远程 %s:%d  来源=%s  分片=%dB  目标帧率=%.1f  协议=%s"
                  % (self.bind_ip, self.dst_ip, self.dst_port, self.source,
                     self.chunk, self.fps, self.mode))

    def stop(self):
        self._run.clear()
        if self._thr:
            self._thr.join(timeout=2.0)
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
        self._log("发送已停止：累计 %d 帧 / %s" % (self.frames, fmt_rate(self.bytes)))

    def _open_source(self):
        if self.source == self.SRC_CAM:
            try:
                idx = int(self.source_arg)
            except ValueError:
                idx = 0
            cap = cv2.VideoCapture(idx, cv2.CAP_DSHOW)
            if not cap.isOpened():
                cap.release()
                cap = cv2.VideoCapture(idx)
            if not cap.isOpened():
                raise RuntimeError("打不开摄像头 %s" % self.source_arg)
            self._log("摄像头已打开：索引 %s" % self.source_arg)
            return "cap", cap

        if self.source == self.SRC_FILE:
            path = os.path.expanduser(self.source_arg.strip().strip('"'))
            cap = cv2.VideoCapture(path)
            if not cap.isOpened():
                raise RuntimeError("打不开视频文件：%s" % path)
            self._log("视频文件已打开：%s" % path)
            return "cap", cap

        if self.source == self.SRC_DIR:
            d = os.path.expanduser(self.source_arg.strip().strip('"'))
            files = sorted(sum([glob.glob(os.path.join(d, e)) for e in
                                ("*.jpg", "*.jpeg", "*.png", "*.bmp")], []))
            if not files:
                raise RuntimeError("目录里没有 jpg/png/bmp：%s" % d)
            self._log("图片目录共 %d 张：%s" % (len(files), d))
            return "dir", files

        self._log("使用内置测试图源")
        return "test", None

    def _test_frame(self, i):
        w, h = self.raw_w, self.raw_h
        img = np.zeros((h, w, 3), dtype=np.uint8)
        grad = np.linspace(40, 220, w, dtype=np.float32).reshape(1, w)
        img[:, :, 0] = grad
        img[:, :, 1] = grad * 0.8
        img[:, :, 2] = 60
        x = (i * 12) % max(w - 120, 1)
        cv2.rectangle(img, (x, h // 3), (x + 120, h // 3 + 120), (0, 0, 255), -1)
        cv2.putText(img, "UDP TEST  frame %d" % i, (20, 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
        cv2.putText(img, time.strftime("%H:%M:%S"), (20, max(h - 30, 40)),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0), 2)
        return img

    def send_frame(self, frame):
        """把一帧编码并按当前模式发送，返回发送的包数。"""
        if frame is None:
            return 0
        if self.sock is None:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            if self.broadcast:
                self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        if self.mode == MODE_SINGLE:
            ok, buf = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), self.quality])
            if not ok:
                return 0
            data = buf.tobytes()
            if len(data) > 1472 and not self._mtu_warned:
                self._mtu_warned = True
                self._log("提示：单包模式整帧 %d 字节超过以太网 MTU(1472)，将依赖 IP 分片传输；"
                          "若出现花屏或丢帧，请改用“JPEG 分片(带头)”模式" % len(data))
            self.sock.sendto(data, (self.dst_ip, self.dst_port))
            self.bytes += len(data)
            self.frames += 1
            self.packets += 1
            return 1

        if self.mode == MODE_JPEG_RAW:
            # JPEG 裸流：编码后按 chunk 分包但不加协议头，纯字节流
            ok, buf = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), self.quality])
            if not ok:
                return 0
            data = buf.tobytes()
            for i in range(0, len(data), self.chunk):
                seg = data[i:i+self.chunk]
                self.sock.sendto(seg, (self.dst_ip, self.dst_port))
                self.bytes += len(seg)
                self.packets += 1
            self.frames += 1
            return (len(data) + self.chunk - 1) // self.chunk

        if self.mode == MODE_RGB888:
            # RGB888 裸数据：BGR -> RGB 后按 chunk 发，不加头
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            data = rgb.tobytes()
            for i in range(0, len(data), self.chunk):
                seg = data[i:i+self.chunk]
                self.sock.sendto(seg, (self.dst_ip, self.dst_port))
                self.bytes += len(seg)
                self.packets += 1
            self.frames += 1
            return (len(data) + self.chunk - 1) // self.chunk

        if self.mode == MODE_RGB565:
            # RGB565 裸数据：BGR -> RGB565 打包成 16bit
            rgb565 = cv2.cvtColor(frame, cv2.COLOR_BGR2BGR565)
            data = rgb565.tobytes()
            for i in range(0, len(data), self.chunk):
                seg = data[i:i+self.chunk]
                self.sock.sendto(seg, (self.dst_ip, self.dst_port))
                self.bytes += len(seg)
                self.packets += 1
            self.frames += 1
            return (len(data) + self.chunk - 1) // self.chunk

        if self.mode == MODE_RAW:
            raw = frame.astype(np.uint8)
            if self.raw_pix == PIX_YUYV:
                raw = cv2.cvtColor(raw, cv2.COLOR_BGR2YUV_YUYV)
            return self._send_payload(raw.tobytes(), raw=True)

        ok, buf = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), self.quality])
        if not ok:
            self._log("JPEG 编码失败")
            return 0
        return self._send_payload(buf.tobytes(), raw=False)

    def _send_payload(self, payload, raw=False):
        total = (len(payload) + self.chunk - 1) // self.chunk
        fid = self.frame_id & 0xFFFF
        self.frame_id += 1
        base_flags = FLAG_RAW if raw else 0
        for i in range(total):
            seg = payload[i * self.chunk:(i + 1) * self.chunk]
            flags = base_flags
            if i == 0:
                flags |= FLAG_FIRST
            if i == total - 1:
                flags |= FLAG_LAST
            pkt = HDR.pack(MAGIC, fid, i, total, len(seg), flags, 0) + seg
            self.sock.sendto(pkt, (self.dst_ip, self.dst_port))
            self.bytes += len(pkt)
        self.packets += total
        self.frames += 1
        return total

    def _loop(self):
        try:
            kind, src = self._open_source()
        except Exception as e:
            self.error = str(e)
            self._log("帧源打开失败：%s" % e)
            self._run.clear()
            return

        idx = 0
        while self._run.is_set():
            t0 = time.monotonic()
            if kind == "cap":
                ok, frame = src.read()
                if not ok or frame is None:
                    if self.loop:
                        src.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        time.sleep(0.02)
                        continue
                    self._log("视频源播放结束")
                    break
            elif kind == "dir":
                frame = cv2.imread(src[idx % len(src)])
                idx += 1
                if frame is None:
                    continue
                if not self.loop and idx >= len(src):
                    self.send_frame(frame)
                    break
            else:
                frame = self._test_frame(idx)
                idx += 1

            try:
                self.send_frame(frame)
            except OSError as e:
                self.error = str(e)
                self._log("发送失败：%s" % e)
                break

            self._emit_stats()
            delay = max(0.0, (1.0 / self.fps) - (time.monotonic() - t0))
            if delay > 0:
                time.sleep(delay)

        if kind == "cap" and src is not None:
            src.release()
        self._run.clear()
        self._emit_stats(force=True)

    def _emit_stats(self, force=False):
        now = time.monotonic()
        if not force and (now - self._t_stat) < 0.4:
            return
        dt = max(now - self._t_stat, 1e-6)
        self.fps_real = (self.frames - self._n_frames_stat) / dt
        self.bitrate = (self.bytes - self._n_bytes_stat) / dt
        self._n_frames_stat = self.frames
        self._n_bytes_stat = self.bytes
        self._t_stat = now

    def snapshot(self):
        return {"frames": self.frames, "fps": self.fps_real,
                "bitrate": self.bitrate, "packets": self.packets,
                "running": self.running}


# ============================================================
# 录像（MJPG AVI）
# ============================================================
class VideoRecorder:
    def __init__(self, path, fps=25.0, on_log=None):
        self.path = path
        self.fps = max(1.0, float(fps))
        self.on_log = on_log
        self.q = queue.Queue(maxsize=240)
        self.writer = None
        self._run = threading.Event()
        self._thr = threading.Thread(target=self._loop, name="rec", daemon=True)
        self.written = 0

    def start(self):
        self._run.set()
        self._thr.start()

    def feed(self, frame):
        try:
            self.q.put_nowait(frame)
        except queue.Full:
            pass

    def stop(self):
        self._run.clear()
        try:
            self.q.put_nowait(None)
        except queue.Full:
            pass
        self._thr.join(timeout=3.0)
        if self.writer:
            self.writer.release()
            self.writer = None
        if self.on_log:
            self.on_log("录像已保存：%s（%d 帧）" % (self.path, self.written))

    def _loop(self):
        while True:
            try:
                frame = self.q.get(timeout=0.4)
            except queue.Empty:
                if not self._run.is_set():
                    break
                continue
            if frame is None:
                break
            if self.writer is None:
                h, w = frame.shape[:2]
                self.writer = cv2.VideoWriter(self.path, cv2.VideoWriter_fourcc(*"MJPG"),
                                              self.fps, (w, h))
                if not self.writer.isOpened():
                    if self.on_log:
                        self.on_log("录像文件创建失败：%s" % self.path)
                    self.writer = None
                    break
            self.writer.write(frame)
            self.written += 1


# ============================================================
# 图形界面（PySide6）
# ============================================================
QSS = """
QWidget { background:#1b1f27; color:#d7dde7;
          font-family:"Microsoft YaHei UI","Segoe UI"; font-size:12px; }
QTabWidget::pane { border:1px solid #2b3240; border-radius:6px; background:#1b1f27; }
QTabBar::tab { background:#161a21; color:#9aa4b2; padding:8px 20px;
               border:1px solid #2b3240; border-bottom:none;
               border-top-left-radius:6px; border-top-right-radius:6px; margin-right:2px; }
QTabBar::tab:selected { background:#232a35; color:#e8eef7; }
QGroupBox { border:1px solid #2b3240; border-radius:6px; margin-top:14px;
            padding:10px 8px 8px 8px; font-weight:bold; }
QGroupBox::title { subcontrol-origin:margin; left:10px; padding:0 5px; color:#7fa6d6; }
QLabel { background:transparent; }
QLineEdit, QComboBox { background:#12161d; border:1px solid #333c4b; border-radius:4px;
                       padding:5px 7px; selection-background-color:#2f6fbf; }
QLineEdit:focus, QComboBox:focus { border:1px solid #3d7fd0; }
QComboBox QAbstractItemView { background:#12161d; border:1px solid #333c4b;
                              selection-background-color:#2f6fbf; }
QPushButton { background:#2a3140; border:1px solid #3a4453; border-radius:5px;
              padding:7px 12px; min-height:16px; }
QPushButton:hover { background:#333c4d; border-color:#4a576a; }
QPushButton:pressed { background:#222834; }
QPushButton:disabled { color:#5a6270; background:#20242c; border-color:#2a2f38; }
QPushButton#primary { background:#2a5d9e; border-color:#3d7fd0; font-weight:bold; }
QPushButton#primary:hover { background:#316bb4; }
QPushButton#danger { background:#7a2f38; border-color:#a1404c; }
QPushButton#danger:hover { background:#8d3742; }
QPlainTextEdit { background:#0f1319; border:1px solid #2b3240; border-radius:6px;
                 color:#98a3b3; font-family:Consolas,"Microsoft YaHei UI"; }
QCheckBox { spacing:6px; }
QStatusBar { background:#151a22; color:#8b95a5; border-top:1px solid #2b3240; }
QSplitter::handle { background:#1b1f27; }
"""


def build_gui():
    from PySide6.QtCore import Qt, QTimer, QRectF, QSize
    from PySide6.QtGui import QImage, QPixmap, QPainter, QColor, QFont, QIcon
    from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QTabWidget,
                                   QVBoxLayout, QHBoxLayout, QGridLayout, QGroupBox,
                                   QLabel, QLineEdit, QComboBox, QCheckBox, QPushButton,
                                   QPlainTextEdit, QFileDialog, QMessageBox, QSizePolicy,
                                   QSplitter, QFrame, QStatusBar)

    class VideoView(QWidget):
        """等比缩放显示视频帧的画布。"""

        def __init__(self):
            super().__init__()
            self._pix = None
            self._hint = "等待视频流…（在右侧选择端口后点“开始接收”）"
            self.setMinimumSize(320, 240)
            self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

        def set_image(self, qimg):
            self._pix = QPixmap.fromImage(qimg)
            self.update()

        def paintEvent(self, ev):
            p = QPainter(self)
            p.fillRect(self.rect(), QColor("#0b0e13"))
            if self._pix is None or self._pix.isNull():
                p.setPen(QColor("#3f4855"))
                f = QFont("Microsoft YaHei UI", 11)
                p.setFont(f)
                p.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, self._hint)
                p.end()
                return
            sc = self._pix.scaled(self.size(), Qt.AspectRatioMode.KeepAspectRatio,
                                 Qt.TransformationMode.SmoothTransformation)
            x = (self.width() - sc.width()) // 2
            y = (self.height() - sc.height()) // 2
            p.drawPixmap(x, y, sc)
            p.end()

    state = {
        "rx": None,
        "tx": None,
        "rec": None,
        "latest": None,
        "latest_seq": 0,
        "rendered_seq": 0,
        "lock": threading.Lock(),
        "logq": queue.Queue(),
    }

    def log(msg):
        state["logq"].put("[%s] %s" % (time.strftime("%H:%M:%S"), msg))

    base_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    shot_dir = os.path.join(base_dir, "captures")
    rec_dir = os.path.join(base_dir, "recordings")
    try:
        os.makedirs(shot_dir, exist_ok=True)
        os.makedirs(rec_dir, exist_ok=True)
    except Exception:
        shot_dir = rec_dir = base_dir

    def push_frame(frame):
        with state["lock"]:
            state["latest"] = frame
            state["latest_seq"] += 1
            rec = state["rec"]
        if rec is not None:
            rec.feed(frame)

    win = QMainWindow()
    win.setWindowTitle("%s v%s" % (APP_NAME, APP_VER))
    win.resize(1200, 800)
    win.setMinimumSize(1000, 680)

    tabs = QTabWidget()
    win.setCentralWidget(tabs)

    # ---------------- 接收页 ----------------
    rx_page = QWidget()
    tabs.addTab(rx_page, "  接收 RX  ")
    rx_layout = QHBoxLayout(rx_page)
    rx_layout.setContentsMargins(10, 10, 10, 10)
    rx_layout.setSpacing(10)

    left = QVBoxLayout()
    left.setSpacing(8)
    video = VideoView()
    left.addWidget(video, 1)
    logview = QPlainTextEdit()
    logview.setReadOnly(True)
    logview.setFixedHeight(140)
    left.addWidget(logview, 0)
    rx_layout.addLayout(left, 1)

    side = QWidget()
    side.setFixedWidth(378)
    side_layout = QVBoxLayout(side)
    side_layout.setContentsMargins(0, 0, 0, 0)
    side_layout.setSpacing(8)
    rx_layout.addWidget(side, 0)

    g_net = QGroupBox("网络参数")
    f_net = QGridLayout(g_net)
    f_net.setHorizontalSpacing(8)
    f_net.setVerticalSpacing(6)

    mode_combo = QComboBox()
    mode_combo.addItems(RX_MODES)
    local_ip_combo = QComboBox()
    local_ip_combo.setEditable(True)
    local_ip_combo.addItem("0.0.0.0")
    for ip in local_ips():
        local_ip_combo.addItem(ip)
    local_ip_combo.setCurrentIndex(0)
    port_edit = QLineEdit(str(DEFAULT_PORT))
    peer_ip_edit = QLineEdit("")
    peer_ip_edit.setPlaceholderText("留空=接收任意来源")
    peer_port_edit = QLineEdit("")
    peer_port_edit.setPlaceholderText("留空=任意来源端口")
    buf_edit = QLineEdit("4096")

    f_net.addWidget(QLabel("协议类型"), 0, 0)
    f_net.addWidget(mode_combo, 0, 1)
    f_net.addWidget(QLabel("本地地址"), 1, 0)
    f_net.addWidget(local_ip_combo, 1, 1)
    f_net.addWidget(QLabel("本地端口"), 2, 0)
    f_net.addWidget(port_edit, 2, 1)
    f_net.addWidget(QLabel("远程地址"), 3, 0)
    f_net.addWidget(peer_ip_edit, 3, 1)
    f_net.addWidget(QLabel("远程端口"), 4, 0)
    f_net.addWidget(peer_port_edit, 4, 1)
    f_net.addWidget(QLabel("接收缓冲(KB)"), 5, 0)
    f_net.addWidget(buf_edit, 5, 1)
    side_layout.addWidget(g_net)

    g_raw = QGroupBox("RAW 参数（仅原始模式）")
    f_raw = QGridLayout(g_raw)
    f_raw.setHorizontalSpacing(8)
    f_raw.setVerticalSpacing(6)
    raw_w_edit = QLineEdit("1280")
    raw_h_edit = QLineEdit("720")
    pix_combo = QComboBox()
    pix_combo.addItems([PIX_BGR, PIX_YUYV])
    f_raw.addWidget(QLabel("宽度"), 0, 0)
    f_raw.addWidget(raw_w_edit, 0, 1)
    f_raw.addWidget(QLabel("高度"), 1, 0)
    f_raw.addWidget(raw_h_edit, 1, 1)
    f_raw.addWidget(QLabel("像素格式"), 2, 0)
    f_raw.addWidget(pix_combo, 2, 1)
    side_layout.addWidget(g_raw)

    g_btn = QGroupBox("操作")
    f_btn = QGridLayout(g_btn)
    f_btn.setHorizontalSpacing(8)
    f_btn.setVerticalSpacing(8)
    btn_rx_start = QPushButton("开始接收")
    btn_rx_start.setObjectName("primary")
    btn_rx_stop = QPushButton("停止接收")
    btn_rx_stop.setObjectName("danger")
    btn_rx_stop.setEnabled(False)
    btn_rec = QPushButton("开始录像")
    btn_rec.setEnabled(False)
    btn_shot = QPushButton("抓拍")
    btn_shot.setEnabled(False)
    f_btn.addWidget(btn_rx_start, 0, 0)
    f_btn.addWidget(btn_rx_stop, 0, 1)
    f_btn.addWidget(btn_rec, 1, 0)
    f_btn.addWidget(btn_shot, 1, 1)
    side_layout.addWidget(g_btn)

    g_stat = QGroupBox("实时统计")
    f_stat = QGridLayout(g_stat)
    f_stat.setHorizontalSpacing(10)
    f_stat.setVerticalSpacing(4)
    stat_labels = {}
    rows = [("peer", "对端地址"), ("size", "分辨率"), ("fps", "帧  率"),
            ("bitrate", "码  率"), ("frames", "已收帧"), ("dropped", "丢帧率"),
            ("decode", "解码失败"), ("packets", "包数 / 包率"), ("latency", "最近帧距")]
    for i, (k, name) in enumerate(rows):
        f_stat.addWidget(QLabel(name), i, 0)
        lab = QLabel("-")
        lab.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        lab.setStyleSheet("color:#e8eef7; font-family:Consolas,'Microsoft YaHei UI'; font-weight:bold;")
        f_stat.addWidget(lab, i, 1)
        stat_labels[k] = lab
    side_layout.addWidget(g_stat)
    side_layout.addStretch(1)

    # ---------------- 发送页 ----------------
    tx_page = QWidget()
    tabs.addTab(tx_page, "  发送 TX  ")
    tx_layout = QVBoxLayout(tx_page)
    tx_layout.setContentsMargins(10, 10, 10, 10)
    tx_layout.setSpacing(8)

    g_dst = QGroupBox("目标与协议")
    f_dst = QGridLayout(g_dst)
    f_dst.setHorizontalSpacing(10)
    f_dst.setVerticalSpacing(8)

    # 配置历史
    cfg_combo = QComboBox()
    cfg_combo.setEditable(True)
    cfg_combo.addItem("（未保存配置）")
    btn_cfg_load = QPushButton("加载")
    btn_cfg_save = QPushButton("保存")
    btn_cfg_del = QPushButton("删除")
    f_dst.addWidget(QLabel("配置方案"), 0, 0)
    f_dst.addWidget(cfg_combo, 0, 1, 1, 3)
    f_dst.addWidget(btn_cfg_load, 0, 4)
    f_dst.addWidget(btn_cfg_save, 0, 5)
    f_dst.addWidget(btn_cfg_del, 0, 6)

    dst_ip_edit = QLineEdit("192.168.137.100")
    dst_port_edit = QLineEdit(str(DEFAULT_PORT))
    chunk_edit = QLineEdit(str(DEFAULT_CHUNK))
    fps_edit = QLineEdit("25")
    qual_edit = QLineEdit(str(DEFAULT_JPEG_Q))
    tx_mode_combo = QComboBox()
    tx_mode_combo.addItems(TX_MODES)
    tx_local_combo = QComboBox()
    tx_local_combo.setEditable(True)
    tx_local_combo.addItem("0.0.0.0")
    for ip in local_ips():
        tx_local_combo.addItem(ip)
    tx_local_combo.setCurrentIndex(0)
    bcast_box = QCheckBox("广播发送（255.255.255.255）")
    local_ip_lab = QLabel("本机 IP：" + "  /  ".join(local_ips()))
    local_ip_lab.setStyleSheet("color:#7fa6d6;")

    f_dst.addWidget(QLabel("远程地址"), 0, 0)
    f_dst.addWidget(dst_ip_edit, 0, 1)
    f_dst.addWidget(QLabel("远程端口"), 0, 2)
    f_dst.addWidget(dst_port_edit, 0, 3)
    f_dst.addWidget(local_ip_lab, 0, 4, 1, 2)

    f_dst.addWidget(QLabel("本地地址"), 1, 0)
    f_dst.addWidget(tx_local_combo, 1, 1)
    f_dst.addWidget(QLabel("分片字节"), 1, 2)
    f_dst.addWidget(chunk_edit, 1, 3)
    f_dst.addWidget(bcast_box, 1, 4, 1, 2)

    f_dst.addWidget(QLabel("协议类型"), 2, 0)
    f_dst.addWidget(tx_mode_combo, 2, 1)
    f_dst.addWidget(QLabel("目标帧率"), 2, 2)
    f_dst.addWidget(fps_edit, 2, 3)
    f_dst.addWidget(QLabel("JPEG 质量"), 2, 4)
    f_dst.addWidget(qual_edit, 2, 5)
    f_dst.setColumnStretch(1, 1)
    f_dst.setColumnStretch(3, 1)
    f_dst.setColumnStretch(5, 1)
    tx_layout.addWidget(g_dst)

    g_src = QGroupBox("帧源")
    f_src = QGridLayout(g_src)
    f_src.setHorizontalSpacing(10)
    f_src.setVerticalSpacing(8)
    src_combo = QComboBox()
    src_combo.addItems([UdpSender.SRC_TEST, UdpSender.SRC_CAM,
                        UdpSender.SRC_FILE, UdpSender.SRC_DIR])
    loop_box = QCheckBox("循环播放")
    loop_box.setChecked(True)
    src_path_edit = QLineEdit("0")
    btn_pick_file = QPushButton("选视频")
    btn_pick_dir = QPushButton("选目录")

    f_src.addWidget(QLabel("来源类型"), 0, 0)
    f_src.addWidget(src_combo, 0, 1)
    f_src.addWidget(loop_box, 0, 2)
    f_src.addWidget(QLabel("摄像头序号 / 文件或目录路径"), 1, 0)
    f_src.addWidget(src_path_edit, 2, 0, 1, 2)
    f_src.addWidget(btn_pick_file, 2, 2)
    f_src.addWidget(btn_pick_dir, 2, 3)
    f_src.setColumnStretch(1, 2)
    f_src.setColumnStretch(2, 1)
    tx_layout.addWidget(g_src)

    g_txbtn = QGroupBox("控制")
    f_txbtn = QHBoxLayout(g_txbtn)
    btn_tx_start = QPushButton("开始发送")
    btn_tx_start.setObjectName("primary")
    btn_tx_stop = QPushButton("停止发送")
    btn_tx_stop.setObjectName("danger")
    btn_tx_stop.setEnabled(False)
    btn_still = QPushButton("发送单张图片")
    f_txbtn.addWidget(btn_tx_start)
    f_txbtn.addWidget(btn_tx_stop)
    f_txbtn.addWidget(btn_still)
    f_txbtn.addStretch(1)
    tx_layout.addWidget(g_txbtn)

    g_txstat = QGroupBox("发送统计")
    f_txstat = QGridLayout(g_txstat)
    tx_stat_labels = {}
    for i, (k, name) in enumerate([("frames", "已发帧"), ("fps", "发送帧率"),
                                   ("bitrate", "码率"), ("packets", "已发包")]):
        f_txstat.addWidget(QLabel(name), 0, i * 2)
        lab = QLabel("-")
        lab.setStyleSheet("color:#e8eef7; font-family:Consolas,'Microsoft YaHei UI'; font-weight:bold;")
        f_txstat.addWidget(lab, 0, i * 2 + 1)
        tx_stat_labels[k] = lab
    tx_layout.addWidget(g_txstat)

    tip = QLabel("提示：先在“接收 RX”页选好协议类型与本地地址/端口后点“开始接收”，"
                 "再把接收页“远程地址”填 127.0.0.1（或留空）、发送页远程地址填 127.0.0.1、"
                 "两端端口相同、来源选“内置测试图”，点“开始发送”，即可本机环回验证整条链路。\n"
                 "对接板子时：接收页“远程地址/远程端口”填开发板 IP 与其发送端口（留空则接收任意来源）；"
                 "发送页“远程地址/远程端口”填板子接收地址；两边协议类型必须一致。")
    tip.setWordWrap(True)
    tip.setStyleSheet("color:#7c8698;")
    tx_layout.addWidget(tip)
    tx_layout.addStretch(1)

    # ---------------- 说明页 ----------------
    info_page = QWidget()
    tabs.addTab(info_page, "  协议说明  ")
    info_layout = QVBoxLayout(info_page)
    info_layout.setContentsMargins(10, 10, 10, 10)
    info_edit = QPlainTextEdit()
    info_edit.setReadOnly(True)
    info_edit.setPlainText(PROTOCOL_DOC)
    info_layout.addWidget(info_edit)

    # ---------------- 状态栏 ----------------
    sbar = QStatusBar()
    win.setStatusBar(sbar)
    status_lab = QLabel("未接收")
    sbar.addWidget(status_lab)
    sbar.addPermanentWidget(QLabel("UDP · 以太网 · v%s" % APP_VER))

    # ============================================================
    # 行为逻辑
    # ============================================================
    def start_rx():
        if state["rx"] and state["rx"].running:
            return
        try:
            port = int(port_edit.text())
            buf = int(buf_edit.text())
            rw = int(raw_w_edit.text())
            rh = int(raw_h_edit.text())
            peer_ip = peer_ip_edit.text().strip()
            peer_port = int(peer_port_edit.text().strip() or 0)
        except ValueError:
            QMessageBox.warning(win, APP_NAME,
                                "端口 / 缓冲 / 分辨率 / 远程端口必须是整数（远程端口可留空）")
            return
        try:
            rx = UdpReceiver(port, mode_combo.currentText(), rcvbuf_kb=buf,
                             bind_ip=local_ip_combo.currentText().strip(),
                             raw_w=rw, raw_h=rh, raw_pix=pix_combo.currentText(),
                             peer_ip=peer_ip, peer_port=peer_port,
                             on_frame=push_frame, on_log=log)
            rx.start()
        except OSError as e:
            code = getattr(e, "winerror", None) or (10048 if "10048" in str(e) else 0)
            if code in (10048, 10013):
                QMessageBox.critical(
                    win, APP_NAME,
                    "端口 %s 已被本机其他程序占用，无法监听。\n\n"
                    "本机常见占用来源：NI（LabVIEW）服务 nidmsrv / lktsrv 默认占用 UDP 5000、5001。\n"
                    "解决办法：\n"
                    "  1) 换一个空闲端口（例如 5002 / 6000 / 8888），并让板子发往同一端口；\n"
                    "  2) 或以管理员权限停止占用该端口的服务后，再用 %s。" % (port, port))
            else:
                QMessageBox.critical(win, APP_NAME, "启动接收失败：%s" % e)
            return
        except Exception as e:
            QMessageBox.critical(win, APP_NAME, "启动接收失败：%s" % e)
            return
        state["rx"] = rx
        btn_rx_start.setEnabled(False)
        btn_rx_stop.setEnabled(True)
        btn_rec.setEnabled(True)
        btn_shot.setEnabled(True)
        status_lab.setText("接收中  本地 %s:%d  ·  %s" % (rx.bind_ip, rx.actual_port, rx.mode))
        status_lab.setStyleSheet("color:#7ee787;")
        tabs.setCurrentWidget(rx_page)

    def stop_rx():
        rx = state["rx"]
        btn_rx_start.setEnabled(True)
        btn_rx_stop.setEnabled(False)
        btn_rec.setEnabled(False)
        btn_shot.setEnabled(False)
        status_lab.setText("未接收")
        status_lab.setStyleSheet("color:#8b95a5;")
        if state["rec"] is not None:
            toggle_rec()
        if rx:
            threading.Thread(target=rx.stop, daemon=True).start()

    def toggle_rec():
        rec = state["rec"]
        if rec is None:
            rx = state["rx"]
            if not rx or not rx.running or not rx.w:
                QMessageBox.information(win, APP_NAME, "还没有收到画面，无法开始录像")
                return
            path = os.path.join(rec_dir, "record_%s.avi" % time.strftime("%Y%m%d_%H%M%S"))
            rec = VideoRecorder(path, fps=rx.fps if rx.fps > 1 else 25.0, on_log=log)
            state["rec"] = rec
            rec.start()
            btn_rec.setText("停止录像")
            log("开始录像：%s" % path)
        else:
            state["rec"] = None
            btn_rec.setText("开始录像")
            threading.Thread(target=rec.stop, daemon=True).start()

    def take_shot():
        with state["lock"]:
            frame = state["latest"]
        if frame is None:
            QMessageBox.information(win, APP_NAME, "暂无画面可抓拍")
            return
        path = os.path.join(shot_dir, "shot_%s.png" % time.strftime("%Y%m%d_%H%M%S"))
        ok = bool(cv2.imwrite(path, frame))
        log(("截图已保存：" + path) if ok else ("截图保存失败：" + path))

    def start_tx():
        if state["tx"] and state["tx"].running:
            return
        try:
            dst = "255.255.255.255" if bcast_box.isChecked() else dst_ip_edit.text().strip()
            tx = UdpSender(dst, int(dst_port_edit.text()),
                           chunk=int(chunk_edit.text()), fps=float(fps_edit.text()),
                           quality=int(qual_edit.text()),
                           source=src_combo.currentText(), source_arg=src_path_edit.text(),
                           loop=loop_box.isChecked(), mode=tx_mode_combo.currentText(),
                           raw_w=int(raw_w_edit.text()), raw_h=int(raw_h_edit.text()),
                           raw_pix=pix_combo.currentText(),
                           bind_ip=tx_local_combo.currentText().strip(),
                           broadcast=bcast_box.isChecked(), on_log=log)
            tx.start()
        except Exception as e:
            QMessageBox.critical(win, APP_NAME, "启动发送失败：%s" % e)
            return
        state["tx"] = tx
        btn_tx_start.setEnabled(False)
        btn_tx_stop.setEnabled(True)
        # 自动保存当前配置为上次使用
        try:
            cfg = load_config_file()
            cfg["last_profile"] = cfg_combo.currentText().strip() if cfg_combo.currentText().strip() != "（未保存配置）" else None
            save_config_file(cfg)
        except Exception:
            pass

    def stop_tx():
        tx = state["tx"]
        btn_tx_start.setEnabled(True)
        btn_tx_stop.setEnabled(False)
        if tx:
            threading.Thread(target=tx.stop, daemon=True).start()

    def send_still():
        p, _ = QFileDialog.getOpenFileName(win, "选择要发送的图片", "",
                                           "图片 (*.jpg *.jpeg *.png *.bmp);;全部 (*.*)")
        if not p:
            return
        img = cv2.imread(p)
        if img is None:
            QMessageBox.warning(win, APP_NAME, "图片读取失败")
            return
        tx = state["tx"]
        if tx is None or not tx.running:
            try:
                dst = "255.255.255.255" if bcast_box.isChecked() else dst_ip_edit.text().strip()
                tx = UdpSender(dst, int(dst_port_edit.text()), chunk=int(chunk_edit.text()),
                               quality=int(qual_edit.text()), mode=tx_mode_combo.currentText(),
                               bind_ip=tx_local_combo.currentText().strip(),
                               broadcast=bcast_box.isChecked())
            except Exception as e:
                QMessageBox.critical(win, APP_NAME, "参数错误：%s" % e)
                return
        try:
            n = tx.send_frame(img)
            log("单张图片已发送：%d 个包 -> %s:%s" % (n, tx.dst_ip, tx.dst_port))
        except Exception as e:
            QMessageBox.critical(win, APP_NAME, "发送失败：%s" % e)

    def pick_file():
        p, _ = QFileDialog.getOpenFileName(win, "选择视频文件", "",
                                           "视频 (*.mp4 *.avi *.mkv *.mov *.flv);;全部 (*.*)")
        if p:
            src_combo.setCurrentText(UdpSender.SRC_FILE)
            src_path_edit.setText(p)

    def pick_dir():
        d = QFileDialog.getExistingDirectory(win, "选择图片目录")
        if d:
            src_combo.setCurrentText(UdpSender.SRC_DIR)
            src_path_edit.setText(d)

    btn_rx_start.clicked.connect(start_rx)
    btn_rx_stop.clicked.connect(stop_rx)
    btn_rec.clicked.connect(toggle_rec)
    btn_shot.clicked.connect(take_shot)
    btn_tx_start.clicked.connect(start_tx)
    btn_tx_stop.clicked.connect(stop_tx)
    btn_still.clicked.connect(send_still)
    btn_pick_file.clicked.connect(pick_file)
    btn_pick_dir.clicked.connect(pick_dir)

    # ---------------- 配置保存/加载 ----------------
    import json
    def load_config_file():
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return {"profiles": {}}

    def save_config_file(cfg):
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(cfg, f, ensure_ascii=False, indent=2)
        except Exception as e:
            log("配置保存失败：%s" % e)

    def collect_tx_params():
        return {
            "dst_ip": dst_ip_edit.text().strip(),
            "dst_port": dst_port_edit.text().strip(),
            "chunk": chunk_edit.text().strip(),
            "fps": fps_edit.text().strip(),
            "quality": qual_edit.text().strip(),
            "mode": tx_mode_combo.currentText(),
            "local": tx_local_combo.currentText().strip(),
            "broadcast": bcast_box.isChecked(),
            "src_type": src_combo.currentText(),
            "src_path": src_path_edit.text().strip(),
            "loop": loop_box.isChecked(),
        }

    def apply_tx_params(p):
        dst_ip_edit.setText(p.get("dst_ip", "127.0.0.1"))
        dst_port_edit.setText(p.get("dst_port", "5002"))
        chunk_edit.setText(p.get("chunk", str(DEFAULT_CHUNK)))
        fps_edit.setText(p.get("fps", "25"))
        qual_edit.setText(p.get("quality", str(DEFAULT_JPEG_Q)))
        idx = tx_mode_combo.findText(p.get("mode", TX_MODES[0]))
        if idx >= 0: tx_mode_combo.setCurrentIndex(idx)
        tx_local_combo.setCurrentText(p.get("local", "0.0.0.0"))
        bcast_box.setChecked(p.get("broadcast", False))
        src_combo.setCurrentText(p.get("src_type", UdpSender.SRC_TEST))
        src_path_edit.setText(p.get("src_path", "0"))
        loop_box.setChecked(p.get("loop", True))

    def refresh_cfg_list():
        cfg = load_config_file()
        cfg_combo.blockSignals(True)
        cfg_combo.clear()
        cfg_combo.addItem("（未保存配置）")
        for name in sorted(cfg.get("profiles", {}).keys()):
            cfg_combo.addItem(name)
        cfg_combo.blockSignals(False)

    def do_save_cfg():
        name = cfg_combo.currentText().strip()
        if not name or name == "（未保存配置）":
            QMessageBox.information(win, APP_NAME, "请先在下拉框输入配置名称")
            return
        cfg = load_config_file()
        cfg.setdefault("profiles", {})[name] = collect_tx_params()
        save_config_file(cfg)
        refresh_cfg_list()
        idx = cfg_combo.findText(name)
        if idx >= 0: cfg_combo.setCurrentIndex(idx)
        log("配置已保存：%s" % name)

    def do_load_cfg():
        name = cfg_combo.currentText().strip()
        if not name or name == "（未保存配置）":
            return
        cfg = load_config_file()
        p = cfg.get("profiles", {}).get(name)
        if p:
            apply_tx_params(p)
            log("配置已加载：%s" % name)

    def do_del_cfg():
        name = cfg_combo.currentText().strip()
        if not name or name == "（未保存配置）":
            return
        cfg = load_config_file()
        if name in cfg.get("profiles", {}):
            del cfg["profiles"][name]
            save_config_file(cfg)
            refresh_cfg_list()
            log("配置已删除：%s" % name)

    btn_cfg_save.clicked.connect(do_save_cfg)
    btn_cfg_load.clicked.connect(do_load_cfg)
    btn_cfg_del.clicked.connect(do_del_cfg)
    refresh_cfg_list()

    # 启动时自动加载上次使用的配置
    cfg = load_config_file()
    last = cfg.get("last_profile")
    if last and last in cfg.get("profiles", {}):
        idx = cfg_combo.findText(last)
        if idx >= 0:
            cfg_combo.setCurrentIndex(idx)
            apply_tx_params(cfg["profiles"][last])

    # ---------------- 定时刷新 ----------------
    def tick():
        # 日志
        drained = 0
        try:
            while drained < 60:
                msg = state["logq"].get_nowait()
                logview.appendPlainText(msg)
                drained += 1
        except queue.Empty:
            pass
        if drained >= 59:
            logview.verticalScrollBar().setValue(logview.verticalScrollBar().maximum())

        # 画面
        seq = state["latest_seq"]
        if seq != state["rendered_seq"]:
            with state["lock"]:
                frame = state["latest"]
            state["rendered_seq"] = seq
            if frame is not None:
                try:
                    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    h, w = rgb.shape[:2]
                    qimg = QImage(rgb.data, w, h, rgb.strides[0], QImage.Format.Format_RGB888).copy()
                    video.set_image(qimg)
                except Exception:
                    pass

        # 接收统计
        rx = state["rx"]
        if rx is not None and rx.running:
            s = rx.snapshot()
            stat_labels["peer"].setText(s["peer"])
            stat_labels["size"].setText(s["size"])
            stat_labels["fps"].setText("%.1f" % s["fps"])
            stat_labels["bitrate"].setText(fmt_rate(s["bitrate"]))
            stat_labels["frames"].setText(str(s["frames"]))
            stat_labels["dropped"].setText("%d (%.1f%%)" % (s["dropped"], s["drop_rate"]))
            stat_labels["decode"].setText(str(s["decode_fail"]))
            stat_labels["packets"].setText("%d / %.0f" % (s["packets"], s["pkt_rate"]))
            stat_labels["latency"].setText("%.0f ms" % s["latency"])
        elif rx is not None and not rx.running and btn_rx_stop.isEnabled():
            stop_rx()

        # 发送统计
        tx = state["tx"]
        if tx is not None:
            s = tx.snapshot()
            tx_stat_labels["frames"].setText(str(s["frames"]))
            tx_stat_labels["fps"].setText("%.1f" % s["fps"])
            tx_stat_labels["bitrate"].setText(fmt_rate(s["bitrate"]))
            tx_stat_labels["packets"].setText(str(s["packets"]))
            if not s["running"] and btn_tx_stop.isEnabled():
                btn_tx_start.setEnabled(True)
                btn_tx_stop.setEnabled(False)

    timer = QTimer(win)
    timer.timeout.connect(tick)
    timer.start(30)

    def on_close(ev):
        try:
            if state["tx"] is not None:
                state["tx"]._run.clear()
            if state["rec"] is not None:
                state["rec"].stop()
            if state["rx"] is not None:
                state["rx"]._run.clear()
                if state["rx"].sock:
                    state["rx"].sock.close()
        except Exception:
            pass
        ev.accept()

    win.closeEvent = on_close

    log("程序启动，工作目录：%s" % base_dir)
    log("接收：设置端口后点“开始接收”；发送：可用“内置测试图”先做本机环回。")
    log("截图存于 captures\\，录像存于 recordings\\。")

    win.show()
    return win


PROTOCOL_DOC = """【UDP 视频传输上位机 · 协议说明】

一、可切换的协议类型（收发两端必须一致，在界面的“协议类型”下拉框中选择）

1) JPEG 分片（带头）—— 推荐，适合 FPGA / Zynq 把 JPEG 编码结果分片发送
   每个 UDP 包 = 12 字节头 + 负载，头结构（C 语言，1 字节对齐，小端）：

       #pragma pack(push, 1)
       typedef struct {
           unsigned short magic;       // 0xB7C5
           unsigned short frame_id;    // 帧号，每帧 +1
           unsigned short pkt_index;   // 分片序号 0 .. pkt_total-1
           unsigned short pkt_total;   // 本帧分片总数
           unsigned short payload_len; // 本包负载长度
           unsigned char  flags;       // bit0=首片 bit1=末片 bit2=RAW
           unsigned char  reserved;    // 0
       } udp_video_hdr_t;             // sizeof == 12
       #pragma pack(pop)

   板子侧发送示例（裸机 / lwIP）：

       int total = (jpeg_len + CHUNK - 1) / CHUNK;        // CHUNK 建议 1400
       for (int i = 0; i < total; i++) {
           int off = i * CHUNK;
           int len = (jpeg_len - off) < CHUNK ? (jpeg_len - off) : CHUNK;
           udp_video_hdr_t h;
           h.magic       = 0xB7C5;
           h.frame_id    = (frame_cnt++) & 0xFFFF;
           h.pkt_index   = i;
           h.pkt_total   = total;
           h.payload_len = len;
           h.flags       = (i == 0 ? 1 : 0) | (i == total - 1 ? 2 : 0);
           h.reserved    = 0;
           memcpy(pkt, &h, 12);                       // 按小端写入
           memcpy(pkt + 12, jpeg_buf + off, len);
           udp_sendto(sock, pkt, 12 + len, dst_ip, port);
       }

2) JPEG 单包（无头）—— 每个 UDP 包就是一整帧 JPEG，不分片
   适合小分辨率（640x480、QVGA）或带宽充裕的场景。
   注意单包不要超过 1472 字节（以太网 MTU），超了上位机会自动降级为分片发送。

3) 原始 RAW（行分片）—— 未压缩像素按 CHUNK 切片发送
   接收端要填对分辨率与像素格式：
       BGR888：每帧字节 = 宽 × 高 × 3
       YUYV422：每帧字节 = 宽 × 高 × 2
   适合 FPGA 直接吐 VDMA 帧缓冲、还没做 JPEG 编码的联调阶段。

4) 自动识别（仅接收端）—— 每个包先看开头是不是 0xB7C5 魔数：
   是就按分片重组，不是就按“整帧 JPEG”尝试解码。板子协议还没定下来时先切它，
   两种格式都能收。

5) JPEG 裸流（FFD8/FFD9 拼帧）—— 本工程（Vitis UDP_camera）用的就是这种：
   每包固定 1024 字节，包内没有任何包头，内容是 OV5640 硬件 JPEG 的原始字节流；
   包边界和帧边界无关，一帧跨若干包，一个包里也可能含着“上一帧结尾 + 下一帧开头”。
   上位机把收到的字节按顺序拼起来，遇到 FF D8（SOI）开始算一帧、
   遇到 FF D9（EOI）就切出一整帧去解码。
   注意：这种格式没有包序号，丢包时会把两帧拼坏（表现为解码失败计数上升、花屏），
   排查方向是降分辨率/降帧率、减小每包字节数，或给板子加 4 字节包头后改用模式 1。

二、地址与端口
   接收 RX：
       · 协议类型：与发送端一致；
       · 本地地址：下拉选本机网卡 IP（如 192.168.1.10），或 0.0.0.0 监听全部网卡；
       · 本地端口：上位机在该端口收包（默认 5001）；
       · 远程地址 / 远程端口：只接受该来源的包，留空表示不过滤（多设备同网段时用它区分）；
       · 接收缓冲：默认 4096 KB，越大越抗突发；仍丢包就降码率或减小分片。
   发送 TX：
       · 远程地址 / 远程端口：板子 IP 与它监听的端口；
       · 本地地址：多网卡机器指定出口网卡（0.0.0.0 由系统选路）；
       · 若板子固定发往 5001，而本机 5001 被 NI（LabVIEW）服务（nidmsrv/lktsrv）占用，
         就换个端口，或停掉占用端口的服务。
   建议千兆直连或独立交换机，板子与 PC 同网段，放行该 UDP 端口的防火墙。
   单向传输不需要握手，上位机随时可开可关。

三、典型故障对照
   · 只有包计数、没画面：payload_len 与实际长度不符，或 frame_id 不连续
     （重组超时 0.6 s，判为丢帧）。检查 memcpy 长度与 pkt_total 计算。
   · 画面局部花块：JPEG 分片丢包。降 JPEG 质量、减小分片、检查交换机流控。
   · 完全收不到包：目标 IP/端口不一致、不同网段、防火墙或板子网口未 link。
   · RAW 模式全黑/彩色错位：分辨率或像素格式选错（BGR888 与 YUYV422 不通用）。

四、文件位置
   · 截图：captures\\shot_时间戳.png
   · 录像：recordings\\record_时间戳.avi（MJPG 编码，VLC / PotPlayer 可直接播放）
"""


# ============================================================
# 自检（无界面，验证 发送 -> 分片 -> 重组 -> 解码 链路）
# ============================================================
def run_selftest():
    print("[selftest] JPEG 分片模式环回 ...")
    received = []
    stats = {}
    rx = UdpReceiver(0, MODE_FRAG, bind_ip="127.0.0.1", rcvbuf_kb=2048,
                     raw_w=640, raw_h=480, on_frame=lambda f: received.append(f))
    port = rx.start()
    tx = UdpSender("127.0.0.1", port, chunk=900, fps=60.0, quality=85,
                   source=UdpSender.SRC_TEST, raw_w=640, raw_h=480)
    tx.start()
    time.sleep(3.0)
    tx.stop()
    time.sleep(0.4)
    rx.stop()
    stats.update(rx.snapshot())

    ok = True
    if len(received) < 20:
        print("[selftest] FAIL 收到帧数过少：%d" % len(received))
        ok = False
    h, w = received[0].shape[:2] if received else (0, 0)
    if (w, h) != (640, 480):
        print("[selftest] FAIL 分辨率不符：%dx%d" % (w, h))
        ok = False
    if stats.get("drop_rate", 100) > 5:
        print("[selftest] FAIL 丢帧率过高：%.1f%%" % stats.get("drop_rate", -1))
        ok = False
    print("[selftest] 收到 %d 帧 / 发送 %d 帧，丢帧 %d，解码失败 %d，平均 %.1f fps，%s"
          % (len(received), tx.frames, stats.get("dropped", 0),
             stats.get("decode_fail", 0), len(received) / 3.0,
             fmt_rate(tx.bytes / 3.0)))

    print("[selftest] RAW 模式环回 ...")
    received.clear()
    rx2 = UdpReceiver(0, MODE_RAW, bind_ip="127.0.0.1", rcvbuf_kb=4096,
                      raw_w=320, raw_h=240, raw_pix=PIX_BGR,
                      on_frame=lambda f: received.append(f))
    port2 = rx2.start()
    tx2 = UdpSender("127.0.0.1", port2, chunk=2000, fps=40.0, mode=MODE_RAW,
                    raw_w=320, raw_h=240, raw_pix=PIX_BGR, source=UdpSender.SRC_TEST)
    tx2.start()
    time.sleep(2.0)
    tx2.stop()
    time.sleep(0.3)
    rx2.stop()
    if len(received) < 5:
        print("[selftest] FAIL RAW 帧数过少：%d" % len(received))
        ok = False
    else:
        print("[selftest] RAW 收到 %d 帧，分辨率 %dx%d"
              % (len(received), received[0].shape[1], received[0].shape[0]))

    print("[selftest] 单包 JPEG 模式环回 ...")
    received.clear()
    rx3 = UdpReceiver(0, MODE_SINGLE, bind_ip="127.0.0.1", rcvbuf_kb=2048,
                      on_frame=lambda f: received.append(f))
    port3 = rx3.start()
    tx3 = UdpSender("127.0.0.1", port3, fps=30.0, quality=70, mode=MODE_SINGLE,
                    raw_w=480, raw_h=320, source=UdpSender.SRC_TEST)
    tx3.start()
    time.sleep(2.0)
    tx3.stop()
    time.sleep(0.3)
    rx3.stop()
    if len(received) < 5:
        print("[selftest] FAIL 单包帧数过少：%d" % len(received))
        ok = False
    else:
        print("[selftest] 单包收到 %d 帧，%dx%d"
              % (len(received), received[0].shape[1], received[0].shape[0]))

    print("[selftest] 自动识别模式（单包 JPEG 输入）...")
    received.clear()
    rx4 = UdpReceiver(0, MODE_AUTO, bind_ip="127.0.0.1", rcvbuf_kb=2048,
                      on_frame=lambda f: received.append(f))
    port4 = rx4.start()
    tx4 = UdpSender("127.0.0.1", port4, fps=30.0, quality=70, mode=MODE_SINGLE,
                    raw_w=480, raw_h=320, source=UdpSender.SRC_TEST)
    tx4.start()
    time.sleep(1.5)
    tx4.stop()
    time.sleep(0.3)
    rx4.stop()
    if len(received) < 4:
        print("[selftest] FAIL 自动识别(单包) 帧数过少：%d" % len(received))
        ok = False
    else:
        print("[selftest] 自动识别(单包) 收到 %d 帧" % len(received))

    print("[selftest] 自动识别模式（分片 JPEG 输入）...")
    received.clear()
    rx5 = UdpReceiver(0, MODE_AUTO, bind_ip="127.0.0.1", rcvbuf_kb=2048,
                      on_frame=lambda f: received.append(f))
    port5 = rx5.start()
    tx5 = UdpSender("127.0.0.1", port5, chunk=800, fps=40.0, mode=MODE_FRAG,
                    raw_w=320, raw_h=240, source=UdpSender.SRC_TEST)
    tx5.start()
    time.sleep(1.5)
    tx5.stop()
    time.sleep(0.3)
    rx5.stop()
    if len(received) < 4:
        print("[selftest] FAIL 自动识别(分片) 帧数过少：%d" % len(received))
        ok = False
    else:
        print("[selftest] 自动识别(分片) 收到 %d 帧" % len(received))

    print("[selftest] 远程地址过滤 ...")
    received.clear()
    rx6 = UdpReceiver(0, MODE_FRAG, bind_ip="127.0.0.1", rcvbuf_kb=2048,
                      peer_ip="10.9.9.9", on_frame=lambda f: received.append(f))
    port6 = rx6.start()
    tx6 = UdpSender("127.0.0.1", port6, fps=30.0, mode=MODE_FRAG,
                    raw_w=320, raw_h=240, source=UdpSender.SRC_TEST)
    tx6.start()
    time.sleep(1.2)
    tx6.stop()
    time.sleep(0.3)
    filtered = rx6.filtered
    rx6.stop()
    if received or filtered == 0:
        print("[selftest] FAIL 过滤未生效：收到 %d 帧，丢弃 %d 包" % (len(received), filtered))
        ok = False
    else:
        print("[selftest] 过滤生效：收到 0 帧，丢弃 %d 包" % filtered)

    print("[selftest] JPEG 裸流模式（1024 字节/包、无包头）...")
    received.clear()
    rx7 = UdpReceiver(0, MODE_STREAM, bind_ip="127.0.0.1", rcvbuf_kb=8192,
                      on_frame=lambda f: received.append(f))
    port7 = rx7.start()
    gen = UdpSender("127.0.0.1", port7, raw_w=640, raw_h=480)
    blob = b""
    n_frames = 40
    for i in range(n_frames):
        ok, enc = cv2.imencode(".jpg", gen._test_frame(i),
                               [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        blob += enc.tobytes()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for i in range(0, len(blob), 1024):
        sock.sendto(blob[i:i + 1024], ("127.0.0.1", port7))
        time.sleep(0.0008)
    sock.close()
    time.sleep(0.8)
    rx7.stop()
    if len(received) < n_frames - 2:
        print("[selftest] FAIL 裸流拼帧：%d/%d 帧" % (len(received), n_frames))
        ok = False
    else:
        print("[selftest] 裸流拼帧 ok：%d/%d 帧，末帧 %d 字节，总流长 %d 字节"
              % (len(received), n_frames, rx7.stream.last_frame_len, len(blob)))
        print("[selftest]   拼帧器统计：切帧 %d，丢弃无效字节 %d"
              % (rx7.stream.frames, rx7.stream.junk_bytes))

    print("[selftest] 结果：%s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    argparse.ArgumentParser(add_help=True).parse_known_args()
    if "--selftest" in sys.argv:
        sys.exit(run_selftest())

    from PySide6.QtWidgets import QApplication
    from PySide6.QtGui import QFont
    try:
        QApplication.setHighDpiScaleFactorRoundingPolicy(
            QApplication.highDpiScaleFactorRoundingPolicy())
    except Exception:
        pass
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setStyle("Fusion")
    app.setStyleSheet(QSS)
    try:
        app.setFont(QFont("Microsoft YaHei UI", 9))
    except Exception:
        pass
    try:
        win = build_gui()
        win.show()
    except Exception:
        traceback.print_exc()
        from PySide6.QtWidgets import QMessageBox
        QMessageBox.critical(None, APP_NAME, "界面启动失败:\n%s" % traceback.format_exc())
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
