"""Saturn's ring for Planets.RING_AMOLED and RING_MIP (source/planets.mc).

A 1 px ellipse around the planet's 5 px disc: semi-axes 5.5 and 2.2 px, the
long axis rising 20 deg to the right, the far side up (drawn before the disc)
and the near side down (drawn after it). AMOLED: each pixel's share of a
1 px wide line, from 8x8 samples, in three strengths; pixels under 15% are
left out. MIP: the line's pixels, plain. Far-side pixels the disc covers are
left out.

    pip install numpy
    python3 ring_table.py
"""
import math, numpy as np
TH=math.radians(20); A=5.5; B=0.4*A
vx,vy=math.cos(TH),-math.sin(TH)          # major axis (screen, y down)
ux,uy=-math.sin(TH),-math.cos(TH)         # minor axis, pointing up-left (the far side)
def pts(front,n=2000):
    ts=np.linspace(0,2*math.pi,n,endpoint=False); s=np.sin(ts)
    keep=(s<0) if front else (s>=0)       # far side: +u (up); near side: -u
    ts=ts[keep]
    return np.c_[A*np.cos(ts)*vx+B*np.sin(ts)*ux, A*np.cos(ts)*vy+B*np.sin(ts)*uy]
def coverage(front,Z=8):
    P=pts(front); cov={}
    for dy in range(-6,7):
        for dx in range(-7,8):
            sub=(np.arange(Z)+0.5)/Z-0.5
            gx,gy=np.meshgrid(dx+sub,dy+sub); g=np.c_[gx.ravel(),gy.ravel()]
            d=np.min(np.hypot(g[:,None,0]-P[None,:,0],g[:,None,1]-P[None,:,1]),axis=1)
            c=float(np.mean(d<=0.5))
            if c>=0.15: cov[(dx,dy)]=c
    return cov
def amoled():
    out=[]
    for front in (False,True):
        for (dx,dy),c in sorted(coverage(front).items()):
            over=abs(dx)<=2 and abs(dy)<=2
            if over and not front: continue                    # hidden behind the disc
            lvl=1 if c<0.45 else 2 if c<0.75 else 3
            out.append((dx,dy,lvl,front,over))
    return out
def mip():
    disc={(dx,dy) for dx in range(-2,3) for dy in range(-2,3) if dx*dx+dy*dy<=5}; out=[]
    for front in (False,True):
        px=sorted({(int(round(x)),int(round(y))) for x,y in pts(front,720)})
        for q in px:
            if q in disc and not front: continue
            out.append((q[0],q[1],3,front,q in disc))
    return out
def pack(e):
    dx, dy, l, f, o = e
    return (dx+8)|((dy+8)<<4)|(l<<8)|(int(f)<<10)|(int(o)<<11)
if __name__=="__main__":
    for nm,t in (("AMOLED",amoled()),("MIP",mip())):
        print(nm,len(t),"pixels"); print([pack(e) for e in t])
