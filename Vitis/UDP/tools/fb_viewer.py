import socket, subprocess, sys, time

# framebuffer 参数
FB_W = 1920
FB_H = 1080
FB_STRIDE = 7680   # 1920*4
FB_BPP = 4

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4*1024*1024)
sock.bind(('0.0.0.0', 5002))
print('listening 5002, writing to /dev/fb0...')

fb = open('/dev/fb0', 'wb')

# 先清屏成全黑
black_row = bytes(FB_STRIDE)
for y in range(FB_H):
    fb.write(black_row)
fb.seek(0)
print('screen cleared')

buf = bytearray()
n = 0
t0 = time.time()

while True:
    data, addr = sock.recvfrom(2048)
    buf.extend(data)
    while True:
        s = buf.find(b'\xff\xd8')
        if s < 0: buf.clear(); break
        e = buf.find(b'\xff\xd9', s+2)
        if e < 0:
            del buf[:s]; break
        jpg = bytes(buf[s:e+2])
        del buf[:e+2]
        n += 1

        # djpeg -> PPM P6
        r = subprocess.run(['djpeg'], input=jpg, capture_output=True)
        ppm = r.stdout
        if not ppm.startswith(b'P6'):
            print('bad ppm, len=%d' % len(ppm))
            continue

        # 解析 PPM header: P6\n + 可选注释行 + <w> <h>\n + <max>\n
        try:
            # 跳过 P6 和可能的注释行
            lines = ppm.split(b'\n')
            i = 1  # 跳过 P6
            while lines[i].startswith(b'#') or lines[i].strip() == b'':
                i += 1
            dims = lines[i].split()
            iw = int(dims[0])
            ih = int(dims[1])
            i += 1
            while lines[i].startswith(b'#') or lines[i].strip() == b'':
                i += 1
            # 数据从 maxval 行之后开始
            # 重新拼接数据部分
            header = b'\n'.join(lines[:i+1]) + b'\n'
            rgb = ppm[len(header):]
        except Exception as ex:
            print('parse err:', ex, 'hdr=', ppm[:50])
            continue

        if len(rgb) < iw * ih * 3:
            print('short rgb: %d < %d' % (len(rgb), iw*ih*3))
            continue

        # 居中位置
        x0 = (FB_W - iw) // 2
        y0 = (FB_H - ih) // 2

        # 每一行：把 RGB888 转成 BGRX8888
        for row in range(ih):
            src = row * iw * 3
            # 构造这一行的 framebuffer 数据
            line = bytearray(FB_STRIDE)
            for col in range(iw):
                r_pix = rgb[src + col*3]
                g_pix = rgb[src + col*3 + 1]
                b_pix = rgb[src + col*3 + 2]
                off = x0 * FB_BPP + col * FB_BPP
                line[off]     = b_pix   # B
                line[off + 1] = g_pix   # G
                line[off + 2] = r_pix   # R
                line[off + 3] = 0       # X
            fb.seek(y0 * FB_STRIDE + row * FB_STRIDE)
            fb.write(line)

        if n % 10 == 0:
            dt = time.time() - t0
            print('frame %d, %dx%d, %.1f fps' % (n, iw, ih, n/dt))
