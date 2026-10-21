#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
#include "xparameters.h"
/* Match Vivado Address Editor after importing the NEW XSA. */
#define CNN_CTRL_BASE 0x80000000U
#define CNN_DMA_BASE  0x80010000U
/* For a legacy (non-SDT) BSP only; check xparameters.h. */
#ifndef SDT
#define CNN_DMA_DEVICE_ID XPAR_AXIDMA_0_DEVICE_ID
#endif
/* Set to the implemented PL clock, not the requested clock if changed. */
#define CNN_PL_CLOCK_HZ 99999001U
#define CNN_BENCH_REPEATS 10U
#define CNN_TIMEOUT_SECONDS 2U
#endif
