"""Independent, bit-exact integer reference and DMA packet serializer."""
from pathlib import Path
import numpy as np

MODEL_MAGIC = 0x434E4E01
IMAGE_MAGIC = 0x434E4E02
RESULT_MAGIC = 0x434E4E10
MODEL_WORDS = 1715
IMAGE_WORDS = 197
RESULT_WORDS = 12

def requantize_relu(x, shift):
    x = np.asarray(x, dtype=np.int64)
    assert 0 <= shift <= 24
    x = np.maximum(x, 0)
    if shift:
        x = (x + (1 << (shift - 1))) >> shift
    return np.clip(x, 0, 127).astype(np.int8)

def infer(images, cw, cb, fw, fb, shift):
    """Images are signed INT8 values [0,127], NCHW (N,28,28 accepted)."""
    x = np.asarray(images, dtype=np.int64).reshape(-1, 28, 28)
    assert x.min() >= 0 and x.max() <= 127
    windows = np.lib.stride_tricks.sliding_window_view(x, (3, 3), axis=(1, 2))
    conv = np.einsum('nyxij,cij->ncyx', windows, np.asarray(cw, np.int64).reshape(4,3,3))
    conv += np.asarray(cb, np.int64)[None, :, None, None]
    if np.abs(conv).max() >= 2**31:
        raise OverflowError('Conv accumulator overflow')
    act = requantize_relu(conv, shift)
    pooled = act.reshape(-1,4,13,2,13,2).max(axis=(3,5))
    logits = pooled.reshape(-1,676).astype(np.int64) @ np.asarray(fw,np.int64).reshape(10,676).T
    logits += np.asarray(fb,np.int64)
    if np.abs(logits).max() >= 2**31:
        raise OverflowError('FC accumulator overflow')
    return logits.astype(np.int32)

def pack_bytes(values):
    raw=np.asarray(values,dtype=np.int8).reshape(-1).tobytes()
    assert len(raw)%4==0
    return np.frombuffer(raw,dtype='<u4').copy()

def model_packet(cw,cb,fw,fb,shift):
    assert 0<=int(shift)<=24
    weights=np.concatenate([np.asarray(cw).reshape(-1),np.asarray(fw).reshape(-1)])
    biases=np.concatenate([cb,fb]).astype('<i4').view('<u4')
    p=np.concatenate([np.array([MODEL_MAGIC,shift],dtype='<u4'),pack_bytes(weights),biases])
    assert len(p)==MODEL_WORDS
    return p

def image_packet(image):
    x=np.asarray(image,dtype=np.int8).reshape(784)
    assert x.min()>=0
    return np.concatenate([np.array([IMAGE_MAGIC],dtype='<u4'),pack_bytes(x)])

def export(out, images, labels, cw, cb, fw, fb, shift, metadata=None):
    import json
    out=Path(out); out.mkdir(parents=True,exist_ok=True)
    images=np.asarray(images,dtype=np.int8).reshape(-1,28,28)
    logits=infer(images,cw,cb,fw,fb,shift)
    model=model_packet(cw,cb,fw,fb,shift)
    packets=np.concatenate([image_packet(x) for x in images])
    for name,values in [('model',model),('images',packets),('expected',logits.view(np.uint32).ravel())]:
        (out/f'{name}.hex').write_text(''.join(f'{int(v):08x}\n' for v in values))
        values.astype('<u4').tofile(out/f'{name}.bin')
    np.savez(out/'model.npz',cw=cw,cb=cb,fw=fw,fb=fb,shift=shift,images=images,labels=labels)
    meta=dict(metadata or {}); meta.update(frames=len(images),model_words=len(model),shift=int(shift))
    (out/'metadata.json').write_text(json.dumps(meta,indent=2))
    def c_array(name,values):
        rows=[', '.join(f'0x{int(v):08x}U' for v in values[i:i+8]) for i in range(0,len(values),8)]
        return f'static const uint32_t {name}[] = {{\n'+',\n'.join(rows)+'\n};\n'
    h='#ifndef CNN_TEST_DATA_H\n#define CNN_TEST_DATA_H\n#include <stdint.h>\n'
    h+=f'#define CNN_TEST_FRAMES {len(images)}\n'
    h+=c_array('cnn_model_words',model)+c_array('cnn_image_words',packets)
    h+=c_array('cnn_expected',logits.view(np.uint32).ravel())
    h+='static const uint8_t cnn_labels[] = {'+','.join(map(str,labels))+'};\n#endif\n'
    (out/'cnn_test_data.h').write_text(h)
    return logits

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser(); p.add_argument('--out',default='vectors'); p.add_argument('--frames',type=int,default=4)
    args=p.parse_args(); rng=np.random.default_rng(421)
    cw=rng.integers(-127,128,(4,3,3),dtype=np.int16).astype(np.int8)
    fw=rng.integers(-127,128,(10,676),dtype=np.int16).astype(np.int8)
    cb=np.array([-50000,17000,-10,60000],np.int32)
    fb=np.arange(10,dtype=np.int32)*131-700
    images=rng.integers(0,128,(args.frames,28,28),dtype=np.int16).astype(np.int8)
    images[0]=0
    if args.frames>1: images[1]=127
    export(args.out,images,[255]*args.frames,cw,cb,fw,fb,9,
           {'kind':'synthetic protocol/numerical test; NOT a trained classifier','seed':421})
    print(f'Exported {args.frames} synthetic reference frames')
