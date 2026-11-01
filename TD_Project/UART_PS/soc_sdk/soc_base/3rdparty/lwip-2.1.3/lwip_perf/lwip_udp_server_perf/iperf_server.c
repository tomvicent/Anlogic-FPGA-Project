/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_hal.h"
#include "al_gbe_ethernetif.h"

#include "lwipopts.h"
#include "lwip/sys.h"
#include "lwip/ip_addr.h"
#include "lwip/err.h"
#include "lwip/udp.h"
#include "lwip/inet.h"

/* used as indices into kLabel[] */
enum {
    KCONV_UNIT,
    KCONV_KILO,
    KCONV_MEGA,
    KCONV_GIGA,
};

/* labels for formats [KMG] */
const char kLabel[] =
{
    ' ',
    'K',
    'M',
    'G'
};

/* used as type of print */
enum measure_t {
    BYTES,
    SPEED
};

/* Report type */
enum report_type {
    /* The Intermediate report */
    INTER_REPORT,
    /* The server side test is done */
    UDP_DONE_SERVER,
    /* Remote side aborted the test */
    UDP_ABORTED_REMOTE
};

struct interim_report {
    u64_t start_time;
    u64_t last_report_time;
    u32_t total_bytes;
    u32_t cnt_datagrams;
    u32_t cnt_dropped_datagrams;
};

struct perf_stats {
    u8_t client_id;
    u64_t start_time;
    u64_t end_time;
    u64_t total_bytes;
    u64_t cnt_datagrams;
    u64_t cnt_dropped_datagrams;
    u32_t cnt_out_of_order_datagrams;
    s32_t expected_datagram_id;
    struct interim_report i_report;
};

/* seconds between periodic bandwidth reports */
#define INTERIM_REPORT_INTERVAL 5

/* server port to listen on/connect to */
#define UDP_CONN_PORT 5001

/* Report interval in ms */
#define REPORT_INTERVAL_TIME (INTERIM_REPORT_INTERVAL * 1000)

extern struct netif gnetif;
static struct udp_pcb *pcb;
static struct perf_stats server;

void print_iperf_info(void)
{
    printf("UDP server listening on port %d\r\n",
            UDP_CONN_PORT);
    printf("On Host: Run $iperf -c %s -i %d -t 300 -u -b <bandwidth>\r\n",
            inet_ntoa(gnetif.ip_addr),
            INTERIM_REPORT_INTERVAL);

}

static void print_udp_conn_stats(void)
{
    printf("[%3d] local %s port %d connected with ",
            server.client_id, inet_ntoa(gnetif.ip_addr),
            UDP_CONN_PORT);
    printf("%s port %d\r\n", inet_ntoa(pcb->remote_ip),
            pcb->remote_port);
    printf("[ ID] Interval\t     Transfer     Bandwidth\t");
    printf("    Lost/Total Datagrams\r\n");
}

static void stats_buffer(char* outString,
        double data, enum measure_t type)
{
    int conv = KCONV_UNIT;
    const char *format;
    double unit = 1024.0;

    if (type == SPEED)
        unit = 1000.0;

    while (data >= unit && conv <= KCONV_GIGA) {
        data /= unit;
        conv++;
    }

    /* Fit data in 4 places */
    if (data < 9.995) { /* 9.995 rounded to 10.0 */
        format = "%4.2f %c"; /* #.## */
    } else if (data < 99.95) { /* 99.95 rounded to 100 */
        format = "%4.1f %c"; /* ##.# */
    } else {
        format = "%4.0f %c"; /* #### */
    }
    sprintf(outString, format, data, kLabel[conv]);
}

/** The report function of a UDP server session */
static void udp_conn_report(u64_t diff,
        enum report_type report_type)
{
    u64_t total_len, cnt_datagrams, cnt_dropped_datagrams, total_packets;
    u32_t cnt_out_of_order_datagrams;
    double duration, bandwidth = 0;
    char data[16], perf[16], time[64], drop[64];

    if (report_type == INTER_REPORT) {
        total_len = server.i_report.total_bytes;
        cnt_datagrams = server.i_report.cnt_datagrams;
        cnt_dropped_datagrams = server.i_report.cnt_dropped_datagrams;
    } else {
        server.i_report.last_report_time = 0;
        total_len = server.total_bytes;
        cnt_datagrams = server.cnt_datagrams;
        cnt_dropped_datagrams = server.cnt_dropped_datagrams;
        cnt_out_of_order_datagrams = server.cnt_out_of_order_datagrams;
    }

    total_packets = cnt_datagrams + cnt_dropped_datagrams;
    /* Converting duration from milliseconds to secs,
     * and bandwidth to bits/sec .
     */
    duration = diff / 1000.0; /* secs */
    if (duration)
        bandwidth = (total_len / duration) * 8.0;

    stats_buffer(data, total_len, BYTES);
    stats_buffer(perf, bandwidth, SPEED);
    /* On 32-bit platforms, printf is not able to print
     * u64_t values, so converting these values in strings and
     * displaying results
     */
    sprintf(time, "%4.1f-%4.1f sec",
            (double)server.i_report.last_report_time,
            (double)(server.i_report.last_report_time + duration));
    sprintf(drop, "%4llu/%5llu (%.2g%%)", cnt_dropped_datagrams,
            total_packets,
            (100.0 * cnt_dropped_datagrams)/total_packets);
    printf("[%3d] %s  %sBytes  %sbits/sec  %s\r\n", server.client_id,
            time, data, perf, drop);

    if (report_type == INTER_REPORT) {
        server.i_report.last_report_time += duration;
    } else if ((report_type != INTER_REPORT) && cnt_out_of_order_datagrams) {
        printf("[%3d] %s  %u datagrams received out-of-order\r\n",
                server.client_id, time,
                cnt_out_of_order_datagrams);
    }
}

static void reset_stats(void)
{
    server.client_id++;
    /* Save start time */
    server.start_time = sys_now();
    server.end_time = 0; /* ms */
    server.total_bytes = 0;
    server.cnt_datagrams = 0;
    server.cnt_dropped_datagrams = 0;
    server.cnt_out_of_order_datagrams = 0;
    server.expected_datagram_id = 0;

    /* Initialize Interim report parameters */
    server.i_report.start_time = 0;
    server.i_report.total_bytes = 0;
    server.i_report.cnt_datagrams = 0;
    server.i_report.cnt_dropped_datagrams = 0;
    server.i_report.last_report_time = 0;
}

/** Receive data on a udp session */
static void udp_recv_perf_traffic(void *arg, struct udp_pcb *tpcb,
        struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    static u8_t first = 1;
    static u64_t now;
    u32_t drop_datagrams = 0;
    s32_t recv_id;

    recv_id = ntohl(*((int *)(p->payload)));

    //if (first && (recv_id == 0 || recv_id == 1)) {
    if (first) {
        /* First packet should always start with recv id 0.
         * However, If Iperf client is running with parallel
         * thread, then this condition will also avoid
         * multiple print of connection header
         */
        pcb->remote_ip = *addr;
        pcb->remote_port = port;
        reset_stats();
        /* Print connection statistics */
        print_udp_conn_stats();
        first = 0;
    } else if (first) {
        /* Avoid rest of the packets if client
         * connection is already terminated.
         */
        return;
    }

    if (first) {
        pcb->remote_ip = *addr;
        pcb->remote_port = port;
        reset_stats();
        /* Print connection statistics */
        print_udp_conn_stats();
        first = 0;
    }

    if (recv_id < 0) {
        u64_t diff_ms = now - server.start_time;
        /* Send Ack */
        udp_sendto(tpcb, p, addr, port);
        udp_conn_report(diff_ms, UDP_DONE_SERVER);
        printf("UDP test passed Successfully\r\n");
        first = 1;
        pbuf_free(p);
        return;
    }

    /* Update dropped datagrams statistics */
    if (server.expected_datagram_id != recv_id) {
        if (server.expected_datagram_id < recv_id) {
            drop_datagrams =
                recv_id - server.expected_datagram_id;
            server.cnt_dropped_datagrams += drop_datagrams;
            server.expected_datagram_id = recv_id + 1;
        } else if (server.expected_datagram_id > recv_id) {
            server.cnt_out_of_order_datagrams++;
        }
    } else {
        server.expected_datagram_id++;
    }

    server.cnt_datagrams++;

    /* Record total bytes for final report */
    server.total_bytes += p->tot_len;

    if (REPORT_INTERVAL_TIME) {
        now = sys_now();

        server.i_report.cnt_datagrams++;
        server.i_report.cnt_dropped_datagrams += drop_datagrams;

        /* Record total bytes for interim report */
        server.i_report.total_bytes += p->tot_len;
        if (server.i_report.start_time) {
            u64_t diff_ms = now - server.i_report.start_time;

            if (diff_ms >= REPORT_INTERVAL_TIME) {
                udp_conn_report(diff_ms, INTER_REPORT);
                /* Reset Interim report counters */
                server.i_report.start_time = 0;
                server.i_report.total_bytes = 0;
                server.i_report.cnt_datagrams = 0;
                server.i_report.cnt_dropped_datagrams = 0;
            }
        } else {
            /* Save start time for interim report */
            server.i_report.start_time = now;
        }
    }

    pbuf_free(p);
    return;
}

void iperf_init(void)
{
    err_t err;

    /* Create Server PCB */
    pcb = udp_new();
    if (!pcb) {
        printf("UDP server: Error creating PCB. Out of Memory\r\n");
        return;
    }

    err = udp_bind(pcb, IP_ADDR_ANY, UDP_CONN_PORT);
    if (err != ERR_OK) {
        printf("UDP server: Unable to bind to port");
        printf(" %d: err = %d\r\n", UDP_CONN_PORT, err);
        udp_remove(pcb);
        return;
    }

    /* specify callback to use for incoming connections */
    udp_recv(pcb, udp_recv_perf_traffic, NULL);

    return;
}