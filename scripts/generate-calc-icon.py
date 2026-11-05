#!/usr/bin/env python3
"""Render the app's code-drawn monochrome calculator icon without third-party tools."""
import pathlib
import struct
import zlib
size = 256
pixels = bytearray([255, 255, 255] * size * size)
def rect(x, y, w, h, color):
    for row in range(max(0,y), min(size,y+h)):
        for col in range(max(0,x), min(size,x+w)):
            p=(row*size+col)*3
            pixels[p:p+3]=bytes(color)
rect(12,12,232,232,(0,0,0))
rect(18,18,220,220,(255,255,255))
rect(28,32,200,102,(0,0,0))
segments={'4':'bcfg','2':'abdeg'}
for x,ch in [(48,'4'),(135,'2')]:
    rect(x-8,42,72,80,(0,0,0))
    for seg,box in {'a':(x+7,49,34,6),'b':(x+43,55,6,25),'c':(x+43,85,6,25),'d':(x+7,112,34,6),'e':(x,85,6,25),'f':(x,55,6,25),'g':(x+7,80,34,6)}.items():
        rect(*box,(255,255,255) if seg in segments[ch] else (0,0,0))
for row in range(3):
    for col in range(4):
        rect(30+col*50,150+row*26,42,19,(0,0,0))
        rect(33+col*50,151+row*26,36,14,(255,255,255))
rect(180,202,42,24,(0,0,0))
rect(187,209,28,3,(255,255,255));rect(187,216,28,3,(255,255,255))
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
raw=b''.join(b'\0'+pixels[y*size*3:(y+1)*size*3] for y in range(size))
image=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
(pathlib.Path(__file__).resolve().parents[1]/'product/payload/apps/papercalc/icon.png').write_bytes(image)
