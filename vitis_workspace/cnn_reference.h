#ifndef CNN_REFERENCE_H
#define CNN_REFERENCE_H
#include <stdint.h>
enum { CNN_MODEL_WORDS=1715, CNN_IMAGE_WORDS=197, CNN_RESULT_WORDS=12 };
/* Host-endian uint32 words containing a little-endian byte stream. */
int cnn_reference(const uint32_t *model,const uint32_t *image,int32_t logits[10]);
int cnn_argmax(const int32_t logits[10]);
#endif
