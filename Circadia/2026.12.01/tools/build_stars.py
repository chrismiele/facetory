"""Build Circadia's star tables in resources/jsonData/:

  stars_brightest.json       the brightest stars, brightest first
  stars_constellations.json  well-known constellation figures first

Sources
  Stars: Yale Bright Star Catalogue, 5th revised ed. (Hoffleit & Warren 1991),
    distributed by NASA HEASARC (a U.S. government work), read from the JSON
    conversion at https://github.com/brettonw/YaleBrightStarCatalog
    (bsc5-all.json).
  Constellation figures and asterisms: d3-celestial by Olaf Frohn
    (https://github.com/ofrohn/d3-celestial, data/constellations.lines.json
    and data/asterisms.json, BSD 3-clause licence). Only which stars belong
    to which figure is used.

Steps
  1. Drop entries without a position or V magnitude. Combine entries closer
     than 0.2 deg (the eye sees them as one star) by adding their light.
  2. Find each figure's and asterism's stars: every vertex is matched to the
     nearest catalogue star within 0.3 deg.
  3. Apply proper motion and precess to the mean equinox of EPOCH (astropy).
  4. Order the stars for each mode and keep as many as the busiest sky needs
     for 200 stars above the horizon (checked over all latitudes and
     sidereal times), with a margin.
  5. Pack each star into one integer (see Stellar in stellar.mc).

Constellations order: a star's rank is its magnitude, less a bonus:
  CORE_BONUS for the core shapes people recognise: the asterisms in
    CORE_ASTERISMS (Big Dipper, Cassiopeia's W, Orion's Belt, the Teapot...),
    the small figures in CORE_FIGURES, the Pleiades, and the bright stars
    (to CORE_ANCHOR_MAG) of the FAMOUS figures, such as Orion's shoulders
    and feet. Stars to CORE_MAX_MAG.
  FAMOUS_BONUS for the rest of a FAMOUS figure, to MEMBER_MAX_MAG.
  FIGURE_BONUS for a star in any other constellation figure.
Within each core shape and each famous figure, stars fainter than its median
are ranked at the median, so a shape comes in as a whole rather than star by
star.
The preference is soft: a very bright star outside the figures still makes
the cut. When each star appears, and how big it is, depends on its true
magnitude either way.

    pip install astropy numpy
    python3 build_stars.py BSC5_JSON D3_CELESTIAL_DATA_DIR OUT_DIR
"""
import sys, json, math
import numpy as np
from astropy.coordinates import SkyCoord, FK5
from astropy.time import Time
import astropy.units as u

EPOCH = 2027.0
K_MAX = 200                  # the "Lots" setting
MARGIN = 1.08                # extra stars beyond the worst case found on the grid

FAMOUS = ("UMa UMi Cas Cep Dra Cyg Lyr Aql Del Her CrB Boo Leo Vir Crv Gem Tau Ori "
          "Aur Per And Peg CMa CMi Lep Sco Sgr Cru Cen Car TrA Gru").split()
CORE_ASTERISMS = ("BigDipper LittleDipper TheQueensW HouseofCepheus Belt WinterTriangle "
                  "SummerTriangle Kite TheSickle NorthernCross PegasusSquare Teapot Fishhook "
                  "SouthernCross FalseCross Sail Keystone JobsCoffin Lozenge").split()
CORE_FIGURES    = "Lyr CrB TrA Cru".split()
CORE_ANCHOR_MAG = 2.5
CORE_MAX_MAG    = 5.0
MEMBER_MAX_MAG  = 4.5
CORE_BONUS      = 3.0
FAMOUS_BONUS    = 1.5
FIGURE_BONUS    = 0.5

RA_BITS, DEC_BITS, MAG_BITS, COL_BITS = 11, 10, 7, 3
MAG0, MAG_STEP = -1.5, 0.1


def sep(ra1, de1, ra2, de2):
    r = math.radians
    c = math.sin(r(de1))*math.sin(r(de2)) + math.cos(r(de1))*math.cos(r(de2))*math.cos(r(ra1 - ra2))
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def parse(path):
    out = []
    for s in json.load(open(path)):
        if 'Vmag' not in s or 'RAh' not in s:
            continue
        ra = 15*(float(s['RAh']) + float(s['RAm'])/60 + float(s['RAs'])/3600)
        de = (float(s['DEd']) + float(s['DEm'])/60 + float(s['DEs'])/3600)*(-1 if s['DE-'] == '-' else 1)
        out.append(dict(hr=int(s['HR']), ra=ra, de=de, v=float(s['Vmag']),
                        bv=float(s['B-V']) if 'B-V' in s else None,
                        pmra=float(s.get('pmRA', '0') or 0),     # arcsec/yr, mu_alpha cos(dec)
                        pmde=float(s.get('pmDE', '0') or 0),
                        name=s.get('Common', '')))
    return out


def merge(stars, sep_deg=0.2):
    stars = sorted(stars, key=lambda s: s['v']); kept = []
    for s in stars:
        for k in kept:
            if abs(k['de'] - s['de']) < sep_deg and sep(s['ra'], s['de'], k['ra'], k['de']) < sep_deg:
                k['v'] = -2.5*math.log10(10**(-0.4*k['v']) + 10**(-0.4*s['v']))
                break
        else:
            kept.append(dict(s))
    return sorted(kept, key=lambda s: s['v'])


def figures(stars, lines_path, strict=True):
    """{figure id: set of star indices drawn in it}. strict: every vertex must be a star
    (some asterisms point at empty sky, such as the south celestial pole)."""
    out = {}
    for f in json.load(open(lines_path))['features']:
        idx = out.setdefault(f['id'], set())
        for line in f['geometry']['coordinates']:
            for lon, lat in line:
                ra = lon % 360; best = None; bestd = 0.3
                for i, s in enumerate(stars):
                    if abs(s['de'] - lat) > 0.3:
                        continue
                    d = sep(ra, lat, s['ra'], s['de'])
                    if d < bestd:
                        best, bestd = i, d
                if best is None and not strict:
                    continue
                if best is None:
                    raise ValueError(f"no star for {f['id']} vertex {ra:.3f} {lat:.3f}")
                idx.add(best)
    return out


def to_epoch(stars, epoch=EPOCH):
    dt = epoch - 2000.0
    ra = np.array([s['ra'] + s['pmra']*dt/3600/max(1e-6, math.cos(math.radians(s['de']))) for s in stars])
    de = np.array([s['de'] + s['pmde']*dt/3600 for s in stars])
    c = SkyCoord(ra=ra*u.deg, dec=de*u.deg, frame=FK5(equinox='J2000')).transform_to(
        FK5(equinox=Time(epoch, format='jyear')))
    for s, r, d in zip(stars, c.ra.deg, c.dec.deg):
        s['ra_e'], s['de_e'] = float(r), float(d)
    return stars


def famous_groups(stars, figs):
    """{figure id: its stars to MEMBER_MAX_MAG} for the FAMOUS figures"""
    return {c: {i for i in figs[c] if stars[i]['v'] <= MEMBER_MAX_MAG} for c in FAMOUS}


def core_groups(stars, figs, asterisms):
    """{shape name: its stars to CORE_MAX_MAG} for the core shapes"""
    keep = lambda mem: {i for i in mem if stars[i]['v'] <= CORE_MAX_MAG}
    groups = {a: keep(asterisms[a]) for a in CORE_ASTERISMS}
    groups.update({c: keep(figs[c]) for c in CORE_FIGURES})
    for c in FAMOUS:
        anchors = {i for i in figs[c] if stars[i]['v'] <= CORE_ANCHOR_MAG}
        if anchors:
            groups[c + ' anchors'] = anchors
    a = next(i for i, s in enumerate(stars) if s['name'] == 'Alcyone')
    groups['Pleiades'] = {i for i, s in enumerate(stars) if s['v'] <= CORE_MAX_MAG
                          and sep(s['ra'], s['de'], stars[a]['ra'], stars[a]['de']) < 1.2}
    return groups


def constellation_order(stars, figs, asterisms):
    key = [s['v'] for s in stars]
    def favour(mem, bonus):
        g = float(np.median([stars[i]['v'] for i in mem])) - bonus
        for i in mem:
            key[i] = min(key[i], stars[i]['v'] - bonus, g)
    for c, mem in figs.items():
        if c not in FAMOUS:
            for i in mem:
                key[i] = min(key[i], stars[i]['v'] - FIGURE_BONUS)
    for mem in famous_groups(stars, figs).values():
        favour(mem, FAMOUS_BONUS)
    for mem in core_groups(stars, figs, asterisms).values():
        favour(mem, CORE_BONUS)
    return sorted(range(len(stars)), key=lambda i: (key[i], stars[i]['v']))


def needed(stars, order, k=K_MAX):
    """How far down the list the busiest sky reaches for k stars above the horizon."""
    ra = np.radians([stars[i]['ra_e'] for i in order]); de = np.radians([stars[i]['de_e'] for i in order])
    worst = 0
    for lat in np.radians(np.arange(-90, 91, 2.5)):
        for lst in np.radians(np.arange(0, 360, 2.5)):
            sa = np.sin(lat)*np.sin(de) + np.cos(lat)*np.cos(de)*np.cos(lst - ra)
            worst = max(worst, np.nonzero(sa > 0)[0][k - 1] + 1)
    return worst


# Drawing.STAR_BIN_*: yellow 0, soft yellow 1, red 2, blue 3, white 4
def color_bin(bv):
    if bv is None:  return 4
    if bv < -0.02:  return 3     # B and hot A stars: blue        (Rigel, Spica, Regulus)
    if bv < 0.30:   return 4     # A and early F: white           (Sirius, Vega, Altair, Deneb)
    if bv < 0.65:   return 1     # F and early G: soft yellow     (Procyon, Polaris)
    if bv < 1.35:   return 0     # G and K: yellow-amber          (Capella, Pollux, Arcturus)
    return 2                     # late K and M: red-orange       (Aldebaran, Betelgeuse, Antares)


def pack(s):
    ra = int(round(s['ra_e']/360*(1 << RA_BITS))) % (1 << RA_BITS)
    de = min((1 << DEC_BITS) - 1, max(0, int(round((s['de_e'] + 90)/180*((1 << DEC_BITS) - 1)))))
    mg = min((1 << MAG_BITS) - 1, max(0, int(round((s['v'] - MAG0)/MAG_STEP))))
    return (ra << (DEC_BITS + MAG_BITS + COL_BITS)) | (de << (MAG_BITS + COL_BITS)) | (mg << COL_BITS) | color_bin(s['bv'])


def write(stars, order, path):
    n = min(len(order), int(math.ceil(needed(stars, order)*MARGIN)))
    vals = [pack(stars[i]) for i in order[:n]]
    assert 0 <= min(vals) and max(vals) < 2**31
    json.dump(vals, open(path, 'w'), separators=(',', ':'))
    print(f"{path}: {n} stars, faintest {max(stars[i]['v'] for i in order[:n]):.2f}")


if __name__ == '__main__':
    bsc, d3data, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stars = merge(parse(bsc))
    figs = figures(stars, d3data + '/constellations.lines.json')
    asterisms = figures(stars, d3data + '/asterisms.json', strict=False)
    to_epoch(stars)
    write(stars, list(range(len(stars))), out + '/stars_brightest.json')
    write(stars, constellation_order(stars, figs, asterisms), out + '/stars_constellations.json')
