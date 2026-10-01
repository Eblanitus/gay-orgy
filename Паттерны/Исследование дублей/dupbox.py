import numpy as np, cv2, json, sys
from PIL import Image, ImageDraw, ImageFont
# boxes around copied regions: for an offset d, pixels where blurred a(p) ~ a(p+d) over a 41px window
OUT='C:/Users/user/Documents/GitHub/gay-orgy/Паттерны/out/'
res=json.load(open('dup/scan.json')); F=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',26)
COL=[(255,70,50),(60,200,255),(255,210,40)]
for n in sys.argv[1:]:
    fn='heat_outline_thin.png' if n=='heat' else 'p_%s.png'%n
    a=np.asarray(Image.open(OUT+fn).split()[-1]).astype(np.float32); h,w=a.shape; s=w/res[fn]['size'][0]
    b=cv2.GaussianBlur(a,(0,0),2)
    img=Image.fromarray(a.astype(np.uint8)).convert('RGB'); d=ImageDraw.Draw(img); seen=[]; tot=0
    for cnt,(fl,dx,dy) in res[fn]['clusters']:
        if fl!='n' or cnt<20: continue
        dx=int(dx*s); dy=int(dy*s)
        if any(abs(dx+q[0])<20 and abs(dy+q[1])<20 or abs(dx-q[0])<20 and abs(dy-q[1])<20 for q in seen): continue
        seen.append((dx,dy)); c=COL[len(seen)-1]
        m=np.zeros((h,w),np.float32)
        ys=slice(max(0,-dy),min(h,h-dy)); xs=slice(max(0,-dx),min(w,w-dx)); ys2=slice(max(0,dy),min(h,h+dy)); xs2=slice(max(0,dx),min(w,w+dx))
        m[ys,xs]=np.abs(b[ys,xs]-b[ys2,xs2])<18
        var=cv2.blur(a*a,(41,41))-cv2.blur(a,(41,41))**2
        m=((cv2.blur(m,(41,41))>.85)&(var>200)).astype(np.uint8)
        nc,lab,st,_=cv2.connectedComponentsWithStats(m)
        for k in range(1,nc):
            x,y,ww,hh,ar=st[k]
            if ar<3000: continue
            tot+=ar
            for ox,oy,wd in ((0,0,6),(dx,dy,6)):
                d.rectangle([x+ox,y+oy,x+ox+ww,y+oy+hh],outline=c,width=wd)
        if len(seen)==3: break
    img.resize((512,int(512*h/w))).save('dup/box_%s.png'%n)
    print(n,'offsets',seen,'copied share',round(tot/(h*w),2))
