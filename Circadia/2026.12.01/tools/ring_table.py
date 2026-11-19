"""Saturn's ring for Planets.RING_AMOLED and RING_MIP (source/planets.mc).

A 1 px ellipse around the planet's 6 px disc (Planets.DISC_PX): semi-axes
6.6 and 2.64 px, the long axis rising 20 deg to the right, the far side up
(drawn before the disc) and the near side down (drawn after it). The disc
covers pixels x-3..x+2, so its centre, and the ring's, is half a pixel up
and left of the planet's point (x, y). AMOLED: each pixel's share of a 1 px
wide line, from 8x8 samples, in three strengths; pixels under 15% are left
out. MIP: the line's pixels, plain. Far-side pixels the disc covers are
left out.

    pip install numpy
    python3 ring_table.py
"""
import math
import numpy as np

DISC = 6                                  # Planets.DISC_PX
HALF = DISC // 2
C = -0.5 if DISC % 2 == 0 else 0.0        # the disc's centre, from the point's pixel centre
TH = math.radians(20)
A = 5.5 * DISC / 5                        # 5.5 px around a 5 px disc, scaled
B = 0.4 * A
vx, vy = math.cos(TH), -math.sin(TH)      # major axis (screen, y down)
ux, uy = -math.sin(TH), -math.cos(TH)     # minor axis, pointing up-left (the far side)

# The disc's pixels, as offsets from (x, y): DISC x DISC with the corners cut.
SQUARE = {(dx, dy) for dx in range(-HALF, DISC - HALF) for dy in range(-HALF, DISC - HALF)}
CORNERS = {(-HALF, -HALF), (DISC - HALF - 1, -HALF), (-HALF, DISC - HALF - 1), (DISC - HALF - 1, DISC - HALF - 1)}


def pts(front, n=2000):
    ts = np.linspace(0, 2 * math.pi, n, endpoint=False)
    s = np.sin(ts)
    ts = ts[(s < 0) if front else (s >= 0)]   # far side: +u (up); near side: -u
    return np.c_[C + A * np.cos(ts) * vx + B * np.sin(ts) * ux,
                 C + A * np.cos(ts) * vy + B * np.sin(ts) * uy]


def coverage(front, Z=8):
    P = pts(front)
    cov = {}
    sub = (np.arange(Z) + 0.5) / Z - 0.5
    for dy in range(-8, 8):
        for dx in range(-8, 8):
            gx, gy = np.meshgrid(dx + sub, dy + sub)
            g = np.c_[gx.ravel(), gy.ravel()]
            d = np.min(np.hypot(g[:, None, 0] - P[None, :, 0], g[:, None, 1] - P[None, :, 1]), axis=1)
            c = float(np.mean(d <= 0.5))
            if c >= 0.15:
                cov[(dx, dy)] = c
    return cov


def amoled():
    out = []
    for front in (False, True):
        for (dx, dy), c in sorted(coverage(front).items()):
            over = (dx, dy) in SQUARE           # AMOLED draws the corners too, dimmed
            if over and not front:
                continue                        # hidden behind the disc
            out.append((dx, dy, 1 if c < 0.45 else 2 if c < 0.75 else 3, front, over))
    return out


def mip():
    disc = SQUARE - CORNERS
    out = []
    for front in (False, True):
        for q in sorted({(int(math.floor(x + 0.5)), int(math.floor(y + 0.5))) for x, y in pts(front, 720)}):
            if q in disc and not front:
                continue
            out.append((q[0], q[1], 3, front, q in disc))
    return out


def pack(e):
    dx, dy, l, f, o = e
    return (dx + 8) | ((dy + 8) << 4) | (l << 8) | (int(f) << 10) | (int(o) << 11)


if __name__ == "__main__":
    for nm, t in (("AMOLED", amoled()), ("MIP", mip())):
        print(nm, len(t), "pixels")
        print([pack(e) for e in t])
