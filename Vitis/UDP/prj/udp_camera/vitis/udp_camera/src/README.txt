OV5640 UDP Video Sender
-----------------------

This application streams OV5640 camera data from the Zynq PS to a PC upper
computer over UDP (1024 bytes per datagram).

   Camera   : OV5640, 640x480, YUV422 (YUYV)
   Board IP : 192.168.1.10 / 255.255.255.0
   PC IP    : 192.168.1.102 (change UDP_DEST_IP_x in udp_perf_server.h)
   UDP port : 5001 (local and destination)

The file udp_perf_server.c keeps the name of the Vitis lwIP template, but it
implements a UDP video sender, not an iperf server.

See Vitis/UDP/prj/udp_camera/README.md for the data path, implementation
flow, key notes and troubleshooting.
