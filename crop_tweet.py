#!/usr/bin/env python
# -*-python-*-

import PIL.Image
import sys

# 50
# 260

png = sys.argv[1]
out = sys.argv[2]

im = PIL.Image.open(png)

(w, h) = im.size

x = 105
y = 50

start_y = None
stop_y = None

while y < h :
    
    pix = im.load()
    c = pix[x,y]

    if ((c[0] == 255 and c[1] == 255 and c[2] == 255) and not start_y) :
        start_y = y

    if ((start_y) and (c[0] != 255 or c[1] != 255 or c[2] != 255)) :
        stop_y = y
        break
    
    y += 1

w = 630
h = stop_y - start_y

x1=85
y1=52
x2=x1 + w
y2=y1 + h + 32

cr=im.crop((x1,y1,x2,y2))
cr.save(out)
