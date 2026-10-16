# 归档说明（2026-10-15 由 avatar-engine 生成，Lead 归档）
# 这些脚本用于「把上游 SVG 参考渲染与本机截图做像素对比」。
# 归档时把原来写死的 /tmp/... 路径改成脚本同目录下的相对路径；
# 运行前请把对应截图放到本目录，或按下方变量改路径。
import os
HERE = os.path.dirname(os.path.abspath(__file__))

import json, sys
CAT='/Users/ponyrun/Documents/HarmonyApp/dsbotHarmony/entry/src/main/resources/rawfile/characters.json'
d=json.load(open(CAT))
shape=sys.argv[1]
c=d['characters'][shape]
gid='g'
s='<defs><linearGradient id="%s" x1="18" y1="10" x2="78" y2="92" gradientUnits="userSpaceOnUse">'%gid
s+='<stop offset="0" stop-color="#A4FFB0"/><stop offset="0.42" stop-color="#00F0E4"/><stop offset="1" stop-color="#2E9EF7"/></linearGradient>'
s+='<mask id="m" maskUnits="userSpaceOnUse" x="-100" y="-100" width="300" height="300"><rect x="-100" y="-100" width="300" height="300" fill="white"/>'
for (cx,cy,w,h,t) in c['eyes']:
    s+=f'<rect x="{-w/2}" y="{-h/2}" width="{w}" height="{h}" rx="{w/2}" fill="black" transform="translate({cx} {cy}) rotate({t})"/>'
s+='</mask></defs>'
body='<g mask="url(#m)">'
body+=f'<path d="{c["body"]}" fill="url(#{gid})"/>'
for p in c.get('paints',[]):
    op=f' opacity="{p[2]}"' if len(p)>2 else ''
    body+=f'<path d="{p[0]}" fill="{p[1]}"{op}/>'
body+=f'<path d="{c["shade"]}" fill="black" opacity="0.14"/>'
body+=f'<path d="{c["light"]}" fill="white" opacity="0.16"/>'
body+='</g>'
svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="-5 -5 110 110"><rect x="-5" y="-5" width="110" height="110" fill="#FFFFFF"/>{s}{body}</svg>'
open(f'/tmp/aurora_ref_{shape}.svg','w').write(svg)
print(f'/tmp/aurora_ref_{shape}.svg')
