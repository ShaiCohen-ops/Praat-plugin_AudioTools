# ============================================================
# Praat AudioTools - Pitch_Class_Spectral_Gravity.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Category: SPECTRAL
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# PITCH-CLASS SPECTRAL GRAVITY
#   A pitch collection acts as an attractor field on the spectrum. Energy
#   at frequencies whose pitch class belongs to the collection is kept or
#   emphasised; energy elsewhere is attenuated by how far it lies from the
#   nearest member. The whole spectrum is coloured at once.
#   This is not pitch correction: nothing is tracked, detected or
#   re-tuned. The whole spectrum is coloured at once, so noise, breath,
#   metal, multiphonics and percussion acquire a tonal field while keeping
#   their own identity.
#
#   ENTIRELY NATIVE PRAAT. No Python, no external tools, offline only.
#
# HOW IT WORKS (see also the notes at the end of this header)
#   1. A PERIODIC FILTER ON THE LOG-FREQUENCY AXIS. This is not a CQT and
#      does not pretend to be one: the tonal field is imposed directly on
#      the spectrum as one gain curve, built once on a log grid of 16
#      points per semitone (a Matrix) and applied to every bin with a
#      single lookup. On 10 s of audio that is 0.13 s, against 4.7 s for
#      the same expression evaluated per bin.
#      FIELD SHAPE decides whether that curve is smooth or stepped:
#        Continuous (default)  the pitch-class position is used as it is,
#                              so the gain varies smoothly with frequency:
#                              a smooth periodic field on the log axis,
#                              sampled at 16 points per semitone (that
#                              sampling is the only staircase left, at
#                              1/16 of a semitone).
#        Quantised             the position is snapped to the nearest of
#                              Bands per octave first, so each band holds
#                              one constant gain and the curve becomes a
#                              staircase. This is an aesthetic choice (a
#                              harder, more "tuned-grid" colour), not a
#                              requirement of the method, and narrow steps
#                              can ring.
#   2. PITCH CLASS. For a bin at frequency f:
#        s  = 69 + 12 log2 (f / A4)        MIDI-like semitone position
#        pc = s mod 12                     pitch class, continuous
#      In Quantised field shape, s is first snapped to the nearest of B
#      bands per octave, which makes pc take only B/12 values per
#      semitone.
#   3. ATTRACTION. d = distance in semitones from pc to the NEAREST target
#      pitch class, measured around the circle of 12. Then
#        w      = exp (-d^2 / (2 sigma^2))        sigma = attraction width
#        gain   = emphasis * w - attenuation * (1 - w)      in dB
#        gain   = gain * attraction_strength
#      At 0 % strength every gain is 0 dB, so the processed signal equals
#      the input to within the FFT round-trip (measured 2.8e-16). Note
#      that Normalize output rescales the result when it is on, so the
#      output is identical only with normalisation off. With it off,
#      Dry/Wet = 0 % returns the input bit for bit and nothing is
#      rescaled - a peak above 1.0 is reported, not silently corrected.
#      Because w is Gaussian in semitones, the transition between kept and
#      rejected regions is smooth: no spectral holes, no comb edges.
#      The WIDTH is what decides how strong the effect is. sigma = 0.8 st
#      leaves a pitch class one semitone away at w = 0.46, i.e. only about
#      a third of the nominal attenuation; sigma = 0.35 leaves it at 0.017,
#      i.e. nearly all of it. Since no pitch class of a 7-note scale is
#      more than one semitone from a member, the default is 0.35 and the
#      Info window prints the gain range actually applied.

# LIMITATIONS vs a true CQT / iCQT
#   - Frequency resolution is the FFT's (linear), not constant-Q: low
#     bands are therefore resolved more coarsely in semitone terms than a
#     real CQT would resolve them. Below about 80 Hz one FFT bin can span
#     more than a semitone for short sounds, so gravity there is gentler
#     than the numbers suggest.
#   - The transform is applied to the whole sound at once, so the gain
#     curve is static: a note that changes pitch is not followed.
#   - The original spectral phase of every bin is preserved by the
#     weighting (real and imaginary parts get the same gain). That is
#     correct and cheap, but it does not guarantee that transients survive
#     untouched: a narrow enough spectral notch has a long impulse
#     response and can ring. Wider Attraction width rings less.
#
# USEFUL COMBINATIONS
#   Chromatic + 24 bands/octave is NOT an identity: every semitone is a
#   target, but quarter-tone positions lie 0.5 semitones away and are
#   pulled onto 12-TET, which drags inharmonic and noisy material towards
#   the tempered grid without choosing a key.
#   Quantised + 24 or 48 bands gives a harder, grid-like colour; Continuous
#   is smoother and is what the defaults use.
#
# CHANGELOG
#   v1.1 - The field is continuous by default. v1.0 snapped the pitch-class
#          position to the nearest band before weighting, so the gain curve
#          was a staircase while the header called it continuous; snapping
#          is now the optional "Quantised" field shape, chosen for its
#          harder colour rather than imposed by the method.
#          Redistribution removed: it gathered residual energy from exactly
#          +-1 semitone, which is not "the nearest pitch class" for
#          pentatonic or whole-tone fields, nor for quantised fields whose
#          nearest member can be half a semitone away. Real spectral
#          transport belongs in a later version, not a half-true switch.
#          Header corrected: phase preservation does not guarantee intact
#          transients (a narrow notch rings), and 0 % strength is identical
#          only to within the FFT round trip, and only bit-identical when
#          normalisation is off.
#   v1.0 - first release.
#
# INPUT   one selected Sound (mono or stereo; channels are processed
#         independently and recombined). The original is never modified.
# OUTPUT  <name>_PCGravity, same sample rate, duration and channel count.
# ============================================================

form Pitch-Class Spectral Gravity v1.1
    optionmenu Root: 1
        option C
        option C#
        option D
        option Eb
        option E
        option F
        option F#
        option G
        option Ab
        option A
        option Bb
        option B
    optionmenu Collection: 1
        option Major
        option Natural minor
        option Harmonic minor
        option Whole tone
        option Octatonic 1 (half-whole)
        option Octatonic 2 (whole-half)
        option Pentatonic major
        option Pentatonic minor
        option Chromatic
        option Custom (below)
    sentence Custom_pitch_classes 0 2 3 5 7 8 10
    optionmenu Preset: 2
        option Gentle colouring
        option Tonal field
        option Hard gravity
        option Radical (resonant grid)
        option Quantised grid
        option Custom (use the values below)
    optionmenu Field_shape: 1
        option Continuous (smooth log-frequency field)
        option Quantised to bands (stepped)
    real Attraction_strength 70
    real Attraction_width 0.35
    real Non_target_attenuation_dB 30
    real Dry_wet 100
    boolean Normalize_output 1
    boolean Play_result 1
    boolean Draw_visualization 1
    boolean Advanced_settings 0
endform

# ---- presets: they set the three controls that decide the effect size,
# plus the field shape where it is part of the character. Custom leaves
# the form values untouched. Exact values:
#   name                strength  width   attenuation  field
#   Gentle colouring       40      0.60      18        continuous
#   Tonal field            70      0.35      30        continuous
#   Hard gravity           90      0.20      40        continuous
#   Radical (resonant)    100      0.10      48        continuous
#   Quantised grid         85      0.30      36        quantised
# Radical keeps only the immediate neighbourhood of each member: it is a
# resonant comb rather than a colouring, it thins the sound heavily and it
# can ring, which is the point of it.
if preset = 1
    attraction_strength = 40
    attraction_width = 0.60
    non_target_attenuation_dB = 18
    field_shape = 1
elsif preset = 2
    attraction_strength = 70
    attraction_width = 0.35
    non_target_attenuation_dB = 30
    field_shape = 1
elsif preset = 3
    attraction_strength = 90
    attraction_width = 0.20
    non_target_attenuation_dB = 40
    field_shape = 1
elsif preset = 4
    attraction_strength = 100
    attraction_width = 0.10
    non_target_attenuation_dB = 48
    field_shape = 1
elsif preset = 5
    attraction_strength = 85
    attraction_width = 0.30
    non_target_attenuation_dB = 36
    field_shape = 2
endif
presetName$[1] = "Gentle colouring"
presetName$[2] = "Tonal field"
presetName$[3] = "Hard gravity"
presetName$[4] = "Radical (resonant grid)"
presetName$[5] = "Quantised grid"
presetName$[6] = "Custom"

# ---- advanced defaults ----
lowest_frequency = 40
highest_frequency = 16000
bands_per_octave = 24
reference_A4 = 440
target_emphasis_dB = 6
preserve_below_range = 1
preserve_above_range = 1
if advanced_settings
    beginPause: "Pitch-Class Spectral Gravity - advanced"
        comment: "Analysis range (clamped to the Nyquist frequency)"
        positive: "Lowest frequency", string$ (lowest_frequency)
        positive: "Highest frequency", string$ (highest_frequency)
        comment: "Bands per octave applies to the Quantised field shape only"
        optionmenu: "Bands per octave", 2
            option: "12"
            option: "24"
            option: "36"
            option: "48"
        positive: "Reference A4", string$ (reference_A4)
        comment: "Attraction (width and attenuation are on the main form)"
        real: "Target emphasis dB", string$ (target_emphasis_dB)
        comment: "Outside the analysis range"
        boolean: "Preserve below range", preserve_below_range
        boolean: "Preserve above range", preserve_above_range
    advClicked = endPause: "Cancel", "Continue", 2, 1
    if advClicked = 1
        exitScript: "Cancelled."
    endif
    bpoChoice$[1] = "12"
    bpoChoice$[2] = "24"
    bpoChoice$[3] = "36"
    bpoChoice$[4] = "48"
    bands_per_octave = number (bpoChoice$[bands_per_octave])
endif

# ============================================================
# VALIDATION
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound object."
endif
sound = selected ("Sound")
soundName$ = selected$ ("Sound")
selectObject: sound
duration = Get total duration
sr = Get sampling frequency
nChan = Get number of channels
xmin = Get start time
srcPeak = Get absolute extremum: 0, 0, "None"
nyquist = sr / 2

if duration <= 0
    exitScript: "The selected Sound has no duration."
endif
if srcPeak <= 0
    exitScript: "The selected Sound is silent: there is no spectrum to colour."
endif
if attraction_strength < 0 or attraction_strength > 100
    exitScript: "Attraction strength must be between 0 and 100 %."
endif
if dry_wet < 0 or dry_wet > 100
    exitScript: "Dry/Wet must be between 0 and 100 %."
endif
if attraction_width < 0.05 or attraction_width > 6
    exitScript: "Attraction width must be between 0.05 and 6 semitones."
endif
if target_emphasis_dB < 0 or target_emphasis_dB > 24
    exitScript: "Target emphasis must be between 0 and 24 dB."
endif
if non_target_attenuation_dB < 0 or non_target_attenuation_dB > 60
    exitScript: "Non-target attenuation must be between 0 and 60 dB."
endif
if reference_A4 < 380 or reference_A4 > 500
    exitScript: "Reference A4 must be between 380 and 500 Hz."
endif
if lowest_frequency < 10
    lowest_frequency = 10
endif
if highest_frequency > nyquist - 1
    highest_frequency = nyquist - 1
endif
if lowest_frequency >= highest_frequency
    exitScript: "Lowest frequency must be below highest frequency (Nyquist here is " + fixed$ (nyquist, 0) + " Hz)."
endif

# ---- target pitch classes ----
rootName$[1] = "C"
rootName$[2] = "C#"
rootName$[3] = "D"
rootName$[4] = "Eb"
rootName$[5] = "E"
rootName$[6] = "F"
rootName$[7] = "F#"
rootName$[8] = "G"
rootName$[9] = "Ab"
rootName$[10] = "A"
rootName$[11] = "Bb"
rootName$[12] = "B"
collName$[1] = "Major"
collName$[2] = "Natural minor"
collName$[3] = "Harmonic minor"
collName$[4] = "Whole tone"
collName$[5] = "Octatonic 1 (half-whole)"
collName$[6] = "Octatonic 2 (whole-half)"
collName$[7] = "Pentatonic major"
collName$[8] = "Pentatonic minor"
collName$[9] = "Chromatic"
collName$[10] = "Custom"
coll$[1] = "0 2 4 5 7 9 11"
coll$[2] = "0 2 3 5 7 8 10"
coll$[3] = "0 2 3 5 7 8 11"
coll$[4] = "0 2 4 6 8 10"
coll$[5] = "0 1 3 4 6 7 9 10"
coll$[6] = "0 2 3 5 6 8 9 11"
coll$[7] = "0 2 4 7 9"
coll$[8] = "0 3 5 7 10"
coll$[9] = "0 1 2 3 4 5 6 7 8 9 10 11"

rootPc = root - 1
if collection = 10
    pcList$ = custom_pitch_classes$
else
    pcList$ = coll$[collection]
endif
pcList$ = replace$ (pcList$, ",", " ", 0)
pcList$ = replace$ (pcList$, ";", " ", 0)
nTarget = 0
rest$ = pcList$ + " "
while index (rest$, " ") > 0
    piece$ = left$ (rest$, index (rest$, " ") - 1)
    rest$ = mid$ (rest$, index (rest$, " ") + 1, length (rest$))
    if piece$ <> ""
        v = number (piece$)
        if v = undefined
            exitScript: "Pitch classes must be numbers 0-11 separated by spaces: '" + piece$ + "' is not."
        endif
        v = round (v)
        if v < 0 or v > 11
            exitScript: "Pitch classes must be between 0 and 11: " + string$ (v) + " is out of range."
        endif
        # transpose by the root, and ignore duplicates
        v = (v + rootPc) mod 12
        known = 0
        for k to nTarget
            if targetPc[k] = v
                known = 1
            endif
        endfor
        if known = 0
            nTarget += 1
            targetPc[nTarget] = v
        endif
    endif
endwhile
if nTarget = 0
    exitScript: "The pitch collection is empty. Give at least one pitch class (0-11)."
endif
if nTarget = 12
    appendInfoLine: ""
endif

strength = attraction_strength / 100
wet = dry_wet / 100
continuousField = field_shape = 1

clearinfo
writeInfoLine: "=== Pitch-Class Spectral Gravity v1.1 ==="
appendInfoLine: "Input: ", soundName$, "  (", fixed$ (duration, 3), " s, ", nChan, " ch @ ", sr, " Hz)"
pcShow$ = ""
for k to nTarget
    pcShow$ = pcShow$ + rootName$[targetPc[k] + 1] + " "
endfor
appendInfoLine: "Field: ", rootName$[root], " ", collName$[collection], "   pitch classes: ", pcShow$
appendInfoLine: "Preset: ", presetName$[preset]
appendInfoLine: "Attraction: ", fixed$ (attraction_strength, 0), " %   width ", fixed$ (attraction_width, 2),
    ... " st   emphasis +", fixed$ (target_emphasis_dB, 1), " dB   attenuation -", fixed$ (non_target_attenuation_dB, 1), " dB"
appendInfoLine: "Field: ", if continuousField then "continuous (smooth)" else "quantised to " + string$ (bands_per_octave) + " bands/octave" fi, ", ", fixed$ (lowest_frequency, 0), "-", fixed$ (highest_frequency, 0),
    ... " Hz, A4 = ", fixed$ (reference_A4, 1), " Hz"
appendInfoLine: ""

# ============================================================
# GAIN CURVE
#   Built once on a log grid (16 points per semitone) as a Matrix, then
#   applied to every bin with one lookup. gridF(i) = fLo * 2^((i-1)/(12*P))
# ============================================================
ppst = 16
gridLo = max (10, lowest_frequency * 0.5)
nPts = ceiling (12 * ppst * ln (nyquist / gridLo) / ln (2)) + 2

# --- semitone position -> band snap -> pitch class, as a formula string ---
fExpr$ = "69 + 12*ln(" + string$ (gridLo) + "*2^((col-1)/(12*" + string$ (ppst) + "))/" + string$ (reference_A4) + ")/ln(2)"
if continuousField
    # no snapping: the pitch-class position is used as it is, so the gain
    # varies smoothly with frequency
    bExpr$ = "(" + fExpr$ + ")"
else
    bExpr$ = "round((" + fExpr$ + ")*" + string$ (bands_per_octave / 12) + ")/" + string$ (bands_per_octave / 12)
endif
pcExpr$ = "((" + bExpr$ + ") - 12*floor((" + bExpr$ + ")/12))"
# --- distance to the nearest target pitch class, around the circle ---
dExpr$ = ""
for k to nTarget
    dk$ = "abs((" + pcExpr$ + ") - " + string$ (targetPc[k]) + ")"
    one$ = "min(" + dk$ + ", 12 - " + dk$ + ")"
    if k = 1
        dExpr$ = one$
    else
        dExpr$ = "min(" + dExpr$ + ", " + one$ + ")"
    endif
endfor
wExpr$ = "exp(-((" + dExpr$ + ")^2)/(2*" + string$ (attraction_width) + "^2))"
gainDbExpr$ = "(" + string$ (target_emphasis_dB) + "*(" + wExpr$ + ") - "
    ... + string$ (non_target_attenuation_dB) + "*(1-(" + wExpr$ + ")))*" + string$ (strength)
# --- outside the analysis range: preserved (0 dB) or treated as non-target ---
fOfCol$ = string$ (gridLo) + "*2^((col-1)/(12*" + string$ (ppst) + "))"
belowExpr$ = if preserve_below_range then "0" else "(-" + string$ (non_target_attenuation_dB) + "*" + string$ (strength) + ")" fi
aboveExpr$ = if preserve_above_range then "0" else "(-" + string$ (non_target_attenuation_dB) + "*" + string$ (strength) + ")" fi
fullDbExpr$ = "if " + fOfCol$ + " < " + string$ (lowest_frequency) + " then " + belowExpr$
    ... + " else if " + fOfCol$ + " > " + string$ (highest_frequency) + " then " + aboveExpr$
    ... + " else " + gainDbExpr$ + " fi fi"

gainMat = Create simple Matrix: "pcg_gain", 1, nPts, "0"
Formula: "10^((" + fullDbExpr$ + ")/20)"
# the same curve in dB, and the rejection curve (1 - w), for the drawing
# (used by the drawing)
dbMat = Create simple Matrix: "pcg_db", 1, nPts, "0"
Formula: fullDbExpr$

# Read the extremes off the curve that will actually be applied, inside
# the analysis range. Deriving them from the 12 whole pitch classes was
# wrong wherever the field is interesting: in Chromatic every pitch class
# IS a target (so it reported 0 semitones) while the point midway between
# two of them is half a semitone away, and a pentatonic gap of three
# semitones has its midpoint 1.5 semitones from any member.
maxBoost = -1000
maxCut = 1000
colLo = max (1, min (nPts, round (1 + 12 * ppst * ln (lowest_frequency / gridLo) / ln (2))))
colHi = max (1, min (nPts, round (1 + 12 * ppst * ln (highest_frequency / gridLo) / ln (2))))
for .c from colLo to colHi
    .v = object [dbMat, 1, .c]
    if .v > maxBoost
        maxBoost = .v
    endif
    if .v < maxCut
        maxCut = .v
    endif
endfor
appendInfoLine: "Gain range actually applied (measured from the curve): +", fixed$ (maxBoost, 1),
    ... " dB to ", fixed$ (maxCut, 1), " dB"
if maxCut > -6 and maxBoost < 12
    appendInfoLine: "  NOTE: that is a gentle setting. For a clearly audible effect narrow the"
    appendInfoLine: "  Attraction width (0.3-0.4 st) or raise the attenuation / attraction strength."
endif
# lookup index for a bin at frequency x (clamped to the grid)
lookup$ = "max(1, min(" + string$ (nPts) + ", round(1 + 12*" + string$ (ppst) + "*ln(max(x,"
    ... + string$ (gridLo) + ")/" + string$ (gridLo) + ")/ln(2))))"

# ============================================================
# PROCESS (per channel, Spectrum domain)
# ============================================================
appendInfoLine: "Processing ", nChan, " channel(s)..."
stopwatch
for ch to nChan
    selectObject: sound
    if nChan > 1
        chan[ch] = Extract one channel: ch
    else
        chan[ch] = Copy: "pcg_chan"
    endif
    spec = To Spectrum: "yes"
    Formula: "self * object[" + string$ (gainMat) + ", 1, " + lookup$ + "]"
    # keep the input spectrum of channel 1 for the figure
    if ch = 1 and draw_visualization
        selectObject: chan[ch]
        vizInSpec = To Spectrum: "yes"
        Rename: "pcg_viz_in"
    endif
    selectObject: spec
    wetChan[ch] = To Sound
    Rename: "pcg_wet" + string$ (ch)
    removeObject: spec
    # To Sound pads to the FFT length: trim back to the original duration
    selectObject: wetChan[ch]
    wdur = Get total duration
    if wdur > duration + 1e-9
        trimmed = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: wetChan[ch]
        wetChan[ch] = trimmed
        Rename: "pcg_wet" + string$ (ch)
    endif
    if ch = 1 and draw_visualization
        selectObject: wetChan[ch]
        vizOutSpec = To Spectrum: "yes"
        Rename: "pcg_viz_out"
    endif
endfor
procTime = stopwatch
appendInfoLine: "  spectral pass: ", fixed$ (procTime, 2), " s"

# ---- reassemble, then dry/wet ----
if nChan > 1
    selectObject: wetChan[1]
    for ch from 2 to nChan
        plusObject: wetChan[ch]
    endfor
    wetSound = Combine to stereo
    Rename: "pcg_wet_all"
else
    selectObject: wetChan[1]
    wetSound = Copy: "pcg_wet_all"
endif
for ch to nChan
    removeObject: chan[ch], wetChan[ch]
endfor
selectObject: wetSound
Shift times to: "start time", xmin

selectObject: sound
result = Copy: soundName$ + "_PCGravity"
if wet >= 1
    Formula: "object[" + string$ (wetSound) + ", row, col]"
elsif wet > 0
    Formula: string$ (1 - wet) + "*self + " + string$ (wet) + "*object[" + string$ (wetSound) + ", row, col]"
endif
selectObject: result
outPeak = Get absolute extremum: 0, 0, "None"
normNote$ = "off"
# "off" means the amplitude is not touched at all: a Praat Sound may hold
# values above 1, and silently rescaling would make Dry/Wet = 0 %, or
# Attraction = 0 %, fail to return the input unchanged.
if normalize_output and outPeak > 0
    Scale peak: 0.99
    normNote$ = "peak scaled to 0.99 (was " + fixed$ (outPeak, 3) + ")"
elsif outPeak > 1
    normNote$ = "off - WARNING: peak is " + fixed$ (outPeak, 3) + " (above 1.0; it will clip on playback or on saving to an integer format)"
else
    normNote$ = "off"
endif
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Output: ", soundName$, "_PCGravity   (", nChan, " ch, ", fixed$ (duration, 3), " s @ ", sr, " Hz)"
appendInfoLine: "Dry/Wet: ", fixed$ (dry_wet, 0), " %   normalisation: ", normNote$, "   peak ", fixed$ (finalPeak, 3)

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    @createVisualization
    removeObject: vizInSpec, vizOutSpec
endif

removeObject: wetSound, gainMat, dbMat
selectObject: result
if play_result
    asynchronous Play
endif
selectObject: result

# ============================================================
# PROCEDURES
# ============================================================
# "#" opens bold markup in Praat Picture text, so C# / F# must be escaped
# before they are drawn (the Info window needs no escaping).
procedure drawSafe: .s$
    .result$ = replace$ (.s$, "#", "\# ", 0)
endproc

procedure createVisualization
    cPrim$ = "{0.20, 0.48, 0.75}"
    cSec$ = "{0.85, 0.38, 0.18}"
    cGrey$ = "{0.55, 0.55, 0.60}"
    cGround$ = "{0.97, 0.97, 0.97}"
    cGrid$ = "{0.80, 0.80, 0.80}"
    cSub$ = "{0.35, 0.35, 0.50}"
    cSum$ = "{0.25, 0.25, 0.35}"
    cTarget$ = "{0.86, 0.91, 0.97}"
    .nm$ = replace$ (soundName$, "_", "\_ ", 0)
    Erase all

    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Pitch-Class Spectral Gravity##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: cSub$
    @drawSafe: rootName$[root]
    .rootSafe$ = drawSafe.result$
    @drawSafe: pcShow$
    .pcSafe$ = drawSafe.result$
    Text: 0.5, "centre", 0.22, "half", .nm$ + "   |   " + .rootSafe$ + " " + collName$[collection]
        ... + "   |   " + presetName$[preset] + ": " + fixed$ (attraction_strength, 0) + " \% , width " + fixed$ (attraction_width, 2) + " st"
        ... + "   |   " + if continuousField then "continuous field" else string$ (bands_per_octave) + " bands/octave" fi + "   |   dry/wet " + fixed$ (dry_wet, 0) + " \% "

    # ---- A: the pitch-class field ----
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Axes: -0.5, 11.5, -1.05, 1.15
    Paint rectangle: cGround$, -0.5, 11.5, -1.05, 1.15
    for .p from 0 to 11
        .isT = 0
        for .k to nTarget
            if targetPc[.k] = .p
                .isT = 1
            endif
        endfor
        pcIsTarget[.p] = .isT
        # distance to the nearest target, and the resulting weight
        .d = 12
        for .k to nTarget
            .dd = abs (.p - targetPc[.k])
            .dd = min (.dd, 12 - .dd)
            .d = min (.d, .dd)
        endfor
        pcDist[.p] = .d
        .w = exp (-(.d ^ 2) / (2 * attraction_width ^ 2))
        pcW[.p] = .w
        pcDb[.p] = (target_emphasis_dB * .w - non_target_attenuation_dB * (1 - .w)) * strength
    endfor
    .dbMaxAbs = max (target_emphasis_dB, non_target_attenuation_dB) * max (strength, 0.001)
    if .dbMaxAbs < 1
        .dbMaxAbs = 1
    endif
    for .p from 0 to 11
        if pcIsTarget[.p]
            Paint rectangle: cTarget$, .p - 0.46, .p + 0.46, -1.05, 1.15
        endif
        .h = pcDb[.p] / .dbMaxAbs
        if pcDb[.p] >= 0
            Paint rectangle: cPrim$, .p - 0.30, .p + 0.30, 0, .h
        else
            Paint rectangle: cSec$, .p - 0.30, .p + 0.30, .h, 0
        endif
    endfor
    Colour: cGrid$
    Draw line: -0.5, 0, 11.5, 0
    # arrows: each non-target points at its nearest target
    Colour: "{0.45, 0.45, 0.52}"
    Line width: 1
    for .p from 0 to 11
        if pcIsTarget[.p] = 0
            .best = 0
            .bd = 12
            for .k to nTarget
                .dd = abs (.p - targetPc[.k])
                .dd = min (.dd, 12 - .dd)
                if .dd < .bd
                    .bd = .dd
                    .best = targetPc[.k]
                endif
            endfor
            .dir = 1
            if (.best - .p + 12) mod 12 > 6
                .dir = -1
            endif
            .x1 = .p + .dir * 0.34
            .x2 = .p + .dir * 0.66
            Draw arrow: .x1, -0.80, .x2, -0.80
        endif
    endfor
    Line width: 1
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Axes: -0.5, 11.5, -1.05, 1.15
    Colour: "Black"
    Draw inner box
    for .p from 0 to 11
        if pcIsTarget[.p]
            @drawSafe: rootName$[.p + 1]
            Colour: "Black"
            One mark bottom: .p, "no", "yes", "no", "##" + drawSafe.result$ + "##"
        else
            @drawSafe: rootName$[.p + 1]
            Colour: "{0.45, 0.45, 0.52}"
            One mark bottom: .p, "no", "yes", "no", drawSafe.result$
        endif
    endfor
    Colour: "Black"
    Marks left every: 1, 0.5, "no", "yes", "no"
    Text left: "yes", "gain (relative)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Text top: "no", "##A   Pitch-class field##   shaded = in the collection; bars = applied gain; arrows = attraction direction"

    # ---- B: the gain curve actually applied ----
    Font size: 7
    Select inner viewport: 0.60, 7.70, 2.85, 4.15
    .fLoDraw = max (lowest_frequency * 0.7, 20)
    .fHiDraw = min (highest_frequency * 1.3, nyquist)
    .octaves = ln (.fHiDraw / .fLoDraw) / ln (2)
    .dbLo = -max (1, non_target_attenuation_dB * strength) * 1.15
    .dbHi = max (1, target_emphasis_dB * strength) * 1.15 + 0.5
    Axes: 0, .octaves, .dbLo, .dbHi
    Paint rectangle: cGround$, 0, .octaves, .dbLo, .dbHi
    Colour: cGrid$
    Draw line: 0, 0, .octaves, 0
    # the curve, read from the dB Matrix at 8 points per semitone
    Colour: cPrim$
    Line width: 1.5
    .steps = round (.octaves * 12 * 8)
    for .i from 1 to .steps
        .o1 = (.i - 1) / (12 * 8)
        .o2 = .i / (12 * 8)
        .f1 = .fLoDraw * 2 ^ .o1
        .f2 = .fLoDraw * 2 ^ .o2
        .c1 = max (1, min (nPts, round (1 + 12 * ppst * ln (.f1 / gridLo) / ln (2))))
        .c2 = max (1, min (nPts, round (1 + 12 * ppst * ln (.f2 / gridLo) / ln (2))))
        .v1 = object [dbMat, 1, .c1]
        .v2 = object [dbMat, 1, .c2]
        Draw line: .o1, .v1, .o2, .v2
    endfor
    Line width: 1
    Select inner viewport: 0.60, 7.70, 2.85, 4.15
    Axes: 0, .octaves, .dbLo, .dbHi
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max (1, round (.dbHi - .dbLo) / 4), "yes", "yes", "no"
    .oct = 0
    while .oct <= .octaves
        .f = .fLoDraw * 2 ^ .oct
        One mark bottom: .oct, "no", "yes", "no", fixed$ (.f, 0)
        .oct += 1
    endwhile
    Text left: "yes", "gain (dB)"
    Text bottom: "yes", "frequency (Hz, log)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 2.85, 4.15
    Text top: "no", "##B   Applied gain curve##   " + if continuousField then "smooth log-frequency field, sampled at 16 points per semitone" else "quantised to " + string$ (bands_per_octave) + " bands per octave" fi

    # ---- C: what it did to the spectrum (channel 1) ----
    Font size: 7
    Select inner viewport: 0.60, 7.70, 4.65, 5.95
    selectObject: vizInSpec
    .ltasIn = To Ltas (1-to-1)
    selectObject: vizOutSpec
    .ltasOut = To Ltas (1-to-1)
    .peakDb = -400
    .oct2 = ln (.fHiDraw / .fLoDraw) / ln (2)
    .steps2 = round (.oct2 * 12 * 4)
    for .i from 0 to .steps2
        .f = .fLoDraw * 2 ^ (.i / (12 * 4))
        selectObject: .ltasIn
        .v = Get value at frequency: .f, "Linear"
        if .v <> undefined and .v > .peakDb
            .peakDb = .v
        endif
    endfor
    .top = .peakDb + 6
    .bot = .peakDb - 60
    Axes: 0, .oct2, .bot, .top
    Paint rectangle: cGround$, 0, .oct2, .bot, .top
    Colour: cGrey$
    Line width: 1
    for .i from 1 to .steps2
        .o1 = (.i - 1) / (12 * 4)
        .o2 = .i / (12 * 4)
        selectObject: .ltasIn
        .a = Get value at frequency: .fLoDraw * 2 ^ .o1, "Linear"
        .b = Get value at frequency: .fLoDraw * 2 ^ .o2, "Linear"
        if .a <> undefined and .b <> undefined
            Select inner viewport: 0.60, 7.70, 4.65, 5.95
            Axes: 0, .oct2, .bot, .top
            Colour: cGrey$
            Draw line: .o1, max (.bot, .a), .o2, max (.bot, .b)
        endif
    endfor
    Colour: cPrim$
    Line width: 1.5
    for .i from 1 to .steps2
        .o1 = (.i - 1) / (12 * 4)
        .o2 = .i / (12 * 4)
        selectObject: .ltasOut
        .a = Get value at frequency: .fLoDraw * 2 ^ .o1, "Linear"
        .b = Get value at frequency: .fLoDraw * 2 ^ .o2, "Linear"
        if .a <> undefined and .b <> undefined
            Select inner viewport: 0.60, 7.70, 4.65, 5.95
            Axes: 0, .oct2, .bot, .top
            Colour: cPrim$
            Draw line: .o1, max (.bot, .a), .o2, max (.bot, .b)
        endif
    endfor
    removeObject: .ltasIn, .ltasOut
    Line width: 1
    Select inner viewport: 0.60, 7.70, 4.65, 5.95
    Axes: 0, .oct2, .bot, .top
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    .oct = 0
    while .oct <= .oct2
        One mark bottom: .oct, "no", "yes", "no", fixed$ (.fLoDraw * 2 ^ .oct, 0)
        .oct += 1
    endwhile
    Text left: "yes", "dB"
    Text bottom: "yes", "frequency (Hz, log)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 4.65, 5.95
    Text top: "no", "##C   Spectrum, channel 1##   grey = input, blue = output (long-term average)"

    # ---- summary ----
    Font size: 6
    Select inner viewport: 0.60, 7.70, 6.45, 7.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: cSum$
    Text: 0.01, "left", 0.80, "half", "##Field:## " + .rootSafe$ + " " + collName$[collection] + " = " + .pcSafe$
        ... + "   ##Attraction:## " + fixed$ (attraction_strength, 0) + " \%  at width " + fixed$ (attraction_width, 2)
        ... + " st, emphasis +" + fixed$ (target_emphasis_dB, 1) + " dB, attenuation \-- " + fixed$ (non_target_attenuation_dB, 1) + " dB"
    Text: 0.01, "left", 0.50, "half", "##Field:## " + if continuousField then "continuous" else "quantised, " + string$ (bands_per_octave) + " bands/octave" fi + ", " + fixed$ (lowest_frequency, 0) + "\--" + fixed$ (highest_frequency, 0)
        ... + " Hz, A4 = " + fixed$ (reference_A4, 1) + " Hz, applied in the Spectrum domain (one gain curve, no band Sounds)"
    Text: 0.01, "left", 0.20, "half", "##Not pitch correction:## nothing is tracked or re-tuned \-- the whole spectrum is weighted by distance to the collection, so noisy and inharmonic material keeps its identity."
    Select inner viewport: 0.60, 7.70, 6.45, 7.15
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Line width: 1
    Select outer viewport: 0, 8, 0, 7.2
endproc
