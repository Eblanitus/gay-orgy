"""Узоры жуков по роли — для видов, у которых пятна панциря ничего не говорят о жуке
(решение автора 2026-10-07: Таран — «просто кубы», узоры слишком похожи друг на друга).

Каждый мотив рисует три слоя в 2048×2048 (потом уменьшается до 1024): F — фигуры среднего тона,
D — тёмная середина фигур, L — светлые линии от руки. Контур фигур рисуется сам по краю F/D.
Всё рисуется со сдвигом на размер текстуры, поэтому фигуры переходят через край без шва.
Результат — та же маска, что у пятен панциря (фон 0.12, фигуры 0.5, линии 1); негатив делает
patterns.py. seed постоянный — при том же коде маска та же.
"""
import math, sys, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd
S=2048; R=1024
class Canvas:
    def __init__(s,seed):
        s.rng=np.random.default_rng(seed)
        s.F=Image.new('L',(S,S)); s.D=Image.new('L',(S,S)); s.L=Image.new('L',(S,S))
        s.f=ImageDraw.Draw(s.F); s.d=ImageDraw.Draw(s.D); s.l=ImageDraw.Draw(s.L)
        # smooth 1-D noise table used to wobble every stroke a little, like a hand
        s.noise=nd.gaussian_filter1d(s.rng.standard_normal(4096),18,mode='wrap'); s.noise/=s.noise.std()
    def wob(s,pts,amp=3.0,step=6):
        pts=np.asarray(pts,float)
        if len(pts)<2: return pts
        seg=np.hypot(*np.diff(pts,axis=0).T); L=np.concatenate([[0],np.cumsum(seg)])
        if L[-1]<1: return pts
        t=np.linspace(0,L[-1],max(2,int(L[-1]/step)))
        x=np.interp(t,L,pts[:,0]); y=np.interp(t,L,pts[:,1])
        dx=np.gradient(x); dy=np.gradient(y); n=np.hypot(dx,dy)+1e-9
        o=s.rng.integers(0,4096); k=s.noise[(o+np.arange(len(t))*2)%4096]*amp
        return np.column_stack([x-dy/n*k,y+dx/n*k])
    def _wrap(s,fn,pts,*a,**kw):
        # draw 9 times shifted by the texture size so shapes cross the edge seamlessly
        for ox in (-S,0,S):
            for oy in (-S,0,S):
                q=np.asarray(pts,float)+[ox,oy]
                if q[:,0].max()<-50 or q[:,0].min()>S+50 or q[:,1].max()<-50 or q[:,1].min()>S+50: continue
                fn([tuple(p) for p in q],*a,**kw)
    def line(s,pts,w=4,amp=3.0,layer='L',val=255):
        q=s.wob(pts,amp)
        dr={'L':s.l,'F':s.f,'D':s.d}[layer]
        ww=max(1,int(round(w*1.8*(0.8+0.4*s.rng.random()))))
        s._wrap(lambda p: dr.line(p,fill=val,width=ww,joint='curve'),q)
    def poly(s,pts,layer='F',amp=3.0,val=255):
        pts=np.asarray(pts,float); q=s.wob(np.vstack([pts,pts[:1]]),amp)
        dr={'L':s.l,'F':s.f,'D':s.d}[layer]
        s._wrap(lambda p: dr.polygon(p,fill=val),q)
    def blob(s,cx,cy,rx,ry,ang=0,n=40,irr=0.08,layer='F',val=255):
        t=np.linspace(0,2*math.pi,n,endpoint=False)
        r=1+irr*nd.gaussian_filter1d(s.rng.standard_normal(n),2,mode='wrap')
        x=np.cos(t)*rx*r; y=np.sin(t)*ry*r; c,sn=math.cos(ang),math.sin(ang)
        s.poly(np.column_stack([cx+x*c-y*sn,cy+x*sn+y*c]),layer,amp=1.5,val=val)
    def ring(s,cx,cy,rx,ry,ang=0,w=4,a0=0,a1=2*math.pi,n=60,dash=None):
        t=np.linspace(a0,a1,n); c,sn=math.cos(ang),math.sin(ang)
        x=np.cos(t)*rx; y=np.sin(t)*ry; p=np.column_stack([cx+x*c-y*sn,cy+x*sn+y*c])
        if dash:
            on,off=dash; i=0
            while i<len(p)-1:
                s.line(p[i:i+on+1],w,amp=1.5); i+=on+off
        else: s.line(p,w,amp=1.5)
    def points(s,mind,count=6000):
        mind*=0.72
        # dart throwing on the torus
        P=[]
        for _ in range(count):
            p=s.rng.uniform(0,S,2)
            if all(min(abs(p[0]-q[0]),S-abs(p[0]-q[0]))**2+min(abs(p[1]-q[1]),S-abs(p[1]-q[1]))**2>mind**2 for q in P): P.append(p)
        return P
def rot(pts,a,cx=0,cy=0):
    c,s=math.cos(a),math.sin(a); p=np.asarray(pts,float)
    return np.column_stack([cx+p[:,0]*c-p[:,1]*s, cy+p[:,0]*s+p[:,1]*c])
def compose(cv):
    sm=lambda im: np.asarray(im.resize((R,R),Image.LANCZOS)).astype(float)/255
    F,D,L=sm(cv.F),sm(cv.D),sm(cv.L)
    fill=F>0.5; inn=fill&(D>0.5)
    edge=np.zeros((R,R),bool)
    for M in (fill,inn):
        for sh in ((0,1),(1,0)): edge|=M!=np.roll(M,sh,(0,1))
    d=nd.distance_transform_edt(~edge)
    rng=cv.rng
    fld=nd.gaussian_filter(rng.standard_normal((R,R)),18,mode='wrap'); fld/=fld.std()
    wid=1.4+0.6*np.clip(fld,-1.5,1.5)
    eline=np.clip(wid-d+0.5,0,1)
    out=np.where(fill,np.where(inn,0.3,0.5),0.12)
    # sparse pores on the shapes, sparse punctures on the ground: same texture as before
    inner=d>7
    for zone,count,val,mul in ((fill&inner,1200,None,0.5),(~fill&inner,600,0.28,None)):
        dots=np.zeros((R,R),np.float32)
        for _ in range(count):
            yi,xi=rng.integers(0,R,2); r=rng.uniform(1.3,2.6)
            y0,y1,x0,x1=max(0,yi-4),min(R,yi+5),max(0,xi-4),min(R,xi+5)
            gy,gx=np.mgrid[y0:y1,x0:x1]; dots[y0:y1,x0:x1]=np.maximum(dots[y0:y1,x0:x1],np.clip(r-np.hypot(gy-yi,gx-xi)+0.5,0,1))
        out=np.where(zone,out*(1-mul*dots) if mul else np.maximum(out,dots*val),out)
    out=np.maximum(out,eline); out=np.maximum(out,L*(0.88+0.12*np.clip(fld,-1,1)))
    return out
PI=math.pi
def ram(cv):
    # Таран: пролом от удара — неровная вмятина с кольцами-волнами и рваные зигзаги трещин
    def crack(x,y,a,L,w,depth=0):
        pts=[(x,y)]; seg=L/5
        for k in range(5):
            a+=cv.rng.uniform(-0.55,0.55); x+=math.cos(a)*seg; y+=math.sin(a)*seg; pts.append((x,y))
            if depth<1 and cv.rng.random()<0.35: crack(x,y,a+cv.rng.choice([-1,1])*cv.rng.uniform(0.5,1.0),L*0.45,max(2,w-1),depth+1)
        cv.line(pts,w,amp=0.6)
    for p in cv.points(560):
        x,y=p; r=cv.rng.uniform(70,105); a0=cv.rng.uniform(0,2*PI)
        pts=[(math.cos(t)*r*cv.rng.uniform(0.75,1.15),math.sin(t)*r*cv.rng.uniform(0.75,1.15)) for t in np.linspace(0,2*PI,9,endpoint=False)]
        cv.poly(rot(pts,a0,x,y),amp=0.8)
        cv.poly(rot([(px*0.55,py*0.55) for px,py in pts],a0+0.3,x,y),layer='D',amp=0.8)
        for k in (1.35,1.7): cv.ring(x,y,r*k,r*k*0.92,a0,w=3,a0=cv.rng.uniform(0,2*PI),a1=None or 0,n=2) if False else cv.ring(x,y,r*k,r*k*0.92,a0,w=3,a0=0,a1=cv.rng.uniform(1.2,2.4)*PI/1.2,n=40)
        for k in range(cv.rng.integers(6,9)):
            a=k/7*2*PI+cv.rng.uniform(-0.3,0.3)
            crack(x+math.cos(a)*r*0.95,y+math.sin(a)*r*0.95,a,r*cv.rng.uniform(1.6,2.6),5)
def shadow(cv):
    # Тень: силуэт жука и за ним тающие пунктирные двойники — турель видит, где он был
    for p in cv.points(400):
        x,y=p; a=cv.rng.uniform(0,2*PI); r=cv.rng.uniform(55,75)
        cv.blob(x,y,r*1.35,r,a,irr=0.05)
        for k in range(1,4):
            gx,gy=x-math.cos(a)*r*1.9*k,y-math.sin(a)*r*1.9*k
            cv.ring(gx,gy,r*1.35,r,a,w=3,n=48,dash=(4-k+1,2+k))
def sprinter(cv):
    # Спринтер: рывки — шевроны-стрелки и штрихи скорости за ними
    for p in cv.points(360):
        x,y=p; a=cv.rng.choice([0,PI])+cv.rng.uniform(-0.25,0.25); r=cv.rng.uniform(65,95)
        ch=np.array([(r,0),(-r*0.5,-r*0.9),(-r*0.1,0),(-r*0.5,r*0.9)])
        cv.poly(rot(ch,a,x,y),amp=1.2)
        for j in range(-2,3):
            L=r*cv.rng.uniform(1.5,3.2); off=j*r*0.32; st=-r*0.4
            p0=rot([(st,off),(st-L,off)],a,x,y)
            cv.line(p0,3,amp=0.8)
def worker(cv):
    # Работяга: куски стены, выгрызенные полукругами, рядом крошки
    bw,bh=150,72
    for p in cv.points(640):
        x0,y0=p; cols=cv.rng.integers(3,5); rows=cv.rng.integers(2,4)
        for r_ in range(rows):
            off=(r_%2)*bw/2
            for c in range(cols+(r_%2)):
                x=x0+c*bw-off; y=y0+r_*bh; g=6
                if r_%2 and c in (0,cols): continue
                cv.poly(np.array([(x+g,y+g),(x+bw-g,y+g),(x+bw-g,y+bh-g),(x+g,y+bh-g)]),amp=1.2)
        W,H=cols*bw,rows*bh
        for k in range(cv.rng.integers(2,4)):
            side=cv.rng.integers(0,4); t=cv.rng.uniform(0.2,0.8); rr=cv.rng.uniform(45,62)
            bx,by=[(x0+t*W,y0),(x0+t*W,y0+H),(x0,y0+t*H),(x0+W,y0+t*H)][side]
            for m in range(cv.rng.integers(2,4)):
                cv.blob(bx+m*rr*0.8*(side<2),by+m*rr*0.8*(side>=2),rr,rr*0.9,n=24,irr=0.05,val=0)
            for m in range(6):
                cv.blob(bx+cv.rng.normal(0,rr*1.4),by+cv.rng.normal(0,rr*1.4)+(rr*1.8 if side==1 else -rr*1.8 if side==0 else 0),cv.rng.uniform(5,10),cv.rng.uniform(4,8),cv.rng.uniform(0,PI),n=8,irr=0.2)
def evolver(cv):
    # Эволюционер: линька — сброшенные шкурки, контуры вложены со сдвигом, старая трескается
    for p in cv.points(460):
        x,y=p; a=cv.rng.uniform(0,2*PI); r=cv.rng.uniform(75,100)
        cv.blob(x,y,r*1.3,r,a,irr=0.06)
        for k in range(1,4):
            dx,dy=math.cos(a)*14*k,math.sin(a)*14*k
            cv.ring(x+dx,y+dy,r*1.3+k*16,r+k*14,a,w=4,a0=0.9,a1=2*PI-0.9+0.3*k,n=50)
        cv.line([(x-math.cos(a)*r*1.3,y-math.sin(a)*r*1.3),(x,y+cv.rng.uniform(-8,8)),(x+math.cos(a)*r*0.9,y+math.sin(a)*r*0.9)],4,amp=4,layer='F',val=0)
def mimic(cv):
    # Мимик: «мешки и обломки», а у некоторых глаза и зубы
    for p in cv.points(380):
        x,y=p; a=cv.rng.uniform(-0.4,0.4); r=cv.rng.uniform(75,110)
        kind=cv.rng.random()
        if kind<0.5:
            cv.blob(x,y,r*1.2,r*0.85,a,irr=0.12)
            cv.line(rot([(-r*0.5,-r*0.85),(-r*0.2,-r*1.05),(0,-r*0.8),(r*0.2,-r*1.05),(r*0.45,-r*0.85)],a,x,y),3,amp=1)
        else:
            pts=[(math.cos(t)*r*cv.rng.uniform(0.7,1.1),math.sin(t)*r*cv.rng.uniform(0.6,0.9)) for t in np.linspace(0,2*PI,6,endpoint=False)]
            cv.poly(rot(pts,a,x,y),amp=1)
        if cv.rng.random()<0.6:
            for sx in (-1,1):
                cv.blob(*rot([(sx*r*0.32,-r*0.1)],a,x,y)[0],r*0.14,r*0.1,a,layer='D')
                cv.blob(*rot([(sx*r*0.32,-r*0.1)],a,x,y)[0],r*0.05,r*0.05,layer='L')
            teeth=[(-r*0.4,r*0.25)]
            for i in range(6): teeth.append((-r*0.4+(i+0.5)*r*0.8/6,r*(0.4 if i%2==0 else 0.25)))
            cv.line(rot(teeth,a,x,y),3,amp=0.5)
def shield(cv):
    # Щитоносец: строй щитов — по три внахлёст, у каждого кант и ось, позади ряды точек-жуков
    w,h=170,210
    def one(cx,cy):
        k=0.82; t=np.linspace(0,PI,10)
        pts=[(-w/2*k,-h/2*k),(w/2*k,-h/2*k)]+[(w/2*k*math.cos(tt),h/2*k*math.sin(tt)*0.95) for tt in t]
        cv.poly(np.array(pts)+[cx,cy],amp=1.5)
        cv.poly(np.array([(px*0.7,py*0.7+6) for px,py in pts])+[cx,cy],layer='D',amp=1.2)
        cv.line([(cx,cy-h/2*k*0.7+6),(cx,cy+h/2*k*0.62)],3,amp=0.8)
    for p in cv.points(560):
        x,y=p
        for j in (-1,0,1): one(x+j*w*0.95,y+abs(j)*14)
        for j in range(-3,4):
            for r_ in (1,2):
                cv.blob(x+j*w*0.4,y-h*0.55-r_*44,10,8,n=12,irr=0.1)
def normal(cv):
    # Стандарт: разведчик петляет по полу — извилистые дорожки следов с петлями
    for k in range(16):
        x,y=cv.rng.uniform(0,S,2); a=cv.rng.uniform(0,2*PI); pts=[]
        for i in range(120):
            a+=cv.rng.normal(0,0.22)+(0.35 if 40<i<52 else 0)
            x+=math.cos(a)*22; y+=math.sin(a)*22; pts.append((x,y))
        pts=np.array(pts)
        cv.line(pts,4,amp=2)
        for i in range(0,len(pts)-1,4):
            d=pts[i+1]-pts[i]; n=np.array([-d[1],d[0]])/(np.hypot(*d)+1e-9)
            for sgn in (-1,1):
                q=pts[i]+n*sgn*16
                cv.blob(q[0],q[1],6,4,math.atan2(d[1],d[0]),n=12,irr=0.1)
        hx,hy=pts[-1]; cv.blob(hx,hy,34,24,math.atan2(*(pts[-1]-pts[-2])[::-1]))
def coordinator(cv):
    # Координатор: метки цели, к ним сходятся стрелки — все бьют в одну точку
    for p in cv.points(430):
        x,y=p; r=cv.rng.uniform(85,110)
        cv.blob(x,y,r,r,irr=0.03); cv.blob(x,y,r*0.62,r*0.62,irr=0.03,layer='D'); cv.blob(x,y,r*0.25,r*0.25,irr=0.03)
        for a in (0,PI/2,PI,3*PI/2): cv.line([(x+math.cos(a)*r*1.1,y+math.sin(a)*r*1.1),(x+math.cos(a)*r*1.45,y+math.sin(a)*r*1.45)],4,amp=0.5)
        for k in range(cv.rng.integers(3,5)):
            a=cv.rng.uniform(0,2*PI); d0=r*cv.rng.uniform(2.6,3.4); d1=r*1.65
            sx,sy=x+math.cos(a)*d0,y+math.sin(a)*d0; ex,ey=x+math.cos(a)*d1,y+math.sin(a)*d1
            cv.line([(sx,sy),(ex,ey)],5,amp=1.5)
            for s in (-1,1):
                b=a+s*0.5; cv.line([(ex,ey),(ex+math.cos(b)*40,ey+math.sin(b)*40)],5,amp=0.5)
def carrier(cv):
    # Носитель: мешки-брюшки, внутри сидят жуки
    for p in cv.points(400):
        x,y=p; a=cv.rng.uniform(0,2*PI); r=cv.rng.uniform(95,125)
        cv.blob(x,y,r*1.15,r,a,irr=0.07)
        cv.blob(x,y,r*0.95,r*0.8,a,irr=0.07,layer='D')
        q=[]
        for _ in range(60):
            u=cv.rng.uniform(-0.65,0.65,2)
            if (u[0]/0.75)**2+(u[1]/0.6)**2<1 and all(np.hypot(*(u-v))>0.4 for v in q): q.append(u)
        for u in q:
            bx,by=rot([(u[0]*r*1.15,u[1]*r)],a,x,y)[0]; b=cv.rng.uniform(0,2*PI)
            cv.blob(bx,by,26,18,b,n=20,irr=0.05,layer='D',val=0)
            cv.line([(bx+math.cos(b)*22,by+math.sin(b)*22),(bx+math.cos(b)*34,by+math.sin(b)*34)],3,amp=0.3)
MOTIFS={'Ram':ram,'Shadow':shadow,'Sprinter':sprinter,'Worker':worker,'Evolver':evolver,'Mimic':mimic,
        'ShieldBearer':shield,'Normal':normal,'Coordinator':coordinator,'Carrier':carrier}


def build(key, seed=7):
    """Маска мотива вида key (ключ Enemies), 1024×1024, 0..1."""
    cv = Canvas(seed)
    MOTIFS[key](cv)
    return compose(cv)
