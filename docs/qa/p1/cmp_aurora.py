# 归档说明（2026-10-15 由 avatar-engine 生成，Lead 归档）
# 这些脚本用于「把上游 SVG 参考渲染与本机截图做像素对比」。
# 归档时把原来写死的 /tmp/... 路径改成脚本同目录下的相对路径；
# 运行前请把对应截图放到本目录，或按下方变量改路径。
import os
HERE = os.path.dirname(os.path.abspath(__file__))

import sys
from PIL import Image

def mask_and_crop(img, box, colored_only):
    px=img.convert('RGB').load()
    x0,y0,x1,y1=box
    pts=[]
    for y in range(y0,y1):
        for x in range(x0,x1):
            r,g,b=px[x,y]
            if colored_only:
                ok = max(r,g,b)-min(r,g,b)>45 and not (r>235 and g>235 and b>235)
            else:
                ok = not (r>240 and g>240 and b>240)
            if ok: pts.append((x,y))
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    return (min(xs),min(ys),max(xs)+1,max(ys)+1)

device=Image.open(os.path.join(HERE, 'final_aurora.jpeg'))
dbox=mask_and_crop(device,(380,380,940,1150),True)
ref=Image.open(os.path.join(HERE, 'aurora_ref_gumdrop.svg.png'))
rbox=mask_and_crop(ref,(0,0,600,600),False)
print('device body bbox',dbox,'ref body bbox',rbox)

N=160
d=Image.open(os.path.join(HERE, 'final_aurora.jpeg')).convert('RGB').crop(dbox).resize((N,N), Image.LANCZOS)
r=Image.open(os.path.join(HERE, 'aurora_ref_gumdrop.svg.png')).convert('RGB').crop(rbox).resize((N,N), Image.LANCZOS)
dp=d.load(); rp=r.load()
tot=0; n=0; worst=0; hist=[0]*8
for y in range(N):
    for x in range(N):
        c1=dp[x,y]; c2=rp[x,y]
        if max(c2)-min(c2)<25 and c2[0]>240: continue   # 参考里是背景
        if max(c1)-min(c1)<25 and c1[0]>240: continue   # 我们这边是背景
        e=(abs(c1[0]-c2[0])+abs(c1[1]-c2[1])+abs(c1[2]-c2[2]))/3
        tot+=e; n+=1; worst=max(worst,e); hist[min(7,int(e//16))]+=1
print(f'对比像素 {n}，平均 ΔRGB = {tot/n:.1f}，最大 {worst:.0f}')
print('误差直方图 (0-16,16-32,...):', hist)
# 沿上游方向的分段色相（两侧各算一遍）
import colorsys, math
L=math.hypot(60,82); dx,dy=60/L,82/L
def bands(img, box, label):
    im=img.crop(box).resize((N*2,N*2), Image.LANCZOS); p=im.load()
    pts=[]
    for y in range(N*2):
        for x in range(N*2):
            c=p[x,y]
            if max(c)-min(c)<40 or (c[0]>235 and c[1]>235 and c[2]>235): continue
            pts.append((x,y,c))
    cx=sum(q[0] for q in pts)/len(pts); cy=sum(q[1] for q in pts)/len(pts)
    pts.sort(key=lambda q:(q[0]-cx)*dx+(q[1]-cy)*dy)
    out=[]
    k=len(pts)//10
    for i in (0,4,9):
        seg=pts[i*k:(i+1)*k]
        r_=sum(q[2][0] for q in seg)//len(seg); g_=sum(q[2][1] for q in seg)//len(seg); b_=sum(q[2][2] for q in seg)//len(seg)
        h,s,v=colorsys.rgb_to_hsv(r_/255,g_/255,b_/255)
        out.append((i*10, f'#{r_:02X}{g_:02X}{b_:02X}', round(h*360,1)))
    print(f'  {label}: ' + ' | '.join(f'{o[0]}%→{o[1]}(hue {o[2]}°)' for o in out))
print('沿上游方向 (左上→右下) 十进制分位:')
bands(Image.open(os.path.join(HERE, 'final_aurora.jpeg')), dbox, 'device')
bands(Image.open(os.path.join(HERE, 'aurora_ref_gumdrop.svg.png')), rbox, 'upstream-ref')
