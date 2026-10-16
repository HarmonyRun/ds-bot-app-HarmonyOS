# 归档说明（2026-10-15 由 avatar-engine 生成，Lead 归档）
# 这些脚本用于「把上游 SVG 参考渲染与本机截图做像素对比」。
# 归档时把原来写死的 /tmp/... 路径改成脚本同目录下的相对路径；
# 运行前请把对应截图放到本目录，或按下方变量改路径。
import os
HERE = os.path.dirname(os.path.abspath(__file__))

import json, html
CAT='/Users/ponyrun/Documents/HarmonyApp/dsbotHarmony/entry/src/main/resources/rawfile/characters.json'
d=json.load(open(CAT))
shapes=d['shapes']; colors=d['colors']
S=100.0
def cell(shape,color,x,y,size):
    c=d['characters'][shape]; ink=d['inks'][color]
    mid=f'm{shape}{color}'
    g=[]
    g.append(f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="-100" y="-100" width="300" height="300">'
             f'<rect x="-100" y="-100" width="300" height="300" fill="white"/>')
    for (cx,cy,w,h,t) in c['eyes']:
        g.append(f'<rect x="{-w/2}" y="{-h/2}" width="{w}" height="{h}" rx="{w/2}" fill="black" '
                 f'transform="translate({cx} {cy}) rotate({t})"/>')
    g.append('</mask>')
    body=f'<g mask="url(#{mid})">'
    body+=f'<path d="{c["body"]}" fill="{ink[0]}"/>'
    for p in c.get('paints',[]):
        op=f' opacity="{p[2]}"' if len(p)>2 else ''
        body+=f'<path d="{p[0]}" fill="{p[1]}"{op}/>'
    body+=f'<path d="{c["shade"]}" fill="black" opacity="0.14"/>'
    body+=f'<path d="{c["light"]}" fill="white" opacity="0.16"/>'
    body+='</g>'
    return (f'<g transform="translate({x} {y}) scale({size/S})">'+''.join(g)+body+'</g>')
parts=[]
# 20 shapes in blue
for i,s in enumerate(shapes):
    parts.append(cell(s,'blue',(i%10)*110+5,(i//10)*110+5,100))
# 12 colors on whale
for i,co in enumerate(colors):
    parts.append(cell('whale',co,5+i*110,240,100))
w=10*110+10; h=3*110+30
svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect width="100%" height="100%" fill="#FFFFFF"/>'+''.join(parts)+'</svg>'
open(os.path.join(HERE, 'avatar_preview.svg'),'w').write(svg)
print('shapes row:', ' '.join(shapes))
print('colors row:', ' '.join(colors))
print('svg bytes', len(svg))
