"""Train MNIST on PC; power-of-two PTQ calibrated only on training data.
Run from package root: python python/train_export.py --epochs 5 --out trained
Requires torch, torchvision, numpy. Training is NEVER done on the FPGA.
"""
import argparse
import json
import math
from pathlib import Path
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, TensorDataset
from torchvision.datasets import MNIST
from reference import export, infer

class TinyCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv=nn.Conv2d(1,4,3)
        self.fc=nn.Linear(676,10)
    def forward(self,x):
        return self.fc(torch.max_pool2d(torch.relu(self.conv(x)),2).flatten(1))

def weight_quant(w):
    a=w.detach().cpu().numpy()
    exponent=math.floor(math.log2(127/max(float(np.max(np.abs(a))),1e-12)))
    scale=2.0**exponent
    return np.clip(np.rint(a*scale),-127,127).astype(np.int8),exponent

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--epochs',type=int,default=5)
    p.add_argument('--out',default='trained')
    p.add_argument('--data',default='data')
    p.add_argument('--frames',type=int,default=16)
    p.add_argument('--threads',type=int,default=4)
    args=p.parse_args()
    if not 1<=args.frames<=10000: p.error('--frames must be 1..10000')
    torch.set_num_threads(args.threads); torch.manual_seed(42); np.random.seed(42)
    train=MNIST(args.data,train=True,download=True)
    test=MNIST(args.data,train=False,download=True)
    # Identical integer input mapping in training, host C, and FPGA.
    tx=(train.data.to(torch.int16)>>1).float().unsqueeze(1)/128.0
    vx=(test.data.to(torch.int16)>>1).float().unsqueeze(1)/128.0
    loader=DataLoader(TensorDataset(tx,train.targets),batch_size=128,shuffle=True)
    net=TinyCNN(); opt=torch.optim.Adam(net.parameters(),lr=0.002)
    for epoch in range(args.epochs):
        net.train(); loss_sum=0
        for x,y in loader:
            opt.zero_grad(); loss=nn.functional.cross_entropy(net(x),y)
            loss.backward(); opt.step(); loss_sum+=loss.item()*len(y)
        net.eval()
        with torch.no_grad():
            correct=sum((net(x).argmax(1)==y).sum().item() for x,y in DataLoader(TensorDataset(vx,test.targets),batch_size=256))
        print(f'epoch={epoch+1} loss={loss_sum/60000:.5f} fp32_test={correct/10000:.4%}',flush=True)
    cw,wexp=weight_quant(net.conv.weight)
    fw,fexp=weight_quant(net.fc.weight)
    # Calibration range from TRAINING samples, never the test set.
    with torch.no_grad(): peak=max(net.conv(tx[i:i+128]).relu().max().item() for i in range(0,2048,128))
    aexp=math.floor(math.log2(127/max(peak,1e-12)))
    shift=7+wexp-aexp
    if not 0<=shift<=24: raise RuntimeError(f'Unsupported requant shift {shift}')
    cb=np.rint(net.conv.bias.detach().numpy()*2.0**(7+wexp)).astype(np.int32)
    fb=np.rint(net.fc.bias.detach().numpy()*2.0**(aexp+fexp)).astype(np.int32)
    # Static worst-case accumulation check, including biases.
    if np.max(np.abs(cb.astype(np.int64)))+9*127*127>=2**31: raise OverflowError('Conv bias')
    if np.max(np.abs(fb.astype(np.int64)))+676*127*127>=2**31: raise OverflowError('FC bias')
    images=(test.data.numpy().astype(np.int16)>>1).astype(np.int8)
    pred=np.concatenate([infer(images[i:i+128],cw,cb,fw,fb,shift).argmax(1) for i in range(0,10000,128)])
    accuracy=float(np.mean(pred==test.targets.numpy()))
    metadata={'kind':'trained MNIST PTQ','seed':42,'epochs':args.epochs,'test_samples':10000,
              'fp32_accuracy':correct/10000,'int8_accuracy':accuracy,'weight_exponent':wexp,
              'activation_exponent':aexp,'fc_weight_exponent':fexp,'calibration':'first 2048 training samples'}
    export(args.out,images[:args.frames],test.targets.numpy()[:args.frames],cw,cb,fw,fb,shift,metadata)
    torch.save(net.state_dict(),Path(args.out)/'model_fp32.pt')
    print(json.dumps(metadata,indent=2),flush=True)

if __name__=='__main__': main()
