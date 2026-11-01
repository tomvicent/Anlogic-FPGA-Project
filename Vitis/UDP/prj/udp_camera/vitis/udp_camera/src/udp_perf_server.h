/*
 * udp_perf_server.h
 *
 * OV5640 video over UDP - lwIP RAW (NO_SYS) sender.
 *
 * The file keeps the name of the Xilinx "udp_perf_server" template because
 * main.c includes it, but it no longer implements the iperf server.
 */

#ifndef __UDP_PERF_SERVER_H_
#define __UDP_PERF_SERVER_H_

#include "xil_types.h"
#include "lwip/ip_addr.h"
#include "lwip/err.h"
#include "lwip/udp.h"
#include "lwip/inet.h"
#include "xil_printf.h"

/* -------------------------------------------------------------------------
 * Network configuration
 *
 * The PC (upper computer) must use this static IP and be connected to the
 * same subnet as the board. The board IP is configured in main.c:
 *     DEFAULT_IP_ADDRESS  "192.168.1.10"
 *     DEFAULT_IP_MASK     "255.255.255.0"
 * ------------------------------------------------------------------------- */
#ifndef UDP_DEST_IP_0
#define UDP_DEST_IP_0   192     /* PC (upper computer) IP address       */
#define UDP_DEST_IP_1   168
#define UDP_DEST_IP_2   1
#define UDP_DEST_IP_3   102
#endif

#define UDP_DEST_PORT       5002    /* port the PC listens on            */
#define UDP_LOCAL_PORT      5002    /* local port bound by the UDP PCB   */

/* Camera bytes carried by one UDP datagram. The vendor upper computer
 * expects 1024-byte payloads. Keep it <= 1472 (Ethernet MTU limit). */
#ifndef UDP_VIDEO_PKT_LEN
#define UDP_VIDEO_PKT_LEN   1024
#endif

/* Application entry points (called from main.c) */
void print_app_header(void);
void start_application(void);

/* Send one chunk of camera data.
 *   buffer_ptr : CPU address of the buffer filled by the AXI DMA
 *   len        : number of bytes to send (UDP_VIDEO_PKT_LEN)
 *
 * Non-blocking; the datagram is silently dropped if no pbuf is available. */
void udp_tx_data(u8 *buffer_ptr, unsigned int len);

#endif /* __UDP_PERF_SERVER_H_ */
