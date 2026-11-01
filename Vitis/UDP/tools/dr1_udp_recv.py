#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DR1 板子 UDP 视频接收显示端
============================
在 DR1M90 Linux 板子上跑：
    python3 dr1_udp_recv.py --port 5002

接收 PC 发送模拟器（或 Zynq 图传板）发来的 UDP JPEG 流，
拼帧后用 OpenCV 解码显示。

显示方式：
  - 接了 HDMI 显示器：cv2.imshow 直接弹窗口
  - headless 无显示器：加 --save out.mp4 存视频，或 --jpeg-dir ./frames/ 存图
"""
import socket, argparse, time, sys, os
import cv2
import numpy as np

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=5002)
    ap.add_argument("--jpeg-dir", default=None, help="把每帧 JPEG 存到这个目录（调试用）")
    ap.add_argument("--save", default=None, help="把显示结果存成 mp4")
    ap.add_argument("--headless", action="store_true", help="不弹窗，只统计")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rcvbuf = 4 * 1024 * 1024
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcvbuf)
    sock.bind((args.host, args.port))
    print(f"[DR1接收端] 监听 {args.host}:{args.port}")
    print(f"[DR1接收端] 等发送端推流...\n")

    if args.jpeg_dir:
        os.makedirs(args.jpeg_dir, exist_ok=True)

    buf = bytearray()
    cnt = 0
    t0 = time.time()
    writer = None

    try:
        while True:
            data, addr = sock.recvfrom(2048)
            buf.extend(data)

            # 拼帧：FFD8 起 / FFD9 止
            while True:
                s = buf.find(b"\xff\xd8")
                if s < 0:
                    buf.clear()
                    break
                e = buf.find(b"\xff\xd9", s + 2)
                if e < 0:
                    del buf[:s]
                    break
                jpg = bytes(buf[s:e + 2])
                del buf[:e + 2]
                cnt += 1

                if args.jpeg_dir:
                    with open(f"{args.jpeg_dir}/frame_{cnt:05d}.jpg", "wb") as f:
                        f.write(jpg)

                img = cv2.imdecode(np.frombuffer(jpg, np.uint8), cv2.IMREAD_COLOR)
                if img is None:
                    continue

                if writer is None and args.save:
                    h, w = img.shape[:2]
                    writer = cv2.VideoWriter(args.save,
                                             cv2.VideoWriter_fourcc(*"mp4v"), 20, (w, h))

                if writer:
                    writer.write(img)

                if not args.headless:
                    cv2.imshow("DR1 UDP Receiver", img)
                    if cv2.waitKey(1) & 0xFF == ord('q'):
                        sys.exit(0)

                if cnt % 30 == 0:
                    dt = time.time() - t0
                    print(f"  收到 {cnt} 帧, {len(jpg)}B/帧, "
                          f"{cnt/dt:.1f} fps, 来自 {addr[0]}")
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        if writer: writer.release()
        cv2.destroyAllWindows()
        dt = time.time() - t0
        print(f"\n[DR1接收端] 结束，共 {cnt} 帧, 平均 {cnt/dt:.1f} fps")

if __name__ == "__main__":
    main()
