"""Build Circadia's star table: resources/jsonData/stars.json.

Source: Yale Bright Star Catalogue, 5th revised ed. (Hoffleit & Warren 1991),
distributed by NASA HEASARC (a U.S. government work), here read from the JSON
conversion at https://github.com/brettonw/YaleBrightStarCatalog (bsc5-all.json).

Steps: drop entries without a position or V magnitude; combine entries closer
than 0.2 deg (the eye sees them as one star) by adding their light; apply
proper motion and precess to the mean equinox of EPOCH (astropy FK5); keep
the N brightest; pack each into one integer (see Stellar in stellar.mc).

    pip install astropy
    python3 build_stars.py /path/to/bsc5-all.json ../resources/jsonData/stars.json
"""
import sys
# Build Circadia's star table from the Yale Bright Star Catalogue (5th ed., via brettonw/YaleBrightStarCatalog).
import json, math, numpy as np
from astropy.coordinates import SkyCoord, FK5
import astropy.units as u
from astropy.time import Time
SRC='/home/claude/data/ybsc/bsc5-all.json'
EPOCH=2027.0
def parse():
    out=[]
    for s in json.load(open(SRC)):
        if 'Vmag' not in s or 'RAh' not in s: continue
        ra=15*(float(s['RAh'])+float(s['RAm'])/60+float(s['RAs'])/3600)
        de=(float(s['DEd'])+float(s['DEm'])/60+float(s['DEs'])/3600)*(-1 if s['DE-']=='-' else 1)
        bv=float(s['B-V']) if 'B-V' in s else None
        pmra=float(s.get('pmRA','0') or 0); pmde=float(s.get('pmDE','0') or 0)   # arcsec/yr, pmRA = mu_alpha cos(dec)
        out.append(dict(hr=int(s['HR']),ra=ra,de=de,v=float(s['Vmag']),bv=bv,pmra=pmra,pmde=pmde,name=s.get('Common','')))
    return out
def merge(stars, sep_deg=0.2):
    # combine close pairs (separate entries for the parts of a double the eye sees as one star)
    stars=sorted(stars,key=lambda s:s['v']); kept=[]
    for s in stars:
        for k in kept:
            d=math.degrees(math.acos(min(1,math.sin(math.radians(s['de']))*math.sin(math.radians(k['de']))+
                math.cos(math.radians(s['de']))*math.cos(math.radians(k['de']))*math.cos(math.radians(s['ra']-k['ra'])))))
            if d<sep_deg:
                f=10**(-0.4*k['v'])+10**(-0.4*s['v']); k['v']=-2.5*math.log10(f); k.setdefault('merged',[]).append(s['hr']); break
        else: kept.append(dict(s))
    return sorted(kept,key=lambda s:s['v'])
def to_epoch(stars, epoch=EPOCH):
    dt=epoch-2000.0
    ra=np.array([s['ra']+s['pmra']*dt/3600/max(1e-6,math.cos(math.radians(s['de']))) for s in stars])
    de=np.array([s['de']+s['pmde']*dt/3600 for s in stars])
    c=SkyCoord(ra=ra*u.deg,dec=de*u.deg,frame=FK5(equinox='J2000')).transform_to(FK5(equinox=Time(epoch,format='jyear')))
    for s,r,d in zip(stars,c.ra.deg,c.dec.deg): s['ra_e'],s['de_e']=float(r),float(d)
    return stars
N=520
RA_BITS, DEC_BITS, MAG_BITS, COL_BITS = 12, 10, 6, 3
MAG0, MAG_STEP = -1.5, 0.1
# Drawing.STAR_BIN_*: yellow 0, soft yellow 1, red 2, blue 3, white 4
def color_bin(bv):
    if bv is None: return 4
    if bv < -0.02: return 3          # B stars and hot A stars: blue  (Rigel, Spica, Regulus)
    if bv < 0.30:  return 4          # A and early F: white            (Sirius, Vega, Altair, Deneb)
    if bv < 0.65:  return 1          # F and early G: soft yellow      (Procyon, Polaris)
    if bv < 1.35:  return 0          # G and K: yellow-amber           (Capella, Pollux, Arcturus)
    return 2                          # late K and M: red-orange        (Aldebaran, Betelgeuse, Antares)
def pack(s):
    ra=int(round(s['ra_e']/360*(1<<RA_BITS)))%(1<<RA_BITS)
    de=min((1<<DEC_BITS)-1,max(0,int(round((s['de_e']+90)/180*((1<<DEC_BITS)-1)))))
    mg=min((1<<MAG_BITS)-1,max(0,int(round((s['v']-MAG0)/MAG_STEP))))
    return (ra<<(DEC_BITS+MAG_BITS+COL_BITS))|(de<<(MAG_BITS+COL_BITS))|(mg<<COL_BITS)|color_bin(s['bv'])
def unpack(v):
    col=v&7; mg=(v>>3)&63; de=(v>>9)&1023; ra=(v>>19)&4095
    return ra*360/4096, de*180/1023-90, MAG0+mg*MAG_STEP, col
def build(out='stars.json'):
    st=to_epoch(merge(parse()))[:N]
    vals=[pack(s) for s in st]
    assert max(vals)<2**31 and min(vals)>=0
    err=max(max(abs((unpack(v)[0]-s['ra_e']+180)%360-180)*math.cos(math.radians(s['de_e'])),abs(unpack(v)[1]-s['de_e'])) for v,s in zip(vals,st))
    print('N',N,'faintest',round(st[-1]['v'],2),'max position error',round(err,3),'deg')
    from collections import Counter
    c=Counter(color_bin(s['bv']) for s in st[:200]); print('colours in brightest 200:',{['yellow','soft yellow','red','blue','white'][k]:v for k,v in sorted(c.items())})
    for nm in ('Sirius','Vega','Betelgeuse','Rigel','Arcturus','Procyon','Polaris','Aldebaran','Antares','Capella'):
        s=next(x for x in st if x['name']==nm); print(f"  {nm:10} V={s['v']:5.2f} B-V={s['bv']} -> {['yellow','soft yellow','red','blue','white'][color_bin(s['bv'])]}")
    json.dump(vals,open(out,'w'),separators=(',',':'))
    print(out,'bytes',len(open(out).read()))

if __name__=='__main__':
    if len(sys.argv)>1: SRC=sys.argv[1]
    build(sys.argv[2] if len(sys.argv)>2 else 'stars.json')
