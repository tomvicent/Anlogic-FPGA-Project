//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2020-2030
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           main.c
// Last modified Date:  2023/08/05 15:59:46
// Last Version:        V1.0
// Descriptions:        PS�����ڴ���OV5640����ͷ��Ƶ����λ����ʾ
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2023/08/02 15:59:52
// Version:             V1.0
// Descriptions:        The original version
//server_netif
//----------------------------------------------------------------------------------------
//****************************************************************************************//
/***************************** Include Files *********************************/
 #include <stdio.h>
 #include <stdlib.h>
 #include <string.h>

 #include "xil_types.h"
 #include "xparameters.h"
 #include "emio_sccb_cfg/emio_sccb_cfg.h"
 #include "axi_gpio_cfg/axi_gpio_cfg.h"
 #include "axi_dma/axi_dma.h"
 #include "ov5640/ov5640_init.h"
 #include "sys_intr/sys_intr.h"

 #include "udp_perf_server.h"
 #include "netif/xadapter.h"
 #include "platform.h"
 #include "platform_config.h"
 #include "xil_printf.h"
 #include "lwip/tcp.h"

 #include "sleep.h"
 #include "lwip/priv/tcp_priv.h"
 #include "lwip/init.h"
 #include "lwip/inet.h"
 #include "xil_cache.h"

 extern volatile int TcpFastTmrFlag;
 extern volatile int TcpSlowTmrFlag;
extern volatile u32 udp_tx_pkt_cnt;
extern volatile u32 udp_tx_drop_cnt;

 #define DEFAULT_IP_ADDRESS  "192.168.1.10"
 #define DEFAULT_IP_MASK     "255.255.255.0"
 #define DEFAULT_GW_ADDRESS  "192.168.1.1"

 void start_application(void);
 void print_app_header(void);
 int lwip_udp_init();
 #define MAX_PKT_LEN     1024      //���Ͱ�����

 //��������
 struct netif *netif;
 extern volatile int rx_done;
 extern u8 *rx_buffer_ptr;
 u32 fifo_count = 0;
 u8 dma_start_flag = 0;            //0������DMA ��1���ر�DMA

 struct netif server_netif;
 static XScuGic Intc;              //GIC


 int main(void)
 {
     u32 status;
     u16 cmos_h_pixel;   //ov5640 DVP ���ˮƽ���ص���
     u16 cmos_v_pixel;   //ov5640 DVP �����ֱ���ص���
     u16 total_h_pixel;  //ov5640 ˮƽ�����ش�С
     u16 total_v_pixel;  //ov5640 ��ֱ�����ش�С

     cmos_h_pixel = 640;
     cmos_v_pixel = 480;
     total_h_pixel = 2844;
     total_v_pixel = 1968;

     emio_init();                         //��ʼ��EMIO

     status = ov5640_init( cmos_h_pixel,  //��ʼ��ov5640
                           cmos_v_pixel,
                          total_h_pixel,
                          total_v_pixel);

     if(status == 0)
         xil_printf("OV5640 detected successful!\r\n");
     else
         xil_printf("OV5640 detected failed!\r\n");

     axi_gpio_init();               // ��ʼAXI-GPIO�ӿ�
     axi_dma_cfg();                 // ����AXI DMA
     Init_Intr_System(&Intc);       // ��ʼDMA�ж�ϵͳ
     Setup_Intr_Exception(&Intc);   // ��������Ӳ�����ж�
     dma_setup_intr_system(&Intc);  // ����DMA�ж�ϵͳ

     lwip_udp_init();               // UDPͨ������

     //���պʹ������ݰ�
     while (1) {

         xemacif_input(netif);

         fifo_count = get_fifo_count(); //PS�˶�ȡFIFO�еĶ����ݼ���

         //FIFO�еĶ����ݼ��������ﵽ���Ͱ����Ⱥ󣬿�ʼ����DMA��FIFO�ж�ȡ1024�����ݴ洢��DDR��
         if((fifo_count >= MAX_PKT_LEN) && (dma_start_flag == 0)){
             axi_dma_start(MAX_PKT_LEN);
             dma_start_flag = 1;
         }
         //DMA����1024��������ɺ����ھͿ��Դ�DDR��ȡ���ݽ��з�����
         if (dma_start_flag == 1 && !rx_done) {
             int _d = axi_dma_done();
             if (_d == 1) rx_done = 1;
             else if (_d == -1) rx_done = 1;
         }
         if(rx_done){
             udp_tx_data(rx_buffer_ptr, UDP_VIDEO_PKT_LEN);

             rx_done = 0;
             dma_start_flag = 0;
         }

         /* debug: print pipeline state every ~1s */
         {
             static u32 _loop = 0, _last = 0;
             _loop++;
             if (_loop - _last >= 30000000U) {
                 _last = _loop;
                 xil_printf("dbg: fifo=%d rx_done=%d dma=%d tx=%u drop=%u stat=0x%x\r\n",
                            fifo_count, rx_done, dma_start_flag,
                            udp_tx_pkt_cnt, udp_tx_drop_cnt, axi_dma_raw_status());
             }
         }
     }
     return 0;
 }

 static void print_ip(char *msg, ip_addr_t *ip)
 {
     print(msg);
     xil_printf("%d.%d.%d.%d\r\n", ip4_addr1(ip), ip4_addr2(ip),
             ip4_addr3(ip), ip4_addr4(ip));
 }

 static void print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
 {
     print_ip("Board IP:       ", ip);
     print_ip("Netmask :       ", mask);
     print_ip("Gateway :       ", gw);
 }

 //���þ�̬IP��ַ
 static void assign_default_ip(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
 {
     int err;

     xil_printf("Configuring default IP %s \r\n", DEFAULT_IP_ADDRESS);

     err = inet_aton(DEFAULT_IP_ADDRESS, ip);
     if (!err)
         xil_printf("Invalid default IP address: %d\r\n", err);

     err = inet_aton(DEFAULT_IP_MASK, mask);
     if (!err)
         xil_printf("Invalid default IP MASK: %d\r\n", err);

     err = inet_aton(DEFAULT_GW_ADDRESS, gw);
     if (!err)
         xil_printf("Invalid default gateway address: %d\r\n", err);
 }

 int lwip_udp_init()
 {
     /*�����캽�߿������MAC��ַ */
     unsigned char mac_ethernet_address[] = {
         0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };

     netif = &server_netif;

     xil_printf("\r\n\r\n");
     xil_printf("-----lwIP RAW Mode UDP Server Application-----\r\n");

     /* ��ʼ��lwIP*/
     lwip_init();

     /* ������ӿ����ӵ�netif_list������������ΪĬ������ӿ� ���������δ�ҵ��ض�·�ɵ��������ݰ��� */
     if (!xemac_add(netif, NULL, NULL, NULL, mac_ethernet_address,
                 PLATFORM_EMAC_BASEADDR)) {
         xil_printf("Error adding N/W interface\r\n");
         return -1;
     }
     netif_set_default(netif);

     /* ָ�������Ƿ�������*/
     netif_set_up(netif);

     //���þ�̬IP��ַ
     assign_default_ip(&(netif->ip_addr), &(netif->netmask), &(netif->gw));

     //��ӡIP����
     print_ip_settings(&(netif->ip_addr), &(netif->netmask), &(netif->gw));

     xil_printf("\r\n");

     /* ��ӡӦ�ó������ */
     print_app_header();

     /* ����Ӧ�ó���*/
     start_application();
     xil_printf("\r\n");
     return 0;
 }


