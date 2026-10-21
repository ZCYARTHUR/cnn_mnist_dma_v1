#include <stdio.h>
#include "cnn_reference.h"
#include "cnn_test_data.h"
int main(void) {
 int32_t logits[10];
 for(unsigned f=0;f<CNN_TEST_FRAMES;f++) {
  if(cnn_reference(cnn_model_words,cnn_image_words+197*f,logits))return 1;
  for(unsigned c=0;c<10;c++)if((uint32_t)logits[c]!=cnn_expected[f*10+c]) {
   fprintf(stderr,"Mismatch frame=%u class=%u\n",f,c);return 2;
  }
 }
 printf("PASS: C reference matches Python, %u frames\n",CNN_TEST_FRAMES);
 return 0;
}
