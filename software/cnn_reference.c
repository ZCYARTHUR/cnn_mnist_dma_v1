#include "cnn_reference.h"
#include <limits.h>
static int32_t byte_signed(const uint32_t *p,unsigned a) {
 unsigned v=(p[a/4]>>(8*(a%4)))&255U;
 return v<128 ? (int32_t)v : (int32_t)v-256;
}
static int32_t word_signed(uint32_t w) {
 return w<=INT32_MAX ? (int32_t)w : (int32_t)((int64_t)w-4294967296LL);
}
static int32_t quantize(int32_t x,unsigned shift) {
 if(x<=0)return 0;
 int64_t r=x;
 if(shift)r=(r+(1LL<<(shift-1)))>>shift;
 return r>127 ? 127 : (int32_t)r;
}
int cnn_reference(const uint32_t *model,const uint32_t *image,int32_t logits[10]) {
 if(model[0]!=0x434e4e01U || image[0]!=0x434e4e02U || model[1]>24)return -1;
 int8_t features[676];
 const uint32_t *weights=model+2,*bias=model+1701,*pixels=image+1;
 for(unsigned c=0;c<4;c++)for(unsigned y=0;y<13;y++)for(unsigned x=0;x<13;x++) {
  int32_t best=0;
  for(unsigned dy=0;dy<2;dy++)for(unsigned dx=0;dx<2;dx++) {
   int64_t acc=word_signed(bias[c]);
   for(unsigned ky=0;ky<3;ky++)for(unsigned kx=0;kx<3;kx++) {
    int32_t pixel=byte_signed(pixels,(2*y+dy+ky)*28+2*x+dx+kx);
    if(pixel<0)return -2;
    acc+=pixel*byte_signed(weights,c*9+ky*3+kx);
   }
   if(acc>INT32_MAX || acc<INT32_MIN)return -3;
   int32_t q=quantize((int32_t)acc,model[1]);
   if(q>best)best=q;
  }
  features[c*169+y*13+x]=(int8_t)best;
 }
 for(unsigned c=0;c<10;c++) {
  int64_t acc=word_signed(bias[4+c]);
  for(unsigned i=0;i<676;i++)acc+=(int32_t)features[i]*byte_signed(weights,36+c*676+i);
  if(acc>INT32_MAX || acc<INT32_MIN)return -3;
  logits[c]=(int32_t)acc;
 }
 return 0;
}
int cnn_argmax(const int32_t logits[10]) {
 int best=0;for(int i=1;i<10;i++)if(logits[i]>logits[best])best=i;return best;
}
