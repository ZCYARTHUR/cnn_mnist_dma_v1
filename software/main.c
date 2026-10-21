/* Vitis Standalone A53; simple AXI DMA, polling, physically addressed DDR.
 * Copy cnn_reference.[ch], board_config.h and vectors/cnn_test_data.h to src.
 * Model remains in PL. Benchmark covers cache ops, two DMA submissions and
 * polling, but excludes model load, CPU reference and UART printing.
 */
#include <stdio.h>
#include <string.h>
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xtime_l.h"
#include "board_config.h"
#include "cnn_reference.h"
#include "cnn_test_data.h"

#define ALIGNED __attribute__((aligned(64)))
static XAxiDma dma;
/* Entire cache lines are reserved so RX invalidation never discards neighbors. */
static uint32_t model_buf[1728] ALIGNED;
static uint32_t image_buf[208] ALIGNED;
static uint32_t result_buf[16] ALIGNED;
static uint32_t batch_images[CNN_TEST_FRAMES][208] ALIGNED;
static uint32_t batch_results[CNN_TEST_FRAMES][16] ALIGNED;
static int32_t cpu_logits[10];
static volatile int32_t checksum;
static XTime now(void){XTime t;XTime_GetTime(&t);return t;}
static double elapsed_us(XTime ticks){return (double)ticks*1e6/(double)COUNTS_PER_SECOND;}
static int dma_error(void) {
 u32 tx=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_TX_OFFSET+XAXIDMA_SR_OFFSET);
 u32 rx=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_RX_OFFSET+XAXIDMA_SR_OFFSET);
 if((tx|rx)&XAXIDMA_ERR_ALL_MASK) {
  printf("DMA error: MM2S=%08lx S2MM=%08lx\n",(unsigned long)tx,(unsigned long)rx);return 1;
 }
 return 0;
}
static int wait_dma(int receive) {
 XTime start=now();
 while(XAxiDma_Busy(&dma,XAXIDMA_DMA_TO_DEVICE) ||
       (receive && XAxiDma_Busy(&dma,XAXIDMA_DEVICE_TO_DMA))) {
  if(dma_error())return -1;
  if(now()-start>(XTime)COUNTS_PER_SECOND*CNN_TIMEOUT_SECONDS) {
   printf("DMA timeout: CNN status=%08lx\n",(unsigned long)Xil_In32(CNN_CTRL_BASE+4));return -1;
  }
 }
 return dma_error() ? -1 : 0;
}
static int initialize(void) {
 if((UINTPTR)model_buf>UINT32_MAX-sizeof(model_buf) ||
    (UINTPTR)image_buf>UINT32_MAX-sizeof(image_buf) ||
    (UINTPTR)result_buf>UINT32_MAX-sizeof(result_buf)) {
  printf("Use low DDR below 4 GiB in lscript.ld for this 32-bit DMA configuration\n");return -1;
 }
 XAxiDma_Config *cfg;
#ifdef SDT
 cfg=XAxiDma_LookupConfig((UINTPTR)CNN_DMA_BASE);
#else
 cfg=XAxiDma_LookupConfig(CNN_DMA_DEVICE_ID);
#endif
 if(!cfg || XAxiDma_CfgInitialize(&dma,cfg)!=XST_SUCCESS || XAxiDma_HasSg(&dma)) {
  printf("DMA init failed: need simple mode and matching BSP\n");return -1;
 }
 XAxiDma_Reset(&dma);
 XTime t=now();
 while(!XAxiDma_ResetIsDone(&dma))if(now()-t>(XTime)COUNTS_PER_SECOND*CNN_TIMEOUT_SECONDS)return -1;
 XAxiDma_IntrDisable(&dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
 XAxiDma_IntrDisable(&dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
 if(Xil_In32(CNN_CTRL_BASE)!=0x434e4e31U) {
  printf("Wrong CNN ID: program NEW bitstream and verify address\n");return -1;
 }
 Xil_Out32(CNN_CTRL_BASE,1); /* Reset queues/model_valid/performance counters. */
 memcpy(model_buf,cnn_model_words,CNN_MODEL_WORDS*4);
 Xil_DCacheFlushRange((INTPTR)model_buf,sizeof(model_buf));
 if(XAxiDma_SimpleTransfer(&dma,(UINTPTR)model_buf,CNN_MODEL_WORDS*4,XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS || wait_dma(0))return -1;
 t=now();
 while(!(Xil_In32(CNN_CTRL_BASE+4)&1U))
  if(now()-t>(XTime)COUNTS_PER_SECOND*CNN_TIMEOUT_SECONDS)return -1;
 return 0;
}
static int run_image(void) {
 /* Buffers are copied BEFORE timing; cache maintenance remains included. */
 Xil_DCacheFlushRange((INTPTR)image_buf,sizeof(image_buf));
 Xil_DCacheFlushRange((INTPTR)result_buf,sizeof(result_buf));
 /* Arm S2MM first; otherwise output can stall waiting for a receive buffer. */
 if(XAxiDma_SimpleTransfer(&dma,(UINTPTR)result_buf,CNN_RESULT_WORDS*4,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)return -1;
 if(XAxiDma_SimpleTransfer(&dma,(UINTPTR)image_buf,CNN_IMAGE_WORDS*4,XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)return -1;
 if(wait_dma(1))return -1;
 Xil_DCacheInvalidateRange((INTPTR)result_buf,sizeof(result_buf));
 if(result_buf[0]!=0x434e4e10U || (Xil_In32(CNN_CTRL_BASE+4)&4U))return -1;
 return 0;
}
/* Simple DMA has one outstanding transfer per channel. Rearm each channel
 * independently so loading image N+1 can overlap PL computation of image N.
 * Every image still has its own TLAST. This is not scatter-gather DMA.
 */
static int run_batch(void) {
 unsigned submitted=0,received=0;
 Xil_DCacheFlushRange((INTPTR)batch_images,sizeof(batch_images));
 Xil_DCacheFlushRange((INTPTR)batch_results,sizeof(batch_results));
 if(XAxiDma_SimpleTransfer(&dma,(UINTPTR)batch_results[0],CNN_RESULT_WORDS*4,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)return -1;
 XTime start=now();
 while(received<CNN_TEST_FRAMES) {
  if(dma_error() || now()-start>(XTime)COUNTS_PER_SECOND*CNN_TIMEOUT_SECONDS)return -1;
  if(!XAxiDma_Busy(&dma,XAXIDMA_DEVICE_TO_DMA)) {
   received++;
   if(received<CNN_TEST_FRAMES && XAxiDma_SimpleTransfer(&dma,(UINTPTR)batch_results[received],
       CNN_RESULT_WORDS*4,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)return -1;
  }
  if(submitted<CNN_TEST_FRAMES && !XAxiDma_Busy(&dma,XAXIDMA_DMA_TO_DEVICE)) {
   if(XAxiDma_SimpleTransfer(&dma,(UINTPTR)batch_images[submitted],CNN_IMAGE_WORDS*4,
       XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)return -1;
   submitted++;
  }
 }
 if(wait_dma(0))return -1;
 Xil_DCacheInvalidateRange((INTPTR)batch_results,sizeof(batch_results));
 return (Xil_In32(CNN_CTRL_BASE+4)&4U)?-1:0;
}
int main(void) {
 printf("\nDMA INT8 CNN: Conv4/ReLU/Pool/FC10\n");
 /* This BSP is A53 standalone; startup has initialized DDR and the UART. */
 if(initialize())return 1;
 printf("MAC lanes=%lu; test frames=%u\n",(unsigned long)Xil_In32(CNN_CTRL_BASE+28),CNN_TEST_FRAMES);
 XTime cpu_ticks=0,hw_ticks=0;uint64_t core_cycles=0;unsigned errors=0,correct=0,labeled=0;
 /* Warm up CPU caches and DMA once, separately from timed measurements. */
 memcpy(image_buf,cnn_image_words,CNN_IMAGE_WORDS*4);
 if(cnn_reference(cnn_model_words,image_buf,cpu_logits) || run_image())return 2;
 for(unsigned rep=0;rep<CNN_BENCH_REPEATS;rep++)for(unsigned f=0;f<CNN_TEST_FRAMES;f++) {
  memcpy(image_buf,cnn_image_words+f*CNN_IMAGE_WORDS,CNN_IMAGE_WORDS*4);
  XTime t=now();
  int rc=cnn_reference(cnn_model_words,image_buf,cpu_logits);
  cpu_ticks+=now()-t;checksum=cpu_logits[0];
  if(rc)return 3;
  t=now();rc=run_image();hw_ticks+=now()-t;
  if(rc)return 4;
  core_cycles+=result_buf[1];
  for(unsigned c=0;c<10;c++)
   if(result_buf[2+c]!=(uint32_t)cpu_logits[c] || result_buf[2+c]!=cnn_expected[f*10+c])errors++;
  if(rep==0) {
   int pred=cnn_argmax(cpu_logits);
   if(cnn_labels[f]<10){labeled++;correct+=(pred==cnn_labels[f]);}
   printf("frame=%u predicted=%d label=%u core_cycles=%lu\n",f,pred,cnn_labels[f],(unsigned long)result_buf[1]);
  }
 }
 double runs=(double)CNN_BENCH_REPEATS*CNN_TEST_FRAMES;
 double cpu_us=elapsed_us(cpu_ticks)/runs,hw_us=elapsed_us(hw_ticks)/runs;
 printf("%s: logit mismatches=%u\n",errors?"FAIL":"PASS",errors);
 if(labeled)printf("Subset accuracy=%u/%u (not full MNIST test accuracy)\n",correct,labeled);
 else printf("Synthetic vectors: no classification accuracy claim\n");
 printf("CPU reference mean=%.3f us; DMA+PL mean=%.3f us\n",cpu_us,hw_us);
 printf("CPU-reference / DMA+PL speedup=%.3fx; sequential service rate=%.2f images/s\n",cpu_us/hw_us,1e6/hw_us);
 printf("PL compute mean=%.3f us at configured clock %u Hz\n",(double)core_cycles/runs*1e6/CNN_PL_CLOCK_HZ,CNN_PL_CLOCK_HZ);
 printf("CPU baseline is portable scalar C with checks, not an optimized NEON library.\n");
 if((UINTPTR)batch_images>UINT32_MAX-sizeof(batch_images) ||
    (UINTPTR)batch_results>UINT32_MAX-sizeof(batch_results))return 6;
 for(unsigned f=0;f<CNN_TEST_FRAMES;f++)
  memcpy(batch_images[f],cnn_image_words+f*CNN_IMAGE_WORDS,CNN_IMAGE_WORDS*4);
 XTime batch_ticks=0;
 for(unsigned rep=0;rep<CNN_BENCH_REPEATS;rep++) {
  XTime t=now();int rc=run_batch();batch_ticks+=now()-t;
  if(rc){printf("Batch DMA failed\n");return 7;}
  for(unsigned f=0;f<CNN_TEST_FRAMES;f++) {
   if(batch_results[f][0]!=0x434e4e10U)errors++;
   for(unsigned c=0;c<10;c++)if(batch_results[f][c+2]!=cnn_expected[f*10+c])errors++;
  }
 }
 double batch_us=elapsed_us(batch_ticks)/runs;
 printf("Pipelined batch: %.3f us/image amortized, %.2f images/s, serial/batch=%.3fx\n",
        batch_us,1e6/batch_us,hw_us/batch_us);
 printf("CPU-reference / batch amortized time=%.3fx\n",cpu_us/batch_us);
 printf("FINAL %s: total mismatches=%u\n",errors?"FAIL":"PASS",errors);
 return errors?5:0;
}
