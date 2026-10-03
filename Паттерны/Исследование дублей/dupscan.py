import numpy as np, cv2, glob, os, json, sys
from PIL import Image
# copy-move scan: 32px blocks of a 512 downscale, best match elsewhere (also flipped), cluster by offset
OUT='C:/Users/user/Documents/GitHub/gay-orgy/Паттерны/out/'
files=sorted(glob.glob(OUT+'p_*.png'))+[OUT+'heat_outline_thin.png',OUT+'fire_inv_1024.png']
B=32; N=512; res={}
for f in files:
    im=Image.open(f); a=np.asarray(im.split()[-1] if im.mode in('RGBA','LA') else im.convert('L'))
    h,w=a.shape; s=N/max(h,w); a=cv2.resize(a,(int(w*s),int(h*s)),interpolation=cv2.INTER_AREA).astype(np.float32)
    H,W=a.shape
    if a.std()<1: continue
    hits=[]
    for fl,src in (('n',a),('h',a[:,::-1].copy()),('v',a[::-1].copy()),('hv',a[::-1,::-1].copy())):
        for y in range(0,H-B+1,B//2):
            for x in range(0,W-B+1,B//2):
                t=a[y:y+B,x:x+B]
                if t.std()<12: continue
                r=cv2.matchTemplate(src,t,cv2.TM_SQDIFF_NORMED)
                # exclude self (only for unflipped)
                if fl=='n': r[max(0,y-24):y+25,max(0,x-24):x+25]=9
                v,_,(mx,my),_=cv2.minMaxLoc(r)
                if v<0.06: hits.append((fl,x,y,mx,my,float(v)))
    # cluster: offsets for n, mapping for flips
    cl={}
    for fl,x,y,mx,my,v in hits:
        if fl=='n': key=(fl,round((mx-x)/8)*8,round((my-y)/8)*8)
        elif fl=='h': key=(fl,round((mx+x)/8)*8,round((my-y)/8)*8)
        elif fl=='v': key=(fl,round((mx-x)/8)*8,round((my+y)/8)*8)
        else: key=(fl,round((mx+x)/8)*8,round((my+y)/8)*8)
        cl.setdefault(key,[]).append((x,y,mx,my))
    tot=((H-B)//(B//2)+1)*((W-B)//(B//2)+1)
    big=sorted(((len(v),k) for k,v in cl.items() if len(v)>=4),reverse=True)[:4]
    name=os.path.basename(f)
    res[name]=dict(size=(W,H),blocks=tot,clusters=[(n,list(map(lambda q: q if isinstance(q,str) else int(q),k))) for n,k in big])
    print(name,res[name],flush=True)
json.dump(res,open('dup/scan.json','w'),ensure_ascii=False)
