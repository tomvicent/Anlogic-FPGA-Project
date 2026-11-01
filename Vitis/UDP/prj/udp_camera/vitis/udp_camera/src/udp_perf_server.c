/*
 * udp_perf_server.c
 *
 * OV5640 video over UDP - lwIP RAW (NO_SYS) sender.
 *
 * Data path:
 *   OV5640 -> ov5640_data_8b -> v_vid_in_axi4s -> axis_data_fifo
 *          -> AXI DMA (S2MM, simple mode) -> DDR buffer (rx_buffer_ptr)
 *          -> udp_tx_data() -> lwIP -> GEM/EMAC -> PC upper computer
 *
 * The file keeps the name of the Xilinx "udp_perf_server" template because
 * main.c includes it, but it no longer implements the iperf server.
 */

#include "udp_perf_server.h"
#include "xil_cache.h"

extern struct netif server_netif;

static struct udp_pcb *pcb = NULL;

/* Volatile so the counters can be watched in the Vitis debugger. */
volatile u32 udp_tx_pkt_cnt  = 0;   /* datagrams accepted by udp_send()  */
volatile u32 udp_tx_drop_cnt = 0;   /* pbuf allocation / send failures   */

/*
 * Print the application banner. Called by lwip_udp_init() after the netif
 * has been configured and before start_application().
 */
void print_app_header(void)
{
    xil_printf("\r\n--- OV5640 camera -> AXI DMA -> lwIP UDP -> PC ---\r\n");
    xil_printf("Board  IP : %d.%d.%d.%d  (local port %d)\r\n",
               ip4_addr1(&server_netif.ip_addr), ip4_addr2(&server_netif.ip_addr),
               ip4_addr3(&server_netif.ip_addr), ip4_addr4(&server_netif.ip_addr),
               UDP_LOCAL_PORT);
    xil_printf("Target IP : %d.%d.%d.%d  (port %d), %d bytes/datagram\r\n",
               UDP_DEST_IP_0, UDP_DEST_IP_1, UDP_DEST_IP_2, UDP_DEST_IP_3,
               UDP_DEST_PORT, UDP_VIDEO_PKT_LEN);
}

/*
 * Send one chunk of camera data.
 *
 * buffer_ptr is the DDR buffer written by the AXI DMA, so the CPU data cache
 * may still hold stale lines from the previous chunk. Invalidate them before
 * reading, otherwise pbuf_take() can send old pixels.
 *
 * One PBUF_POOL buffer is PBUF_POOL_BUFSIZE (1700) bytes, so a 1024-byte
 * payload always fits into a single pbuf.
 */
void udp_tx_data(u8 *buffer_ptr, unsigned int len)
{
    struct pbuf *ptr;
    err_t err;

    if ((pcb == NULL) || (buffer_ptr == NULL) || (len == 0U)) {
        return;
    }

    /* Never exceed a single Ethernet frame. */
    if (len > 1472U) {
        len = 1472U;
    }

    /* DMA (S2MM) wrote DDR behind the CPU's back: drop stale cache lines. */
    Xil_DCacheInvalidateRange((UINTPTR)buffer_ptr, len);

    ptr = pbuf_alloc(PBUF_TRANSPORT, (u16_t)len, PBUF_POOL);
    if (ptr == NULL) {
        udp_tx_drop_cnt++;
        return;
    }

    if (pbuf_take(ptr, buffer_ptr, (u16_t)len) != ERR_OK) {
        pbuf_free(ptr);
        udp_tx_drop_cnt++;
        return;
    }

    err = udp_send(pcb, ptr);

    /* The Xilinx GEM driver takes its own reference on the pbuf; releasing
     * ours here is safe (the last reference is freed on TX completion). */
    pbuf_free(ptr);

    if (err == ERR_OK) {
        udp_tx_pkt_cnt++;
    } else {
        udp_tx_drop_cnt++;
    }
}

/*
 * Create the UDP PCB, bind it to the local port and connect it to the PC.
 * Because the PCB is connected, udp_send() does not need a destination
 * address on every packet.
 */
void start_application(void)
{
    err_t err;
    ip_addr_t dest_ip;

    IP4_ADDR(&dest_ip, UDP_DEST_IP_0, UDP_DEST_IP_1,
             UDP_DEST_IP_2, UDP_DEST_IP_3);

    pcb = udp_new();
    if (pcb == NULL) {
        xil_printf("UDP: Error creating PCB. Out of Memory\r\n");
        return;
    }

    err = udp_bind(pcb, IP_ADDR_ANY, UDP_LOCAL_PORT);
    if (err != ERR_OK) {
        xil_printf("UDP: Unable to bind to port %d; err %d\r\n",
                   UDP_LOCAL_PORT, err);
        udp_remove(pcb);
        pcb = NULL;
        return;
    }

    err = udp_connect(pcb, &dest_ip, UDP_DEST_PORT);
    if (err != ERR_OK) {
        xil_printf("UDP: Unable to connect to %d.%d.%d.%d:%d; err %d\r\n",
                   UDP_DEST_IP_0, UDP_DEST_IP_1, UDP_DEST_IP_2, UDP_DEST_IP_3,
                   UDP_DEST_PORT, err);
        udp_remove(pcb);
        pcb = NULL;
        return;
    }

    xil_printf("UDP video stream started: port %d -> %d.%d.%d.%d:%d\r\n",
               UDP_LOCAL_PORT,
               UDP_DEST_IP_0, UDP_DEST_IP_1, UDP_DEST_IP_2, UDP_DEST_IP_3,
               UDP_DEST_PORT);
}
