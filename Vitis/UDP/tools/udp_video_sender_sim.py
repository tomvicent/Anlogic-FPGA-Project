#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP 视频发送模拟器 —— 模拟 Zynq-7020 OV5640 图传板
============================================
从本地视频文件或摄像头读帧 → JPEG 编码 → 按 1024 字节分包发 UDP
完全复刻 Zynq 板子的发送格式：无头裸流，FFD8 起 / FFD9 止。

用法：
    python3 udp_video_sender_sim.py --video test.mp4 --dst 192.168.1.100 --port 5002
    python3 udp_video_sender_sim.py --camera 0 --dst 192.168.1.100 --port 5002
    python3 udp_video_sender_sim.py --video test.mp4 --dst 127.0.0.1 --port 5002   # 本机环回测试
"""
import socket, argparse, time, sys
import cv2
import numpy as np

# 跟 Zynq 板子保持一致
PKT_SIZE = 1024
JPEG_QUALITY = 70      # OV5640 默认差不多这个量级
FPS_LIMIT = 25         # 模拟摄像头帧率

def main():
    ap = argparse.ArgumentParser(description="模拟 Zynq OV5640 UDP JPEG 图传")
    ap.add_argument("--video", type=str, default=None, help="本地视频文件路径（mp4/avi）")
    ap.add_argument("--camera", type=int, default=None, help="摄像头编号（0=默认）")
    ap.add_argument("--dst", type=str, default="192.168.1.100", help="目标 IP（DR1 板子 IP）")
    ap.add_argument("--port", type=int, default=5002, help="目标 UDP 端口")
    ap.add_argument("--size", type=str, default="640x480", help="发送分辨率 WxH")
    ap.add_argument("--quality", type=int, default=JPEG_QUALITY, help="JPEG 质量 1-100")
    ap.add_argument("--loop", action="store_true", help="视频文件循环播放")
    args = ap.parse_args()

    # 打开视频源
    if args.camera is not None:
        cap = cv2.VideoCapture(args.camera)
        print(f"[发送端] 打开摄像头 /dev/{args.camera}")
    elif args.video:
        cap = cv2.VideoCapture(args.video)
        print(f"[发送端] 打开视频文件: {args.video}")
    else:
        # 默认用一个合成测试图（无摄像头无文件时）
        print("[发送端] 未指定视频源，使用内置测试图（移动的圆）")
        cap = None

    W, H = map(int, args.size.lower().split("x"))

    # UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dst = (args.dst, args.port)
    print(f"[发送端] 目标 {args.dst}:{args.port}, 分包 {PKT_SIZE}B, "
          f"分辨率 {W}x{H}, JPEG Q={args.quality}")
    print(f"[发送端] Ctrl+C 退出\n")

    cnt = 0
    t0 = time.time()
    try:
        while True:
            # 读一帧
            if cap is not None:
                ret, frame = cap.read()
                if not ret:
                    if args.loop and args.video:
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        continue
                    break
                frame = cv2.resize(frame, (W, H))
            else:
                # 标准彩色测试卡：红绿蓝白四色竖条 + 中间黑条 + 时间戳
                frame = np.zeros((H, W, 3), dtype=np.uint8)
                bar_w = W // 4
                frame[:, 0:bar_w] = (0, 0, 255)      # 红 (BGR)
                frame[:, bar_w:2*bar_w] = (0, 255, 0)  # 绿
                frame[:, 2*bar_w:3*bar_w] = (255, 0, 0) # 蓝
                frame[:, 3*bar_w:] = (255, 255, 255)    # 白
                # 中间黑色横条
                frame[H//2-20:H//2+20, :] = (0, 0, 0)
                cv2.putText(frame, f"frame {cnt}", (20, H//2+60),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 255), 3)

            # JPEG 编码
            ok, jpg = cv2.imencode(".jpg", frame,
                                   [cv2.IMWRITE_JPEG_QUALITY, args.quality])
            if not ok:
                continue
            data = jpg.tobytes()

            # 按 1024 字节分包发送（跟 Zynq 完全一致）
            offset = 0
            while offset < len(data):
                chunk = data[offset:offset + PKT_SIZE]
                sock.sendto(chunk, dst)
                offset += PKT_SIZE

            cnt += 1
            if cnt % 30 == 0:
                dt = time.time() - t0
                print(f"  已发 {cnt} 帧, {len(data)}B/帧, "
                      f"实际 {cnt/dt:.1f} fps")

            time.sleep(1.0 / FPS_LIMIT)

    except KeyboardInterrupt:
        pass
    finally:
        if cap: cap.release()
        sock.close()
        dt = time.time() - t0
        print(f"\n[发送端] 结束，共发 {cnt} 帧, 平均 {cnt/dt:.1f} fps")

if __name__ == "__main__":
    main()
