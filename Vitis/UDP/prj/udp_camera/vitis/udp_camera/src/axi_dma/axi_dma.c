//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           axi_dma.c
// Last modified Date:  2023/08/9 10:59:46
// Last Version:        V1.0
// Descriptions:        Axi dma�����������ж�ģʽ�½������ݰ�
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/06/30 15:59:52
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

/***************************** Include Files *********************************/
#include "axi_dma.h"

/************************** Constant Definitions *****************************/
#define DMA_DEV_ID             XPAR_AXIDMA_0_DEVICE_ID
#define RX_INTR_ID             XPAR_FABRIC_AXIDMA_0_VEC_ID
#define INTC_DEVICE_ID         XPAR_SCUGIC_SINGLE_DEVICE_ID
#define DDR_BASE_ADDR          XPAR_PS7_DDR_0_S_AXI_BASEADDR   //0x00100000
/*
 * AXI DMA destination buffer.
 *
 * Keep this address ABOVE the application image. With the default lwIP
 * settings (PBUF_POOL_SIZE = 16384, PBUF_POOL_BUFSIZE = 1700) the pbuf
 * pool is a ~28MB static array that the linker places at about
 * 0x00280000..0x01E90000, so the vendor demo's 0x01400000 actually falls
 * inside the pool. 0x08000000 (128MB) is above .bss and still inside DDR.
 */
#define RX_BUFFER_BASE         0x08000000U                     //128MB
#define RESET_TIMEOUT_COUNTER  10000    //��λʱ��

/************************** Variable Definitions *****************************/

static XAxiDma axidma;     //XAxiDmaʵ��
volatile int rx_done=0;    //������ɱ�־
volatile int error;        //���������־
u8 *rx_buffer_ptr;

/************************** Function Definitions *****************************/

int axi_dma_cfg(void)
{

    int status;

    XAxiDma_Config *config;

    rx_buffer_ptr = (u8 *) RX_BUFFER_BASE;

    xil_printf("\r\n--- Entering axi_dma_cfg --- \r\n");

    config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!config) {
        xil_printf("No config found for %d\r\n", DMA_DEV_ID);
        return XST_FAILURE;
    }

    //��ʼ��DMA����
    status = XAxiDma_CfgInitialize(&axidma, config);
    if (status != XST_SUCCESS) {
        xil_printf("Initialization failed %d\r\n", status);
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&axidma)) {
        xil_printf("Device configured as SG mode \r\n");
        return XST_FAILURE;
    }

    xil_printf("AXI DMA CFG Success\r\n");
    return XST_SUCCESS;

}

//����AXI DMA
int axi_dma_start(u32 pkt_len)
{
    int status;
    //��ʼ����־�ź�
    error   = 0;

    status = XAxiDma_SimpleTransfer(&axidma, (UINTPTR) rx_buffer_ptr,
    		pkt_len, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
    	xil_printf("AXI DMA Start FAILURE\r\n");
    	return XST_FAILURE;
    }
   // while(!rx_done && !error);//�ȴ�DMA�����ݴ�FIFO���˵�DDR
    Xil_DCacheFlushRange((UINTPTR) rx_buffer_ptr, pkt_len); //ˢ��Data Cache
    return XST_SUCCESS;
}

//DMA RX�жϴ�������
u32 axi_dma_raw_status(void)
{
    return XAxiDma_IntrGetIrq(&axidma, XAXIDMA_DEVICE_TO_DMA);
}

int axi_dma_done(void)
{
    u32 irq;
    irq = XAxiDma_IntrGetIrq(&axidma, XAXIDMA_DEVICE_TO_DMA);
    if (irq & XAXIDMA_IRQ_ERROR_MASK) {
        XAxiDma_IntrAckIrq(&axidma, irq, XAXIDMA_DEVICE_TO_DMA);
        XAxiDma_Reset(&axidma);
        int to = 10000;
        while (to--) { if (XAxiDma_ResetIsDone(&axidma)) break; }
        XAxiDma_IntrEnable(&axidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
        error = 1;
        return -1;
    }
    if (irq & XAXIDMA_IRQ_IOC_MASK) {
        XAxiDma_IntrAckIrq(&axidma, irq, XAXIDMA_DEVICE_TO_DMA);
        return 1;
    }
    return 0;
}

void rx_intr_handler(void *callback)
{
    u32 irq_status;
    int timeout;
    XAxiDma *axidma_inst = (XAxiDma *) callback;

    irq_status = XAxiDma_IntrGetIrq(axidma_inst, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(axidma_inst, irq_status, XAXIDMA_DEVICE_TO_DMA);

    //Rx����               0x00004000 /**< Error interrupt */
    if ((irq_status & XAXIDMA_IRQ_ERROR_MASK)) {
        error = 1;
        xil_printf("XAxiDma error");
        XAxiDma_Reset(axidma_inst);
        timeout = RESET_TIMEOUT_COUNTER;
        while (timeout) {
            if (XAxiDma_ResetIsDone(axidma_inst))
                break;
            timeout -= 1;
        }
        return;
    }
    //Rx���     0x00001000 /**< Completion intr */
    if ((irq_status & XAXIDMA_IRQ_IOC_MASK))
        rx_done = 1;

    irq_status = XAxiDma_IntrGetIrq(axidma_inst, XAXIDMA_DEVICE_TO_DMA);
}

//����DMA�ж�ϵͳ
//  @param   int_ins_ptr��ָ��XScuGicʵ����ָ��
//  @param   AxiDmaPtr��ָ��DMA����ʵ����ָ��
//  @param   rx_intr_id��RXͨ���ж�ID
//  @return���ɹ�����XST_SUCCESS�����򷵻�XST_FAILURE
int dma_setup_intr_system(XScuGic * int_ins_ptr)
{
    int status;
    //�������ȼ��ʹ�������
    XScuGic_SetPriorityTriggerType(int_ins_ptr, RX_INTR_ID, 0xA0, 0x3);

    //Ϊ�ж������жϴ�������
    status = XScuGic_Connect(int_ins_ptr, RX_INTR_ID,
            (Xil_InterruptHandler) rx_intr_handler, &axidma);
    if (status != XST_SUCCESS) {
        return status;
    }
    XScuGic_Enable(int_ins_ptr, RX_INTR_ID);

    //ʹ��DMA�ж�
    XAxiDma_IntrEnable(&axidma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}






