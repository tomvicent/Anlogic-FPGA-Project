#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP BGRX 摄像头发送器 - 读 PC 摄像头，发 BGRX8888 到板子
板子 mmap 直写 fb0，零转换
"""
import socket, time, cv2, numpy as np

W, H = 640, 480
CHUNK = 400

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dst = ("192.168.137.100", 5002)
print(f"sending camera {W}x{H} -> {dst}")

cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, W)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, H)

n = 0
t0 = time.time()
while True:
    ret, frame = cap.read()
    if not ret:
        print("no camera frame")
        time.sleep(0.1)
        continue

    # BGR -> BGRX (补 alpha 通道)
    bgrx = cv2.cvtColor(frame, cv2.COLOR_BGR2BGRA)
    flat = bgrx.tobytes()

    for row in range(H):
        for col_off in range(0, W, CHUNK):
            c_end = min(col_off + CHUNK, W)
            start = (row * W + col_off) * 4
            end = (row * W + c_end) * 4
            chunk = flat[start:end]
            hdr = bytes([n & 0xFF, (n>>8)&0xFF,
                         row & 0xFF, (row>>8)&0xFF,
                         col_off & 0xFF, (col_off>>8)&0xFF])
            sock.sendto(hdr + chunk, dst)

    n += 1
    if n % 30 == 0:
        print(f"sent {n} frames, {n/(time.time()-t0):.1f} fps")

cap.release()
