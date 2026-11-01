#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UDP BGRX 发送器 - 板子收到直接写 fb0，零转换
包头 6 字节: [帧号2][行号2][列偏移2]
每包 400 像素 = 400*4 = 1600 字节 + 6 头
"""
import socket, time
import cv2
import numpy as np

W, H = 640, 480
CHUNK = 400

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dst = ("192.168.137.100", 5002)
print(f"sending BGRX {W}x{H} -> {dst}")

n = 0
t0 = time.time()
while True:
    frame = np.zeros((H, W, 4), dtype=np.uint8)
    # 四个角画 80x80 色块: 左上红, 右上绿, 左下蓝, 右下白
    frame[0:80, 0:80] = (0, 0, 255, 255)       # 左上红
    frame[0:80, W-80:W] = (0, 255, 0, 255)     # 右上绿
    frame[H-80:H, 0:80] = (255, 0, 0, 255)     # 左下蓝
    frame[H-80:H, W-80:W] = (255, 255, 255, 255) # 右下白
    # 中间画个十字线
    frame[H//2-1:H//2+1, :] = (0, 255, 255, 255)  # 水平黄线
    frame[:, W//2-1:W//2+1] = (0, 255, 255, 255)  # 垂直黄线

    flat = frame.tobytes()  # BGRX8888 连续字节

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
    time.sleep(1.0/25)
