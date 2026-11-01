from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

DARK = RGBColor(0x1a, 0x1a, 0x2e)
BLUE = RGBColor(0x3d, 0x7f, 0xd0)
WHITE = RGBColor(0xff, 0xff, 0xff)
GRAY = RGBColor(0xcc, 0xcc, 0xcc)
ACCENT = RGBColor(0x00, 0xd2, 0xff)

def add_bg(slide, color=DARK):
    bg = slide.shapes.add_shape(1, 0, 0, prs.slide_width, prs.slide_height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = color
    bg.line.fill.background()
    return bg

def add_text(slide, left, top, width, height, text, size=18, color=WHITE, bold=False, align=PP_ALIGN.LEFT):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(size)
    p.font.color.rgb = color
    p.font.bold = bold
    p.alignment = align
    return tb

# Page 1: 封面
s = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(s)
add_text(s, Inches(1), Inches(2), Inches(11), Inches(1.5),
         "基于安路FPGA的UDP视频实时传输\n与NPU智能分析系统", 40, WHITE, True, PP_ALIGN.CENTER)
add_text(s, Inches(1), Inches(4), Inches(11), Inches(0.6),
         "OV5640采集 | 千兆UDP传输 | DR1M90 NPU推理 | HDMI实时显示", 20, ACCENT, False, PP_ALIGN.CENTER)
add_text(s, Inches(1), Inches(5.5), Inches(11), Inches(0.5),
         "米联客MLK-F3P-CZ02 DR1M90  |  Zynq-7020  |  OV5640", 14, GRAY, False, PP_ALIGN.CENTER)

# Page 2: 系统架构
s = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(s)
add_text(s, Inches(0.5), Inches(0.3), Inches(12), Inches(0.8), "系统架构", 32, WHITE, True)
# 三个模块框
modules = [
    (Inches(0.8), Inches(2), "采集端\nZynq-7020 + OV5640", "摄像头采集\nAXI DMA\nJPEG压缩\nUDP发送"),
    (Inches(4.8), Inches(2), "传输网络\n千兆以太网 UDP", "UDP/IP协议\n1024字节/包\n无连接传输"),
    (Inches(8.8), Inches(2), "处理端\nDR1M90 + NPU", "Linux接收\nHDMI显示\nNPU推理\nINT8量化"),
]
for left, top, title, desc in modules:
    box = s.shapes.add_shape(1, left, top, Inches(3.5), Inches(3.5))
    box.fill.solid()
    box.fill.fore_color.rgb = RGBColor(0x2a, 0x3a, 0x5e)
    box.line.color.rgb = BLUE
    box.line.width = Pt(2)
    add_text(s, left, top+Inches(0.3), Inches(3.5), Inches(1), title, 18, ACCENT, True, PP_ALIGN.CENTER)
    add_text(s, left, top+Inches(1.5), Inches(3.5), Inches(1.8), desc, 14, WHITE, False, PP_ALIGN.CENTER)

# 箭头
for x in [4.3, 8.3]:
    arrow = s.shapes.add_shape(1, Inches(x), Inches(3.5), Inches(0.5), Inches(0.3))
    arrow.fill.solid()
    arrow.fill.fore_color.rgb = ACCENT
    arrow.line.fill.background()

# Page 3: 性能指标
s = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(s)
add_text(s, Inches(0.5), Inches(0.3), Inches(12), Inches(0.8), "性能指标", 32, WHITE, True)
stats = [
    ("640x480", "视频分辨率"),
    ("1 TOPS", "NPU算力(INT8)"),
    ("<100ms", "端到端延迟"),
    ("1080p60", "HDMI显示"),
    ("20+ FPS", "推理帧率"),
    ("千兆网", "传输带宽"),
]
for i, (val, label) in enumerate(stats):
    row, col = i // 3, i % 3
    left = Inches(1 + col * 4)
    top = Inches(2 + row * 2.5)
    add_text(s, left, top, Inches(3.5), Inches(1), val, 44, ACCENT, True, PP_ALIGN.CENTER)
    add_text(s, left, top+Inches(1.2), Inches(3.5), Inches(0.5), label, 16, GRAY, False, PP_ALIGN.CENTER)

# Page 4: 创新点 & 应用
s = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(s)
add_text(s, Inches(0.5), Inches(0.3), Inches(12), Inches(0.8), "创新点与应用", 32, WHITE, True)
innov = "1. 跨平台异构：Zynq采集 + 安路NPU推理\n2. 端侧AI：INT8量化，1 TOPS低功耗推理\n3. 零拷贝：AXI DMA硬件搬运，CPU仅控制\n4. 开放协议：标准UDP，多平台互联"
add_text(s, Inches(0.8), Inches(1.5), Inches(6), Inches(3), innov, 18, WHITE)
apps = "应用领域：\n• 智能安防监控\n• 工业视觉检测\n• 服务机器人视觉\n• 智慧交通边缘计算\n• FPGA+NPU教学平台"
add_text(s, Inches(7.5), Inches(1.5), Inches(5), Inches(3), apps, 18, ACCENT)

out = r'D:\FPGA\Vitis\UDP\作品海报.pptx'
prs.save(out)
print('saved:', out)
