// Single source of truth for every named colour in the watch face.
//
// MIP devices (Forerunner 2xx 3xx 9xx series, Fenix MIP variants, Tactix,
// Enduro) only support a 64-colour palette: the 4×4×4 grid where each of
// R, G, B can be one of {0x00, 0x55, 0xAA, 0xFF}. Off-palette colours are
// silently rounded by the firmware, sometimes unpredictably.
//
// MIP solar palette is structured as three rings per band. Daytime is a
// pure yellow dark→medium→bright ramp; transition bands carry the previous
// band's bright hue as the new core. See the comment block in the module
// for the full table. Moon palette is unchanged from the user's tuning.
module Colours {

    // ── Universal ────────────────────────────────────────────────────────
    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    // ── AMOLED solar palette (smoothly blended between altitude bands) ──
    const SUN_YELLOW  = 0xFFFF00;
    const SUN_ORANGE  = 0xFFAA00;
    const SUN_RED     = 0xFF0000;
    const SUN_PURPLE  = 0xD060FF;
    const SUN_BLUE    = 0x5F6FFF;

    // ── MIP solar palette ──────────────────────────────────────────────
    // The MIP sun draws three concentric rings (outer → middle → core).
    // Each band's outer and middle come from its own MEDIUM/BRIGHT, and
    // the core is the BRIGHT shade of the *next-warmer* band:
    //
    //   Sun (≥ 6°)    : SUN_MEDIUM     SUN_BRIGHT     WHITE
    //   Orange (≥ 0°) : ORANGE_MEDIUM  ORANGE_BRIGHT  SUN_BRIGHT
    //   Red    (≥-6°) : RED_MEDIUM     RED_BRIGHT     ORANGE_BRIGHT
    //   Purple (≥-12°): PURPLE_MEDIUM  PURPLE_BRIGHT  RED_BRIGHT
    //   Blue   (else) : BLUE_MEDIUM    BLUE_BRIGHT    BLUE_BRIGHT
    //
    // Minute text matches the band's BRIGHT, whitened by the saturation
    // slider. All values are on the 64-colour MIP palette.
    const MIP_SUN_BRIGHT    = 0xFFFF00;   // pure yellow
    const MIP_SUN_MEDIUM    = 0xAAAA00;   // ochre

    const MIP_ORANGE_BRIGHT = 0xFFAA00;   // pure on-palette orange
    const MIP_ORANGE_MEDIUM = 0xAA5500;   // burnt amber

    const MIP_RED_BRIGHT    = 0xFF0000;   // pure red
    const MIP_RED_MEDIUM    = 0xAA0000;   // dark red

    const MIP_PURPLE_BRIGHT = 0xFF55FF;   // magenta-pink
    const MIP_PURPLE_MEDIUM = 0xAA00AA;   // saturated purple

    const MIP_BLUE_BRIGHT   = 0x55AAFF;   // pale blue (echoes AMOLED 0x5F6FFF)
    const MIP_BLUE_MEDIUM   = 0x0055AA;   // medium blue

    // ── Moon ───────────────────────────────────────────────────────────
    const MOON_AMOLED       = 0xC8CDD3;   // soft silver disc on AMOLED
    const MIP_MOON_BRIGHT   = 0xAAAAAA;
    const MIP_MOON_MEDIUM   = 0x808080;
    const MIP_MOON_DARK     = 0x555555;

    // ── Stars (colour-bin lookup; same on AMOLED and MIP) ─────────────
    const STAR_YELLOW       = 0xFDEBD2;
    const STAR_SOFT_YELLOW  = 0xFFF6D8;
    const STAR_RED          = 0xFFB08A;
    const STAR_BLUE         = 0xC9D8FF;
    const STAR_WHITE        = 0xF4F4FF;

    // ── Accents ─────────────────────────────────────────────────────────
    const SUNSET_ACCENT     = 0xFF8000;   // tinges the hour text near sunrise/sunset
    const CHARGING          = 0xFFFF00;   // battery field foreground when charging

}
