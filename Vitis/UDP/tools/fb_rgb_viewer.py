import socket, time, mmap, os

FB_W = 1920
FB_H = 1080
FB_STRIDE = 7680
FB_SIZE = FB_W * FB_H * 4
IMG_W = 640
IMG_H = 480

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32*1024*1024)
sock.bind(('0.0.0.0', 5002))
print('listening 5002, BGRX direct mode')

fbfd = os.open('/dev/fb0', os.O_RDWR)
fb = mmap.mmap(fbfd, FB_SIZE)
fb.seek(0)
fb.write(bytes(FB_SIZE))
print('screen cleared, waiting...')

x0 = (FB_W - IMG_W) // 2
y0 = (FB_H - IMG_H) // 2
n = 0
t0 = time.time()

while True:
    data, addr = sock.recvfrom(2048)
    if len(data) < 6: continue

    row = data[2] | (data[3] << 8)
    col = data[4] | (data[5] << 8)
    payload = data[6:]

    # 直接写到 fb0 对应位置，零转换
    dst_off = (y0 + row) * FB_STRIDE + (x0 + col) * 4
    fb.seek(dst_off)
    fb.write(payload)

    if col == 0 and row == 0:
        n += 1
        if n % 30 == 0:
            print(f'frame ~{n}, {n/(time.time()-t0):.1f} fps')
