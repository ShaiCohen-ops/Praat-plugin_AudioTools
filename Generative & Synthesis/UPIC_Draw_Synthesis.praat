# ============================================================
# Praat AudioTools - UPIC_Draw_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# UPIC -> STOCHASTIC MASS -> GENDYN, from one drawing (pure Praat)
#
#   The drawing interface is v1's: per arc a PITCH ARC (macro), a WAVEFORM
#   POLYGON (micro) and a dB ENVELOPE. What changes is the REALIZATION: the
#   same drawing can sound as a line, a mass, or a living stochastic mass.
#
#   REALIZATION (per arc; R cycles it)
#     Line             one voice on the drawn arc (UPIC).
#     Mass             N voices around the arc (Xenakis sound mass):
#                        f_i(t) = 2^( L(t) + g_i (L(t) - L0) + c_i / 1200 )
#                      L = drawn log2 frequency, L0 = its first vertex,
#                      c_i = static pitch offset (stratified over +-spread),
#                      g_i = glissando dispersion: every member bends the
#                      drawn glissando by its own factor, pivoting on the
#                      first vertex -> a fan / wedge; mean g_i = 0 exactly,
#                      so the population's centre follows the drawn line.
#                      Random start phases, onset scatter, gain scatter.
#     Stochastic Mass  Mass + a correlated drift per member (cents):
#                        D_i(t + dt) = rho D_i(t) + sigma sqrt(1-rho^2) e
#                      (stationary std = sigma = spread / 2).
#
#   GENDYN LAYER (any realization)
#     The drawn polygon is not a frozen wavetable but an ATTRACTOR. Per
#     member, every breakpoint amplitude A_k and phase position P_k walks
#     (Ornstein-Uhlenbeck, i.e. random step + pull back to the drawing):
#       A_k(t + dt) = A_drawn,k + rho (A_k(t) - A_drawn,k) + sA sqrt(1-rho^2) e
#     pull per frame = 1 - rho; stationary std = sA (mutation) / sP (drift).
#     Positions stay ordered inside the cycle. The walks are baked into a
#     phase x time wavetable per member (one bilinear lookup per sample).
#
#   DENSITY: the envelope can also set how many members sound:
#       N_active(t) = max(1, N * 10^(coupling * min(0, dB) / 40))
#     (16 voices: -24 dB -> 4, -12 dB -> 8, 0 dB -> 16). Members enter in
#     order of distance from the drawn line: thin line -> thick line -> mass.
#   REGISTER FIELD: decides WHICH members of the population exist over time
#     (hollow centre, low->high, high->low, moving window, alternating
#     bands). It shapes the distribution, it is not a filter / EQ.
#   ROUGHNESS is structural, not a noise knob: mutation, drift and jitter
#     are scaled by (1 + 2 R), R = (spread / 200 cents, max 1) x (active
#     fraction). Wide + dense masses become rougher by their own disorder.
#   ENERGY: each population is scaled 1/sqrt(N) (plus gain scatter); the
#     mix is NOT normalised - only a peak guard (scale to 0.99 if above),
#     so a large mass and a thin line keep their real level difference.
#
# INTERACTION (as v1)
#   Click add/move   U undo   1..6 arc   Tab/M pitch<->waveform
#   R realization of the current arc   Enter commit + play arc
#   F finish + mix   Esc cancel. Click the Demo window once for focus.
#
# HONEST LIMITS
#   - Drawings are polygons of clicked vertices (no freehand), no live audio
#     while drawing, max 6 arcs, one fixed time axis (as v1).
#   - Piecewise-linear cycles alias at high pitch (not band-limited).
#   - Mass rendering costs about (voices x arcs) times a Line render; the
#     form refuses workloads over 1600 voice-seconds.
#   - The editor shows the static fan (offsets + dispersion); stochastic
#     drift, onset/gain scatter, density and register are heard, and shown
#     after rendering in the result spectrogram.
#
# Changelog v2.0:
#   - NEW realization engine (Line / Mass / Stochastic Mass, per arc),
#     GENDYN attractor mutation of the drawn polygon, density coupling,
#     register field, structural roughness, equal-power stereo mass width,
#     1/sqrt(N) energy + peak guard, seeded and reproducible.
#   - Presets: UPIC Pure / Xenakis Mass / GENDYN Mass.
#   - Editor shows the mass fan and the waveform attractor cloud; result view
#     shows the spectrogram of the mix under the drawn arcs.
#   - Changed from v1: the mix is no longer normalised (peak guard only).
# Changelog v1.0: initial drawn-arc + micro-waveform + envelope version.
# ============================================================

form UPIC Draw Synthesis v2.0
    optionmenu Preset 1
        option Custom
        option UPIC Pure
        option Xenakis Mass
        option GENDYN Mass
    positive Duration_s 8
    integer Number_of_arcs 4
    positive Lowest_frequency_Hz 55
    positive Highest_frequency_Hz 1760
    optionmenu Sample_rate 2
        option 22050
        option 44100
    optionmenu Realization 3
        option Line
        option Mass
        option Stochastic Mass
    integer Mass_voices_per_arc 12
    integer Random_seed 12345
    boolean Edit_mass_and_GENDYN_details 0
    boolean Keep_individual_arcs 0
endform

# ---------------------------------------------------------------------------
# DETAIL DEFAULTS (Custom) + PRESETS
# ---------------------------------------------------------------------------
pitch_spread_cents = 80
glissando_dispersion_percent = 25
onset_scatter_ms = 30
gain_scatter_dB = 3
waveform_mutation_percent = 20
breakpoint_drift_percent = 5
mutation_correlation = 0.90
mutation_rate_Hz = 25
envelope_density_coupling_percent = 50
register_field = 1
stereo_mass_width_percent = 70
preset_name$ = "Custom"

if preset = 2
    preset_name$ = "UPIC Pure"
    realization = 1
    mass_voices_per_arc = 1
    pitch_spread_cents = 0
    glissando_dispersion_percent = 0
    onset_scatter_ms = 0
    gain_scatter_dB = 0
    waveform_mutation_percent = 0
    breakpoint_drift_percent = 0
    envelope_density_coupling_percent = 0
    stereo_mass_width_percent = 0
elsif preset = 3
    preset_name$ = "Xenakis Mass"
    realization = 2
    mass_voices_per_arc = 16
    pitch_spread_cents = 80
    glissando_dispersion_percent = 25
    onset_scatter_ms = 30
    gain_scatter_dB = 3
    waveform_mutation_percent = 0
    breakpoint_drift_percent = 0
    envelope_density_coupling_percent = 50
    stereo_mass_width_percent = 70
elsif preset = 4
    preset_name$ = "GENDYN Mass"
    realization = 3
    mass_voices_per_arc = 16
    pitch_spread_cents = 60
    glissando_dispersion_percent = 25
    onset_scatter_ms = 30
    gain_scatter_dB = 3
    waveform_mutation_percent = 20
    breakpoint_drift_percent = 5
    mutation_correlation = 0.90
    mutation_rate_Hz = 25
    envelope_density_coupling_percent = 50
    stereo_mass_width_percent = 70
endif

if edit_mass_and_GENDYN_details
    beginPause: "UPIC v2 - mass and GENDYN details (" + preset_name$ + ")"
        comment: "Mass"
        real: "Pitch spread cents", string$ (pitch_spread_cents)
        real: "Glissando dispersion percent", string$ (glissando_dispersion_percent)
        real: "Onset scatter ms", string$ (onset_scatter_ms)
        real: "Gain scatter dB", string$ (gain_scatter_dB)
        comment: "GENDYN layer (waveform attractor)"
        real: "Waveform mutation percent", string$ (waveform_mutation_percent)
        real: "Breakpoint drift percent", string$ (breakpoint_drift_percent)
        real: "Mutation correlation", string$ (mutation_correlation)
        positive: "Mutation rate Hz", string$ (mutation_rate_Hz)
        comment: "Population"
        real: "Envelope density coupling percent", string$ (envelope_density_coupling_percent)
        optionmenu: "Register field", register_field
            option: "None"
            option: "Hollow centre"
            option: "Low to high"
            option: "High to low"
            option: "Moving window"
            option: "Alternating bands"
        real: "Stereo mass width percent", string$ (stereo_mass_width_percent)
    clickedDetail = endPause: "Cancel", "Continue", 2, 1
    if clickedDetail = 1
        exitScript: "Cancelled."
    endif
endif

# ---------------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------------
if sample_rate = 1
    sr = 22050
else
    sr = 44100
endif
dur = duration_s
if dur < 0.5 or dur > 60
    exitScript: "Duration must be between 0.5 and 60 seconds."
endif
if number_of_arcs < 1 or number_of_arcs > 6
    exitScript: "Number of arcs must be between 1 and 6."
endif
fLo = lowest_frequency_Hz
fHi = highest_frequency_Hz
if fLo < 10 or fHi <= fLo * 1.5
    exitScript: "Frequency range: lowest >= 10 Hz and highest > 1.5 x lowest."
endif
if fHi > 0.45 * sr
    exitScript: "Highest frequency must stay below 0.45 x sample rate (" + string$ (0.45 * sr) + " Hz)."
endif
if mass_voices_per_arc < 1 or mass_voices_per_arc > 32
    exitScript: "Mass voices per arc must be between 1 and 32."
endif
if pitch_spread_cents < 0 or pitch_spread_cents > 2400
    exitScript: "Pitch spread must be between 0 and 2400 cents."
endif
if glissando_dispersion_percent < 0 or glissando_dispersion_percent > 100
    exitScript: "Glissando dispersion must be between 0 and 100 %."
endif
if onset_scatter_ms < 0 or gain_scatter_dB < 0
    exitScript: "Onset and gain scatter cannot be negative."
endif
if waveform_mutation_percent < 0 or waveform_mutation_percent > 100 or breakpoint_drift_percent < 0 or breakpoint_drift_percent > 50
    exitScript: "Mutation must be 0-100 %, breakpoint drift 0-50 %."
endif
if mutation_correlation < 0 or mutation_correlation >= 1
    exitScript: "Mutation correlation must be >= 0 and < 1."
endif
if mutation_rate_Hz < 1 or mutation_rate_Hz > 200
    exitScript: "Mutation rate must be between 1 and 200 Hz."
endif
if envelope_density_coupling_percent < 0 or envelope_density_coupling_percent > 100 or stereo_mass_width_percent < 0 or stereo_mass_width_percent > 100
    exitScript: "Density coupling and stereo width must be 0-100 %."
endif
if number_of_arcs * mass_voices_per_arc * dur > 1600
    exitScript: "Workload arcs x voices x duration = " + string$ (number_of_arcs * mass_voices_per_arc * dur) + " voice-seconds; the limit is 1600. Reduce one of them."
endif
nArcs = number_of_arcs
nVoices = mass_voices_per_arc
lfLo = log2 (fLo)
lfHi = log2 (fHi)
spreadC = pitch_spread_cents
dispFrac = glissando_dispersion_percent / 100
onsetS = onset_scatter_ms / 1000
gainScatDb = gain_scatter_dB
sigA = waveform_mutation_percent / 100
sigP = breakpoint_drift_percent / 100
rho = mutation_correlation
innov = sqrt (1 - rho ^ 2)
mutRate = mutation_rate_Hz
densC = envelope_density_coupling_percent / 100
regField = register_field
widthF = stereo_mass_width_percent / 100
if widthF > 0
    outCh = 2
else
    outCh = 1
endif
if random_seed > 0
    baseSeed = random_seed
else
    baseSeed = randomInteger (1, 999999)
endif
tableRes = 1024
realName$[1] = "Line"
realName$[2] = "Mass"
realName$[3] = "Stochastic Mass"
realTag$[1] = "L"
realTag$[2] = "M"
realTag$[3] = "SM"
regName$[1] = "None"
regName$[2] = "Hollow centre"
regName$[3] = "Low to high"
regName$[4] = "High to low"
regName$[5] = "Moving window"
regName$[6] = "Alternating bands"

# ---------------------------------------------------------------------------
# LAYOUT (Demo window units 0..100, y upward; sx/sy/flip only for tests)
# ---------------------------------------------------------------------------
sx = 1
sy = 1
flipH = 0
vpL = 7.5
vpR = 96.25
ttlB = 91
ttlT = 99
pitB = 44
pitT = 86
envB = 20
envT = 36
wavB = 38
wavT = 86
preB = 20
preT = 30
sumB = 1.5
sumT = 12

# ---------------------------------------------------------------------------
# PALETTE (AudioTools standard; arc colours = the library's categorical set,
# light versions = 55 % toward white, for the mass fan and attractor cloud)
# ---------------------------------------------------------------------------
cPanel$ = "{0.97, 0.97, 0.97}"
cSum$   = "{0.94, 0.94, 0.94}"
cSumTx$ = "{0.25, 0.25, 0.35}"
cSubTx$ = "{0.35, 0.35, 0.50}"
cGrid$  = "{0.80, 0.80, 0.80}"
cInput$ = "{0.55, 0.55, 0.60}"
cOff$   = "{0.91, 0.91, 0.93}"
arcR[1] = 0.20
arcG[1] = 0.48
arcB[1] = 0.75
arcR[2] = 0.85
arcG[2] = 0.38
arcB[2] = 0.18
arcR[3] = 0.25
arcG[3] = 0.55
arcB[3] = 0.45
arcR[4] = 0.55
arcG[4] = 0.35
arcB[4] = 0.65
arcR[5] = 0.70
arcG[5] = 0.55
arcB[5] = 0.10
arcR[6] = 0.40
arcG[6] = 0.40
arcB[6] = 0.45
for k from 1 to 6
    arcCol$[k] = "{" + fixed$ (arcR[k], 2) + ", " + fixed$ (arcG[k], 2) + ", " + fixed$ (arcB[k], 2) + "}"
    arcLight$[k] = "{" + fixed$ (arcR[k] + 0.55 * (1 - arcR[k]), 2) + ", " + fixed$ (arcG[k] + 0.55 * (1 - arcG[k]), 2) + ", " + fixed$ (arcB[k] + 0.55 * (1 - arcB[k]), 2) + "}"
endfor

# ---------------------------------------------------------------------------
# DATA MODEL (as v1): lane 1 PITCH ARC (s, Hz), lane 2 WAVEFORM (phase, amp),
# lane 3 ENVELOPE (s, dB); nP[lane, arc]; one shared undo stack.
# ---------------------------------------------------------------------------
envLo = -60
envHi = 12
envOff = -120
envOffBand = 3
for k from 1 to nArcs
    nP[1, k] = 0
    nP[3, k] = 0
    nP[2, k] = 3
    pT[2, k, 1] = 0.00
    pV[2, k, 1] = 0.0
    pT[2, k, 2] = 0.25
    pV[2, k, 2] = 0.8
    pT[2, k, 3] = 0.75
    pV[2, k, 3] = -0.8
    arcDirty[k] = 1
    arcSnd[k] = 0
    arcCommitted[k] = 0
    arcReal[k] = realization
endfor
nHist = 0
mode = 1
cur = 1
status$ = "Macro screen: click in the upper panel to draw arc 1 (" + realName$[realization] + ")."
finalView = 0
mixSnd = 0
mixArcs = 0

@niceStep: dur, 8
tStep = niceStep.result
for k from 1 to nArcs
    @genVoices: k
endfor

# ============================================================================
# PROCEDURES - generic point editing (reused from v1 / Draw_Intensity_Envelope)
# ============================================================================
# ============================================================================
# fixed$ prints a bare "0" for zero whatever the precision; keep columns even
procedure fmt3: .v
    if abs (.v) < 0.0005
        .result$ = "0.000"
    else
        .result$ = fixed$ (.v, 3)
    endif
endproc

# fixed$ ignores the precision for tiny values (prints 1e-14 in full): round first
procedure fmtN: .v, .d
    .r = round (.v * 10 ^ .d) / 10 ^ .d
    if .r = 0
        .r = 0
    endif
    .result$ = fixed$ (.r, .d)
    if .r = 0 and .d > 0
        .result$ = "0." + left$ ("0000000", .d)
    endif
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc

procedure addOrMove: .lane, .k, .x, .y
    if .lane = 2
        .tol = 0.006
    else
        .tol = dur * 0.004
    endif
    .hit = 0
    for .i to nP[.lane, .k]
        if .hit = 0 and abs (pT[.lane, .k, .i] - .x) <= .tol
            .hit = .i
        endif
    endfor
    nHist += 1
    hLane[nHist] = .lane
    hArc[nHist] = .k
    if .hit > 0
        hKind[nHist] = 2
        hT[nHist] = pT[.lane, .k, .hit]
        hV[nHist] = pV[.lane, .k, .hit]
        pV[.lane, .k, .hit] = .y
        .verb$ = "Moved"
    else
        .n = nP[.lane, .k]
        .pos = .n + 1
        for .i to .n
            if .pos = .n + 1 and pT[.lane, .k, .i] > .x
                .pos = .i
            endif
        endfor
        for .m to .n - .pos + 1
            .j = .n - .m + 1
            .jn = .j + 1
            pT[.lane, .k, .jn] = pT[.lane, .k, .j]
            pV[.lane, .k, .jn] = pV[.lane, .k, .j]
        endfor
        pT[.lane, .k, .pos] = .x
        pV[.lane, .k, .pos] = .y
        nP[.lane, .k] = .n + 1
        hKind[nHist] = 1
        hT[nHist] = .x
        hV[nHist] = .y
        .verb$ = "Added"
    endif
    arcDirty[.k] = 1
    if .lane = 2
        @fmtN: .x, 3
    else
        @fmtN: .x, 2
    endif
    .xs$ = fmtN.result$
    if .lane = 2
        @fmtN: .y, 2
    else
        @fmtN: .y, 1
    endif
    .ys$ = fmtN.result$
    if .lane = 1
        status$ = .verb$ + " arc " + string$(.k) + " vertex: " + .xs$ + " s, " + .ys$ + " Hz."
    elsif .lane = 2
        status$ = .verb$ + " arc " + string$(.k) + " waveform point: phase " + .xs$ + ", amp " + .ys$ + "."
    else
        if .y <= envOff
            status$ = .verb$ + " arc " + string$(.k) + " envelope point: " + .xs$ + " s, off."
        else
            status$ = .verb$ + " arc " + string$(.k) + " envelope point: " + .xs$ + " s, " + .ys$ + " dB."
        endif
    endif
endproc

procedure undoLast
    if nHist = 0
        status$ = "Nothing to undo."
    else
        .lane = hLane[nHist]
        .k = hArc[nHist]
        .idx = 0
        for .i to nP[.lane, .k]
            if pT[.lane, .k, .i] = hT[nHist]
                .idx = .i
            endif
        endfor
        if hKind[nHist] = 2 and .idx > 0
            pV[.lane, .k, .idx] = hV[nHist]
            status$ = "Undid move (arc " + string$(.k) + ")."
        elsif .idx > 0
            for .i from .idx to nP[.lane, .k] - 1
                .j = .i + 1
                pT[.lane, .k, .i] = pT[.lane, .k, .j]
                pV[.lane, .k, .i] = pV[.lane, .k, .j]
            endfor
            nP[.lane, .k] = nP[.lane, .k] - 1
            status$ = "Undid add (arc " + string$(.k) + ")."
        endif
        arcDirty[.k] = 1
        nHist -= 1
    endif
endproc

# Route a click (Demo units) to the lane under the cursor.
procedure routeClick: .x, .y
    .u = (.x - vpL) / (vpR - vpL)
    if .u < 0 or .u > 1
        status$ = "Click inside a drawing panel."
    elsif mode = 1 and .y >= pitB and .y <= pitT
        # PITCH ARC lane: log-frequency axis
        .f = 2 ^ (lfLo + (.y - pitB) / (pitT - pitB) * (lfHi - lfLo))
        @addOrMove: 1, cur, .u * dur, .f
    elsif mode = 1 and .y >= envB and .y <= envT
        # ENVELOPE lane: the bottom band means "off" (silence)
        .db = envLo + (.y - envB) / (envT - envB) * (envHi - envLo)
        if .db < envLo + envOffBand
            .db = envOff
        endif
        @addOrMove: 3, cur, .u * dur, .db
    elsif mode = 2 and .y >= wavB and .y <= wavT
        # WAVEFORM lane: one cycle, phase 0..1, amplitude -1..1
        .a = -1 + 2 * (.y - wavB) / (wavT - wavB)
        @addOrMove: 2, cur, min (.u, 0.999), .a
    else
        status$ = "Click inside a drawing panel."
    endif
endproc

# ============================================================================
# PROCEDURES - WAVEFORM POLYGON (micro level) helpers
#   The polygon is periodic: the last vertex joins the first vertex of the
#   next cycle. wrapA = value at phase 0 (= phase 1) on that wrap segment.
# ============================================================================
procedure polyStats: .k
    .n = nP[2, .k]
    .p1 = pT[2, .k, 1]
    .a1 = pV[2, .k, 1]
    .pn = pT[2, .k, .n]
    .an = pV[2, .k, .n]
    .wrapW = .p1 + 1 - .pn
    if .wrapW > 1e-9
        .wrapA = .an + (.a1 - .an) * (1 - .pn) / .wrapW
    else
        .wrapA = .a1
    endif
    # mean over one cycle (trapezoids, including the wrap segment) = DC
    .mean = .wrapW * (.an + .a1) / 2
    for .i to .n - 1
        .j = .i + 1
        .mean += (pT[2, .k, .j] - pT[2, .k, .i]) * (pV[2, .k, .i] + pV[2, .k, .j]) / 2
    endfor
    .peak = 0
    for .i to .n
        .peak = max (.peak, abs (pV[2, .k, .i] - .mean))
    endfor
endproc

# Build the Formula that reads the polygon at phase = self (0..1).
# ============================================================================
# [MASS] POPULATION PARAMETERS - seeded per arc, so the editor preview and
# the render use the identical population (same seed, same call order).
#   vU  position in the population, -1..1 (stratified + jitter)
#   vC  static pitch offset, cents (= vU x spread)
#   vG  glissando dispersion factor (stratified, shuffled, mean exactly 0)
#   vOn onset (s)   vGdb gain scatter (dB)   vPh start phase   vPan -1..1
#   vRank  1 = closest to the drawn line (enters first under density)
# ============================================================================
procedure genVoices: .k
    random_initializeWithSeedUnsafelyButPredictably (baseSeed + 1000 * .k)
    if arcReal[.k] = 1
        .n = 1
    else
        .n = nVoices
    endif
    vN[.k] = .n
    for .i from 1 to .n
        gvPermA[.i] = .i
        gvPermB[.i] = .i
    endfor
    for .i from 1 to .n - 1
        .j = randomInteger (.i, .n)
        .tmp = gvPermA[.i]
        gvPermA[.i] = gvPermA[.j]
        gvPermA[.j] = .tmp
        .j = randomInteger (.i, .n)
        .tmp = gvPermB[.i]
        gvPermB[.i] = gvPermB[.j]
        gvPermB[.j] = .tmp
    endfor
    for .i from 1 to .n
        if .n = 1
            vU[.k, .i] = 0
            vC[.k, .i] = 0
            vG[.k, .i] = 0
            vOn[.k, .i] = 0
            vGdb[.k, .i] = 0
            vPh[.k, .i] = 0
            vPan[.k, .i] = 0
        else
            vU[.k, .i] = ((.i - 0.5) / .n) * 2 - 1 + randomUniform (-0.5, 0.5) / .n
            vC[.k, .i] = vU[.k, .i] * spreadC
            vG[.k, .i] = dispFrac * (((gvPermA[.i] - 0.5) / .n) * 2 - 1)
            vOn[.k, .i] = randomUniform (0, onsetS)
            vGdb[.k, .i] = randomUniform (-gainScatDb, gainScatDb)
            vPh[.k, .i] = randomUniform (0, 1)
            vPan[.k, .i] = widthF * (((gvPermB[.i] - 0.5) / .n) * 2 - 1)
        endif
    endfor
    # rank by distance from the drawn line (ascending selection sort)
    for .i from 1 to .n
        gvOrd[.i] = .i
    endfor
    for .a from 1 to .n - 1
        for .b from .a + 1 to .n
            .ia = gvOrd[.a]
            .ib = gvOrd[.b]
            if abs (vU[.k, .ib]) < abs (vU[.k, .ia])
                gvOrd[.a] = .ib
                gvOrd[.b] = .ia
            endif
        endfor
    endfor
    for .r from 1 to .n
        .i = gvOrd[.r]
        vRank[.k, .i] = .r
    endfor
    # the member closest to the line starts on time at nominal gain
    .i = gvOrd[1]
    vOn[.k, .i] = 0
    vGdb[.k, .i] = 0
endproc

# ============================================================================
# [ENVELOPE -> DENSITY] envelope in dB as a 100 Hz control Sound (linear in
# dB like the IntensityTier, held outside the drawn points), then
# N_active(t) = max(1, N 10^(coupling min(0, dB) / 40)).
# ============================================================================
procedure buildDensity: .k, .n
    .ctl = 100
    if nP[3, .k] = 0
        .v0 = 0
    else
        .v0 = pV[3, .k, 1]
    endif
    .snd = Create Sound from formula: "upic_nact" + string$ (.k), 1, 0, dur + 0.05, .ctl, string$ (.v0)
    for .i to nP[3, .k] - 1
        .j = .i + 1
        .t1 = pT[3, .k, .i]
        .t2 = pT[3, .k, .j]
        if .t2 - .t1 > 0.001
            Formula (part): .t1, .t2, 1, 1, string$ (pV[3, .k, .i]) + " + (" + string$ (pV[3, .k, .j] - pV[3, .k, .i]) + ") * (x - " + string$ (.t1) + ") / " + string$ (.t2 - .t1)
        endif
    endfor
    if nP[3, .k] > 0
        .tn = pT[3, .k, nP[3, .k]]
        if .tn < dur
            Formula (part): .tn, dur + 0.05, 1, 1, string$ (pV[3, .k, nP[3, .k]])
        endif
    endif
    Formula: "max (1, " + string$ (.n) + " * 10 ^ (" + string$ (densC) + " * min (0, self) / 40))"
    .result = .snd
endproc

# ============================================================================
# [GENDYN LAYER] one member's living cycle as a phase x time wavetable.
#   Rows = frames (mutation rate), columns = phase 0..1 (tableRes + 1).
#   A and P walks: Ornstein-Uhlenbeck around the drawn polygon, one
#   in-place Matrix Formula each (row r reads row r-1 already updated);
#   roughness scales the innovations by (1 + 2 R(t)).
#   P stays ordered: >= left neighbour + gap, and leaves room to the right.
#   Each row's mean (DC) is removed. Static drawing -> 2 identical rows.
# ============================================================================
procedure buildTable: .k, .nact$, .n, .spreadNorm
    .nb = nP[2, .k]
    if sigA > 0 or sigP > 0
        .dy = 1 / mutRate
        .nf = ceiling (dur * mutRate) + 2
    else
        .dy = dur
        .nf = 2
    endif
    .ymax = (.nf - 1) * .dy
    .gap = 0.002
    # drawn polygon as 1 x nb matrices (the attractor)
    .ad = Create Matrix: "upic_ad", 0.5, .nb + 0.5, .nb, 1, 1, 0.5, 1.5, 1, 1, 1, "0"
    .pd = Create Matrix: "upic_pd", 0.5, .nb + 0.5, .nb, 1, 1, 0.5, 1.5, 1, 1, 1, "0"
    for .c from 1 to .nb
        selectObject: .ad
        Set value: 1, .c, pV[2, .k, .c]
        selectObject: .pd
        Set value: 1, .c, pT[2, .k, .c]
    endfor
    .ad$ = string$ (.ad)
    .pd$ = string$ (.pd)
    .rough$ = "(1 + 2 * " + string$ (.spreadNorm) + " * object (" + .nact$ + ", y) / " + string$ (.n) + ")"
    .am = Create Matrix: "upic_am", 0.5, .nb + 0.5, .nb, 1, 1, 0, .ymax, .nf, .dy, 0, "0"
    Formula: "if row = 1 then object[" + .ad$ + ", 1, col] else min (1, max (-1, object[" + .ad$ + ", 1, col] + "
        ... + string$ (rho) + " * (self[row-1, col] - object[" + .ad$ + ", 1, col]) + "
        ... + string$ (sigA * innov) + " * " + .rough$ + " * randomGauss (0, 1))) fi"
    .pm = Create Matrix: "upic_pm", 0.5, .nb + 0.5, .nb, 1, 1, 0, .ymax, .nf, .dy, 0, "0"
    Formula: "if row = 1 then object[" + .pd$ + ", 1, col] else min (1 - (" + string$ (.nb) + " - col + 1) * " + string$ (.gap)
        ... + ", max (if col = 1 then 0 else self[row, col-1] + " + string$ (.gap) + " fi, object[" + .pd$ + ", 1, col] + "
        ... + string$ (rho) + " * (self[row-1, col] - object[" + .pd$ + ", 1, col]) + "
        ... + string$ (sigP * innov) + " * " + .rough$ + " * randomGauss (0, 1))) fi"
    # polygon read at phase x for every row (periodic: last joins first + 1)
    .a$ = string$ (.am)
    .p$ = string$ (.pm)
    .nb$ = string$ (.nb)
    .p1$ = "object[" + .p$ + ", row, 1]"
    .a1$ = "object[" + .a$ + ", row, 1]"
    .pn$ = "object[" + .p$ + ", row, " + .nb$ + "]"
    .an$ = "object[" + .a$ + ", row, " + .nb$ + "]"
    .ww$ = "max (1e-9, " + .p1$ + " + 1 - " + .pn$ + ")"
    .f$ = "if x < " + .p1$ + " then " + .an$ + " + (" + .a1$ + " - " + .an$ + ") * (x + 1 - " + .pn$ + ") / " + .ww$
    for .i to .nb - 1
        .j = .i + 1
        .pi$ = "object[" + .p$ + ", row, " + string$ (.i) + "]"
        .pj$ = "object[" + .p$ + ", row, " + string$ (.j) + "]"
        .ai$ = "object[" + .a$ + ", row, " + string$ (.i) + "]"
        .aj$ = "object[" + .a$ + ", row, " + string$ (.j) + "]"
        .f$ = .f$ + " else if x < " + .pj$ + " then " + .ai$ + " + (" + .aj$ + " - " + .ai$ + ") * (x - " + .pi$ + ") / max (1e-9, " + .pj$ + " - " + .pi$ + ")"
    endfor
    .f$ = .f$ + " else " + .an$ + " + (" + .a1$ + " - " + .an$ + ") * (x - " + .pn$ + ") / " + .ww$
    for .i to .nb
        .f$ = .f$ + " fi"
    endfor
    .tab = Create Matrix: "upic_tab", 0, 1, tableRes + 1, 1 / tableRes, 0, 0, .ymax, .nf, .dy, 0, .f$
    # remove each row's DC (trapezoid integral over one cycle)
    .cum = Copy: "upic_cum"
    Formula: "if col = 1 then 0 else self[row, col-1] + (object[" + string$ (.tab) + ", row, col-1] + object[" + string$ (.tab) + ", row, col]) / " + string$ (2 * tableRes) + " fi"
    selectObject: .tab
    Formula: "self - object[" + string$ (.cum) + ", row, " + string$ (tableRes + 1) + "]"
    removeObject: .ad, .pd, .am, .pm, .cum
    .result = .tab
endproc

# ============================================================================
# [REGISTER FIELD] which members exist over time; u = member position -1..1,
# tau = x / dur. Returns a Formula fragment (weight 0..1).
# ============================================================================
procedure registerExpr: .u
    .u$ = string$ (.u)
    .tau$ = "(x / " + string$ (dur) + ")"
    if regField = 1
        .result$ = "1"
    elsif regField = 2
        .result$ = string$ (min (1, max (0, (abs (.u) - 0.25) / 0.2)))
    elsif regField = 3 or regField = 4 or regField = 5
        if regField = 3
            .c$ = "(-1 + 2 * " + .tau$ + ")"
        elsif regField = 4
            .c$ = "(1 - 2 * " + .tau$ + ")"
        else
            .c$ = "(0.8 * sin (2 * pi * " + .tau$ + "))"
        endif
        .result$ = "(if abs (" + .u$ + " - " + .c$ + ") < 0.6 then 0.5 + 0.5 * cos (pi * (" + .u$ + " - " + .c$ + ") / 0.6) else 0 fi)"
    else
        .result$ = "(0.5 + 0.5 * cos (4 * pi * " + .u$ + ") * cos (4 * pi * " + .tau$ + "))"
    endif
endproc

# ============================================================================
# RENDER ONE ARC = realization of (PITCH ARC, WAVEFORM ATTRACTOR, ENVELOPE)
# ============================================================================
procedure renderArc: .k
    if arcSnd[.k] > 0
        removeObject: arcSnd[.k]
        arcSnd[.k] = 0
    endif
    .np = nP[1, .k]
    if .np >= 1
        @genVoices: .k
        .n = vN[.k]
        if .n > 1
            .spreadNorm = min (1, spreadC / 200)
        else
            .spreadNorm = 0
        endif

        # ---- [UPIC LINE] drawn arc as log2 frequency at audio rate --------
        .arcLog = Create Sound from formula: "upic_L" + string$ (.k), 1, 0, dur, sr, string$ (log2 (pV[1, .k, 1]))
        for .i to .np - 1
            .j = .i + 1
            .t1 = pT[1, .k, .i]
            .t2 = pT[1, .k, .j]
            if .t2 - .t1 > 1 / sr
                .l1 = log2 (pV[1, .k, .i])
                .dl = log2 (pV[1, .k, .j]) - .l1
                Formula (part): .t1, .t2, 1, 1, string$ (.l1) + " + " + string$ (.dl) + " * (x - " + string$ (.t1) + ") / " + string$ (.t2 - .t1)
            endif
        endfor
        .tn = pT[1, .k, .np]
        if .tn < dur
            Formula (part): .tn, dur, 1, 1, string$ (log2 (pV[1, .k, .np]))
        endif
        .lsnd$ = string$ (.arcLog)
        .l0 = log2 (pV[1, .k, 1])

        # ---- [DENSITY] active-member count from the envelope --------------
        @buildDensity: .k, .n
        .nact = buildDensity.result
        .nact$ = string$ (.nact)

        .buf = Create Sound from formula: "UPIC_arc" + string$ (.k), outCh, 0, dur, sr, "0"
        .fmax$ = string$ (0.45 * sr)
        .dt$ = string$ (1 / sr)
        for .i to .n
            # ---- [GENDYN LAYER] this member's living cycle ----------------
            @buildTable: .k, .nact$, .n, .spreadNorm
            .tab = buildTable.result

            # ---- [STOCHASTIC MASS] correlated pitch drift (cents) ---------
            if arcReal[.k] = 3 and .n > 1
                .dsnd = Create Sound from formula: "upic_drift", 1, 0, dur + 2 / mutRate, mutRate, "0"
                Formula: "if col = 1 then 0 else " + string$ (rho) + " * self[col-1] + " + string$ (spreadC / 2 * innov)
                    ... + " * (1 + 2 * " + string$ (.spreadNorm) + " * object (" + .nact$ + ", x) / " + string$ (.n) + ") * randomGauss (0, 1) fi"
                .drift$ = "object (" + string$ (.dsnd) + ", x - " + .dt$ + ")"
            else
                .dsnd = 0
                .drift$ = "0"
            endif

            # ---- [MASS] member frequency -> running phase -----------------
            .g = vG[.k, .i]
            .v = Create Sound from formula: "upic_v", 1, 0, dur, sr, "0"
            Formula: "if col = 1 then " + string$ (vPh[.k, .i]) + " else self[col-1] + max (5, min (" + .fmax$ + ", 2 ^ (object[" + .lsnd$ + ", 1, col-1] * "
                ... + string$ (1 + .g) + " - " + string$ (.g * .l0) + " + (" + string$ (vC[.k, .i]) + " + " + .drift$ + ") / 1200))) / " + string$ (sr) + " fi"

            # ---- read the cycle; energy, onset, density, register ---------
            .gain = 10 ^ (vGdb[.k, .i] / 20) / sqrt (.n)
            .w$ = string$ (.gain)
            if vOn[.k, .i] > 0
                .on$ = string$ (vOn[.k, .i])
                .w$ = .w$ + " * (if x < " + .on$ + " then 0 else min (1, (x - " + .on$ + ") / 0.005) fi)"
            endif
            if .n > 1
                .w$ = .w$ + " * min (1, max (0, object (" + .nact$ + ", x) - " + string$ (vRank[.k, .i] - 1) + "))"
            endif
            if .n >= 3 and regField > 1
                @registerExpr: vU[.k, .i]
                .w$ = .w$ + " * " + registerExpr.result$
            endif
            Formula: "object (" + string$ (.tab) + ", self - floor (self), x) * " + .w$

            # ---- equal-power placement into the arc buffer ----------------
            selectObject: .buf
            if outCh = 2
                .th = (vPan[.k, .i] + 1) * pi / 4
                Formula: "self + object[" + string$ (.v) + ", 1, col] * (if row = 1 then " + string$ (cos (.th)) + " else " + string$ (sin (.th)) + " fi)"
            else
                Formula: "self + object[" + string$ (.v) + ", 1, col]"
            endif
            removeObject: .v, .tab
            if .dsnd > 0
                removeObject: .dsnd
            endif
        endfor
        removeObject: .arcLog, .nact

        # ---- [ENVELOPE] IntensityTier Multiply, scaling OFF ----------------
        if nP[3, .k] > 0
            .tier = Create IntensityTier: "upic_env" + string$ (.k), 0, dur
            for .i to nP[3, .k]
                Add point: pT[3, .k, .i], pV[3, .k, .i]
            endfor
            selectObject: .buf, .tier
            .env = Multiply: "no"
            removeObject: .buf, .tier
            .buf = .env
            selectObject: .buf
            Rename: "UPIC_arc" + string$ (.k)
        endif
        upicFade = min (0.01, dur / 10)
        Formula: "if x < upicFade then self * x / upicFade else if x > dur - upicFade then self * (dur - x) / upicFade else self fi fi"
        arcSnd[.k] = .buf
    endif
    arcDirty[.k] = 0
endproc

# ---- display-only pseudo-random (never touches Praat's RNG) --------------
procedure hashGauss: .a, .b
    .u1 = sin (.a * 12.9898 + .b * 78.233) * 43758.5453
    .u1 = .u1 - floor (.u1)
    .u2 = sin (.a * 39.3467 + .b * 11.135) * 24634.6345
    .u2 = .u2 - floor (.u2)
    .result = sqrt (-2 * ln (max (1e-9, .u1))) * cos (2 * pi * .u2)
endproc

# ============================================================================
# PROCEDURES - DRAWING
# ============================================================================
procedure vp: .x1, .x2, .y1, .y2
    if flipH > 0
        demo Select inner viewport: .x1 * sx, .x2 * sx, flipH - .y2 * sy, flipH - .y1 * sy
    else
        demo Select inner viewport: .x1 * sx, .x2 * sx, .y1 * sy, .y2 * sy
    endif
endproc

procedure drawTitle: .title$
    demo Font size: 12
    @vp: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0.5, "centre", 0.72, "half", "##" + .title$ + "##"
    demo Font size: 7
    @vp: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: cSubTx$
    if outCh = 2
        .ch$ = "stereo width " + fixed$ (widthF * 100, 0) + " \% "
    else
        .ch$ = "mono"
    endif
    demo Text: 0.5, "centre", 0.12, "half", preset_name$ + "   |   " + fixed$ (dur, 2) + " s   |   " + string$ (nArcs) + " arcs x up to "
        ... + string$ (nVoices) + " voices   |   " + fixed$ (fLo, 0) + "\--" + fixed$ (fHi, 0) + " Hz (log)   |   " + .ch$
endproc

procedure caption: .x1, .x2, .yT, .text$
    demo Font size: 8
    @vp: .x1, .x2, .yT, .yT + 3
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0, "left", 0.2, "half", .text$
endproc

procedure freqMarks
    for .oct from 0 to 12
        .f = 27.5 * 2 ^ .oct
        if .f >= fLo * 0.999 and .f <= fHi * 1.001
            demo One mark left: log2 (.f), "no", "yes", "no", string$ (.f)
        endif
    endfor
endproc

# ---- PITCH ARC panel: all arcs, current arc bold with vertices ------------
procedure drawPitchPanel: .editable
    demo Font size: 7
    @vp: vpL, vpR, pitB, pitT
    demo Axes: 0, dur, lfLo, lfHi
    demo Paint rectangle: cPanel$, 0, dur, lfLo, lfHi
    demo Colour: cGrid$
    demo Dotted line
    for .oct from 0 to 12
        .f = 27.5 * 2 ^ .oct
        if .f > fLo and .f < fHi
            demo Draw line: 0, log2 (.f), dur, log2 (.f)
        endif
    endfor
    demo Solid line
    # [MASS] static fan of every arc: offsets c_i + glissando dispersion g_i
    # (a straight segment in log2 stays straight for every member)
    demo Line width: 1
    for .k to nArcs
        .n = nP[1, .k]
        if .n > 0 and vN[.k] > 1
            demo Colour: arcLight$[.k]
            for .i to vN[.k]
                .g = vG[.k, .i]
                .c = vC[.k, .i] / 1200
                .l0 = log2 (pV[1, .k, 1])
                .la = log2 (pV[1, .k, 1]) * (1 + .g) - .g * .l0 + .c
                .lz = log2 (pV[1, .k, .n]) * (1 + .g) - .g * .l0 + .c
                .la = max (lfLo, min (lfHi, .la))
                .lz = max (lfLo, min (lfHi, .lz))
                if pT[1, .k, 1] > 0
                    demo Draw line: 0, .la, pT[1, .k, 1], .la
                endif
                if pT[1, .k, .n] < dur
                    demo Draw line: pT[1, .k, .n], .lz, dur, .lz
                endif
                for .p to .n - 1
                    .q = .p + 1
                    .ya = max (lfLo, min (lfHi, log2 (pV[1, .k, .p]) * (1 + .g) - .g * .l0 + .c))
                    .yb = max (lfLo, min (lfHi, log2 (pV[1, .k, .q]) * (1 + .g) - .g * .l0 + .c))
                    demo Draw line: pT[1, .k, .p], .ya, pT[1, .k, .q], .yb
                endfor
            endfor
        endif
    endfor
    for .kk to nArcs
        # current arc last, so it sits on top
        .k = ((cur + .kk - 1) mod nArcs) + 1
        .n = nP[1, .k]
        if .n > 0
            demo Colour: arcCol$[.k]
            if .k = cur and .editable
                demo Line width: 2.5
            else
                demo Line width: 1.2
            endif
            demo Dotted line
            if pT[1, .k, 1] > 0
                demo Draw line: 0, log2 (pV[1, .k, 1]), pT[1, .k, 1], log2 (pV[1, .k, 1])
            endif
            if pT[1, .k, .n] < dur
                demo Draw line: pT[1, .k, .n], log2 (pV[1, .k, .n]), dur, log2 (pV[1, .k, .n])
            endif
            demo Solid line
            for .i to .n - 1
                .j = .i + 1
                demo Draw line: pT[1, .k, .i], log2 (pV[1, .k, .i]), pT[1, .k, .j], log2 (pV[1, .k, .j])
            endfor
            demo Line width: 1
            if .k = cur and .editable
                for .i to .n
                    demo Paint circle (mm): arcCol$[.k], pT[1, .k, .i], log2 (pV[1, .k, .i]), 1.6
                endfor
            endif
        endif
    endfor
    demo Font size: 7
    @vp: vpL, vpR, pitB, pitT
    demo Axes: 0, dur, lfLo, lfHi
    for .k to nArcs
        if nP[1, .k] > 0
            demo Colour: arcCol$[.k]
            demo Text: pT[1, .k, 1], "right", log2 (pV[1, .k, 1]), "bottom", "##" + string$ (.k) + "## " + realTag$[arcReal[.k]] + " "
        endif
    endfor
    @vp: vpL, vpR, pitB, pitT
    demo Axes: 0, dur, lfLo, lfHi
    demo Colour: "Black"
    demo Draw inner box
    @freqMarks
    demo Marks bottom every: 1, tStep, "yes", "yes", "no"
    demo Text left: "yes", "Frequency (Hz)"
    if .editable
        @caption: vpL, vpR, pitT + 1, "##PITCH ARCS (macro)  \--  editing arc " + string$ (cur) + ", " + realName$[arcReal[cur]] + "##   bold = drawn line, light = mass members (static fan); dotted = held"
    else
        @caption: vpL, vpR, pitT + 1, "##PITCH ARCS##"
    endif
endproc

# ---- ENVELOPE panel: current arc, dB over time ----------------------------
procedure drawEnvPanel
    .k = cur
    demo Font size: 7
    @vp: vpL, vpR, envB, envT
    demo Axes: 0, dur, envLo, envHi
    demo Paint rectangle: cPanel$, 0, dur, envLo, envHi
    demo Paint rectangle: cOff$, 0, dur, envLo, envLo + envOffBand
    demo Colour: cGrid$
    demo Dotted line
    for .g from 1 to 5
        demo Draw line: 0, -12 * .g, dur, -12 * .g
    endfor
    demo Solid line
    demo Draw line: 0, 0, dur, 0
    .n = nP[3, .k]
    if .n > 0
        demo Colour: arcCol$[.k]
        demo Line width: 2
        demo Dotted line
        .v1 = max (envLo, pV[3, .k, 1])
        .vn = max (envLo, pV[3, .k, .n])
        if pT[3, .k, 1] > 0
            demo Draw line: 0, .v1, pT[3, .k, 1], .v1
        endif
        if pT[3, .k, .n] < dur
            demo Draw line: pT[3, .k, .n], .vn, dur, .vn
        endif
        demo Solid line
        for .i to .n - 1
            .j = .i + 1
            demo Draw line: pT[3, .k, .i], max (envLo, pV[3, .k, .i]), pT[3, .k, .j], max (envLo, pV[3, .k, .j])
        endfor
        demo Line width: 1
        for .i to .n
            demo Paint circle (mm): arcCol$[.k], pT[3, .k, .i], max (envLo, pV[3, .k, .i]), 1.4
        endfor
    else
        demo Colour: arcCol$[.k]
        demo Line width: 2
        demo Draw line: 0, 0, dur, 0
        demo Line width: 1
    endif
    demo Font size: 6
    @vp: vpL, vpR, envB, envT
    demo Axes: 0, 1, 0, 1
    demo Colour: cSubTx$
    demo Text: 0.005, "left", (envOffBand / 2) / (envHi - envLo), "half", "off (silence)"
    if .n = 0
        demo Text: 0.995, "right", 0.85, "half", "no points: 0 dB throughout"
    endif
    demo Font size: 7
    @vp: vpL, vpR, envB, envT
    demo Axes: 0, dur, envLo, envHi
    demo Colour: "Black"
    demo Draw inner box
    demo Marks left every: 1, 12, "yes", "yes", "no"
    demo Marks bottom every: 1, tStep, "yes", "yes", "no"
    demo Text left: "yes", "Gain (dB)"
    demo Text bottom: "yes", "Time (s)"
    @caption: vpL, vpR, envT + 1, "##ENVELOPE  \--  arc " + string$ (.k) + "##   IntensityTier, scaling off; bottom band = off"
endproc

# ---- WAVEFORM POLYGON editor: current arc, one cycle ----------------------
procedure drawWavePanel
    .k = cur
    @polyStats: .k
    .n = nP[2, .k]
    demo Font size: 7
    @vp: vpL, vpR, wavB, wavT
    demo Axes: 0, 1, -1, 1
    demo Paint rectangle: cPanel$, 0, 1, -1, 1
    demo Colour: cGrid$
    demo Dotted line
    for .q from 1 to 3
        demo Draw line: .q / 4, -1, .q / 4, 1
    endfor
    demo Draw line: 0, 0.5, 1, 0.5
    demo Draw line: 0, -0.5, 1, -0.5
    demo Solid line
    demo Draw line: 0, 0, 1, 0
    # DC (mean) that will be removed
    demo Colour: cInput$
    demo Dashed line
    demo Draw line: 0, polyStats.mean, 1, polyStats.mean
    demo Solid line
    # [GENDYN LAYER] attractor cloud: typical mutated cycles at the
    # stationary spread (display-only pseudo-random; does not touch the RNG)
    if sigA > 0 or sigP > 0
        demo Colour: arcLight$[.k]
        demo Line width: 1
        for .s to 8
            for .i to .n
                @hashGauss: .s * 31 + .k, .i
                cA[.i] = min (1, max (-1, pV[2, .k, .i] + sigA * hashGauss.result))
                @hashGauss: .s * 17 + .k + 101, .i
                cP[.i] = pT[2, .k, .i] + sigP * hashGauss.result
                if .i > 1
                    cP[.i] = max (cP[.i], cP[.i - 1] + 0.002)
                else
                    cP[.i] = max (0, cP[.i])
                endif
                cP[.i] = min (1 - (.n - .i + 1) * 0.002, cP[.i])
            endfor
            for .i to .n - 1
                .j = .i + 1
                demo Draw line: cP[.i], cA[.i], cP[.j], cA[.j]
            endfor
            .ww = max (1e-9, cP[1] + 1 - cP[.n])
            .wa = cA[.n] + (cA[1] - cA[.n]) * (1 - cP[.n]) / .ww
            demo Draw line: cP[.n], cA[.n], 1, .wa
            demo Draw line: 0, .wa, cP[1], cA[1]
        endfor
    endif
    # the polygon, wrap segment dotted (it joins the next cycle)
    demo Colour: arcCol$[.k]
    demo Line width: 2.5
    for .i to .n - 1
        .j = .i + 1
        demo Draw line: pT[2, .k, .i], pV[2, .k, .i], pT[2, .k, .j], pV[2, .k, .j]
    endfor
    demo Dotted line
    demo Draw line: pT[2, .k, .n], pV[2, .k, .n], 1, polyStats.wrapA
    demo Draw line: 0, polyStats.wrapA, pT[2, .k, 1], pV[2, .k, 1]
    demo Solid line
    demo Line width: 1
    for .i to .n
        demo Paint circle (mm): arcCol$[.k], pT[2, .k, .i], pV[2, .k, .i], 1.6
    endfor
    demo Font size: 6
    @vp: vpL, vpR, wavB, wavT
    demo Axes: 0, 1, -1, 1
    demo Colour: cInput$
    demo Text: 0.995, "right", polyStats.mean, "bottom", "DC " + fixed$ (polyStats.mean, 3) + " (removed)"
    demo Font size: 7
    @vp: vpL, vpR, wavB, wavT
    demo Axes: 0, 1, -1, 1
    demo Colour: "Black"
    demo Draw inner box
    demo Marks left every: 1, 0.5, "yes", "yes", "no"
    demo Marks bottom every: 1, 0.25, "yes", "yes", "no"
    demo Text left: "yes", "Amplitude"
    demo Text bottom: "yes", "Phase within one cycle"
    if sigA > 0 or sigP > 0
        @caption: vpL, vpR, wavT + 1, "##WAVEFORM ATTRACTOR (micro)  \--  arc " + string$ (.k) + "##   bold = drawn centre of gravity; light = typical mutated cycles (" + fixed$ (sigA * 100, 0) + " \%  amp, " + fixed$ (sigP * 100, 0) + " \%  drift)"
    else
        @caption: vpL, vpR, wavT + 1, "##WAVEFORM POLYGON (micro)  \--  arc " + string$ (.k) + "##   static cycle (mutation off); dotted = wrap to next cycle"
    endif
endproc

# ---- rendered-cycle preview: 3 cycles, DC removed (what is heard) ---------
procedure drawWavePreview
    .k = cur
    @polyStats: .k
    .n = nP[2, .k]
    .r = max (1, polyStats.peak) * 1.08
    .m = polyStats.mean
    demo Font size: 7
    @vp: vpL, vpR, preB, preT
    demo Axes: 0, 3, -.r, .r
    demo Paint rectangle: cPanel$, 0, 3, -.r, .r
    demo Colour: cGrid$
    demo Draw line: 0, 0, 3, 0
    demo Dotted line
    demo Draw line: 1, -.r, 1, .r
    demo Draw line: 2, -.r, 2, .r
    demo Solid line
    demo Colour: arcCol$[.k]
    demo Line width: 1.5
    for .c from 0 to 2
        demo Draw line: .c, polyStats.wrapA - .m, .c + pT[2, .k, 1], pV[2, .k, 1] - .m
        for .i to .n - 1
            .j = .i + 1
            demo Draw line: .c + pT[2, .k, .i], pV[2, .k, .i] - .m, .c + pT[2, .k, .j], pV[2, .k, .j] - .m
        endfor
        demo Draw line: .c + pT[2, .k, .n], pV[2, .k, .n] - .m, .c + 1, polyStats.wrapA - .m
    endfor
    demo Line width: 1
    @vp: vpL, vpR, preB, preT
    demo Axes: 0, 3, -.r, .r
    demo Colour: "Black"
    demo Draw inner box
    demo Marks bottom every: 1, 1, "yes", "yes", "no"
    demo Text bottom: "yes", "Cycles (drawn attractor: wrap closed, DC removed)"
    @caption: vpL, vpR, preT + 1, "##DRAWN CYCLE x3##"
endproc

# ---- result view: measured spectrogram of the mix + drawn arcs --------------
procedure drawOutputPanel
    # frequency range = the drawn arcs (fundamentals), not the harmonics
    .fMaxDrawn = 0
    for .k to nArcs
        for .i to nP[1, .k]
            .fMaxDrawn = max (.fMaxDrawn, pV[1, .k, .i])
        endfor
    endfor
    .fTop = min (0.45 * sr, max (500, 1.3 * .fMaxDrawn * 2 ^ (spreadC / 2400)))
    selectObject: mixSnd
    if outCh = 2
        .mono = Convert to mono
    else
        .mono = Copy: "upic_mono"
    endif
    .spec = To Spectrogram: 0.03, .fTop, max (0.002, dur / 1000), 20, "Gaussian"
    demo Font size: 7
    @vp: vpL, vpR, envB, envT
    demo Paint: 0, 0, 0, .fTop, 100, "yes", 50, 6, 0, "no"
    removeObject: .mono, .spec
    @vp: vpL, vpR, envB, envT
    demo Axes: 0, dur, 0, .fTop
    for .k to nArcs
        .n = nP[1, .k]
        if .n > 0
            demo Colour: arcCol$[.k]
            demo Line width: 1.5
            for .i to .n - 1
                .j = .i + 1
                demo Draw line: pT[1, .k, .i], min (.fTop, pV[1, .k, .i]), pT[1, .k, .j], min (.fTop, pV[1, .k, .j])
            endfor
            demo Line width: 1
        endif
    endfor
    @vp: vpL, vpR, envB, envT
    demo Axes: 0, dur, 0, .fTop
    demo Colour: "Black"
    demo Draw inner box
    @niceStep: .fTop, 4
    demo Marks left every: 1, niceStep.result, "yes", "yes", "no"
    demo Marks bottom every: 1, tStep, "yes", "yes", "no"
    demo Text left: "yes", "Hz (linear)"
    demo Text bottom: "yes", "Time (s)"
    @caption: vpL, vpR, envT + 1, "##OUTPUT  \--  measured spectrogram of the mix##   drawn arcs overlaid (linear axis, fundamentals range); peak " + fixed$ (mixPeak, 3) + guardNote$
endproc

procedure drawSummary
    demo Font size: 7
    @vp: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Paint rectangle: cSum$, 0, 1, 0, 1
    demo Colour: cSumTx$
    if finalView
        demo Text: 0.01, "left", 0.80, "half", "##Done.## The mix is selected in the Objects window; see the Info window for the per-arc summary."
    else
        demo Text: 0.01, "left", 0.80, "half", "##Click## add / move   ##U## undo   ##1\-- " + string$ (nArcs) + "## arc   ##Tab/M## pitch \<> waveform   ##R## realization   ##Enter## commit + play   ##F## finish   ##Esc## cancel"
    endif
    # per-arc status in each arc's colour
    for .k to nArcs
        .x = 0.01 + (.k - 1) * 0.165
        if arcSnd[.k] > 0 and arcDirty[.k] = 0
            .st$ = "rendered"
        elsif arcCommitted[.k]
            .st$ = "edited"
        elsif nP[1, .k] = 0
            .st$ = "empty"
        else
            .st$ = "drawn"
        endif
        demo Colour: arcCol$[.k]
        if .k = cur and finalView = 0
            demo Text: .x, "left", 0.50, "half", "##>" + string$ (.k) + " " + realTag$[arcReal[.k]] + "## " + string$ (nP[1, .k]) + "/" + string$ (nP[2, .k]) + "/" + string$ (nP[3, .k]) + " " + .st$
        else
            demo Text: .x, "left", 0.50, "half", "##" + string$ (.k) + " " + realTag$[arcReal[.k]] + "## " + string$ (nP[1, .k]) + "/" + string$ (nP[2, .k]) + "/" + string$ (nP[3, .k]) + " " + .st$
        endif
    endfor
    demo Colour: cSumTx$
    demo Text: 0.01, "left", 0.20, "half", "##Status:## " + status$ + "     (L line, M mass, SM stochastic mass; points pitch/wave/env)"
    @vp: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Draw inner box
endproc

procedure drawAll
    demo Erase all
    if finalView
        @drawTitle: "UPIC Draw Synthesis \--  RESULT"
        @drawPitchPanel: 0
        @drawOutputPanel
    elsif mode = 1
        @drawTitle: "UPIC Draw Synthesis \--  PITCH ARCS (macro)"
        @drawPitchPanel: 1
        @drawEnvPanel
    else
        @drawTitle: "UPIC Draw Synthesis \--  WAVEFORM (micro)"
        @drawWavePanel
        @drawWavePreview
    endif
    @drawSummary
    # Leave the frame on the whole window in Demo units, so demoX/demoY
    # are window coordinates and routeClick decides the panel.
    demo Font size: 7
    @vp: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
endproc

# ---- commit / finish ------------------------------------------------------
procedure commitArc: .k
    if nP[1, .k] = 0
        status$ = "Arc " + string$ (.k) + " has no pitch vertices yet - draw it first."
    else
        status$ = "Rendering arc " + string$ (.k) + " (" + realName$[arcReal[.k]] + ", " + string$ (vN[.k]) + " voices)..."
        @drawAll
        @renderArc: .k
        arcCommitted[.k] = 1
        selectObject: arcSnd[.k]
        .pk = Get absolute extremum: 0, 0, "None"
        if .pk > 0.99
            .aud = Copy: "upic_audition"
            Scale peak: 0.99
            Play
            removeObject: .aud
        elsif .pk > 0
            Play
        endif
        status$ = "Arc " + string$ (.k) + " committed and played (peak " + fixed$ (.pk, 3) + ")."
    endif
endproc

procedure cleanUpArcs
    for .k to nArcs
        if arcSnd[.k] > 0
            removeObject: arcSnd[.k]
            arcSnd[.k] = 0
        endif
    endfor
endproc

# ============================================================================
# INTERACTIVE DRAWING
# ============================================================================
@drawAll

# >>> INPUT LOOP
action$ = ""
while action$ = ""
    demoWaitForInput ()
    if demoClicked ()
        @routeClick: demoX (), demoY ()
        @drawAll
    elsif demoKeyPressed ()
        key$ = demoKey$ ()
        if key$ = newline$ or key$ = unicode$ (13) or key$ = unicode$ (65293)
            @commitArc: cur
            @drawAll
        elsif key$ = unicode$ (27) or key$ = unicode$ (65307)
            action$ = "cancel"
        elsif key$ = tab$ or key$ = unicode$ (65289) or key$ = "m" or key$ = "M"
            mode = 3 - mode
            if mode = 1
                status$ = "Pitch-arc screen (macro). Draw arc " + string$ (cur) + " and its envelope."
            else
                status$ = "Waveform screen (micro). Draw the attractor cycle for arc " + string$ (cur) + "."
            endif
            @drawAll
        elsif key$ = "r" or key$ = "R"
            # cycle this arc's realization: Line -> Mass -> Stochastic Mass
            arcReal[cur] = (arcReal[cur] mod 3) + 1
            @genVoices: cur
            arcDirty[cur] = 1
            status$ = "Arc " + string$ (cur) + " realization: " + realName$[arcReal[cur]] + " (" + string$ (vN[cur]) + " voices)."
            @drawAll
        elsif key$ = "u" or key$ = "U"
            @undoLast
            @drawAll
        elsif key$ = "f" or key$ = "F"
            anyArc = 0
            for k to nArcs
                if nP[1, k] > 0
                    anyArc = 1
                endif
            endfor
            if anyArc
                action$ = "finish"
            else
                status$ = "Draw at least one pitch arc before finishing."
                @drawAll
            endif
        else
            keyNum = number (key$)
            if keyNum <> undefined
                if keyNum >= 1 and keyNum <= nArcs
                    cur = keyNum
                    status$ = "Editing arc " + string$ (cur) + " (" + realName$[arcReal[cur]] + ")."
                    @drawAll
                endif
            endif
        endif
    endif
endwhile
# <<< INPUT LOOP

if action$ = "cancel"
    @cleanUpArcs
    status$ = "Cancelled - nothing was created."
    @drawAll
    exitScript: "UPIC Draw Synthesis cancelled."
endif

# ============================================================================
# FINISH - render remaining arcs, sum, PEAK GUARD (no normalisation), Info
# ============================================================================
status$ = "Rendering and mixing..."
@drawAll
renderStart = stopwatch
for k to nArcs
    if nP[1, k] > 0
        if arcDirty[k] or arcSnd[k] = 0
            @renderArc: k
        endif
        mixArcs += 1
    endif
endfor

mixSnd = Create Sound from formula: "UPIC_mix", outCh, 0, dur, sr, "0"
for k to nArcs
    if arcSnd[k] > 0
        selectObject: arcSnd[k]
        arcPeak[k] = Get absolute extremum: 0, 0, "None"
        arcRms[k] = Get root-mean-square: 0, 0
        selectObject: mixSnd
        Formula: "self + object[" + string$ (arcSnd[k]) + ", row, col]"
    endif
endfor
selectObject: mixSnd
mixPeakRaw = Get absolute extremum: 0, 0, "None"
guardDb = 0
guardNote$ = ""
if mixPeakRaw > 0.99
    Scale peak: 0.99
    guardDb = 20 * log10 (0.99 / mixPeakRaw)
    guardNote$ = " (peak guard " + fixed$ (guardDb, 1) + " dB)"
endif
mixPeak = Get absolute extremum: 0, 0, "None"
mixRms = Get root-mean-square: 0, 0
renderTime = stopwatch

if keep_individual_arcs = 0
    @cleanUpArcs
endif

# ---- Info summary ----
writeInfoLine: "=== UPIC Draw Synthesis v2.0 ==="
appendInfoLine: "Preset ", preset_name$, "   duration ", fixed$ (dur, 2), " s, ", sr, " Hz, ", outCh, " ch, frequency axis ", fixed$ (fLo, 0), "-", fixed$ (fHi, 0), " Hz (log)"
appendInfoLine: "Mass: spread ", fixed$ (spreadC, 0), " c, glissando dispersion ", fixed$ (dispFrac * 100, 0), " %, onset scatter ", fixed$ (onsetS * 1000, 0), " ms, gain scatter ", fixed$ (gainScatDb, 1), " dB, stereo width ", fixed$ (widthF * 100, 0), " %"
appendInfoLine: "GENDYN: mutation ", fixed$ (sigA * 100, 0), " %, drift ", fixed$ (sigP * 100, 0), " %, correlation ", fixed$ (rho, 2), " (pull ", fixed$ (1 - rho, 2), "/frame), rate ", fixed$ (mutRate, 0), " Hz"
appendInfoLine: "Population: density coupling ", fixed$ (densC * 100, 0), " %, register field ", regName$[regField], "   seed ", baseSeed
appendInfoLine: ""
for k to nArcs
    if nP[1, k] = 0
        appendInfoLine: "Arc ", k, ": empty (not rendered)"
    else
        fMin = pV[1, k, 1]
        fMax = pV[1, k, 1]
        for i to nP[1, k]
            fMin = min (fMin, pV[1, k, i])
            fMax = max (fMax, pV[1, k, i])
        endfor
        @polyStats: k
        appendInfoLine: "Arc ", k, ": ", realName$[arcReal[k]], ", ", vN[k], " voice(s)"
        appendInfoLine: "   pitch arc   ", nP[1, k], " vertices, drawn ", fixed$ (fMin, 1), "-", fixed$ (fMax, 1), " Hz"
        if vN[k] > 1
            gMin = 0
            gMax = 0
            cMin = 0
            cMax = 0
            for i to vN[k]
                gMin = min (gMin, vG[k, i])
                gMax = max (gMax, vG[k, i])
                cMin = min (cMin, vC[k, i])
                cMax = max (cMax, vC[k, i])
            endfor
            appendInfoLine: "               members: offsets ", fixed$ (cMin, 0), "..", fixed$ (cMax, 0), " c, glissando factors ", fixed$ (1 + gMin, 2), "..", fixed$ (1 + gMax, 2)
        endif
        @fmt3: pT[1, k, 1]
        spanA$ = fmt3.result$
        @fmt3: pT[1, k, nP[1, k]]
        spanB$ = fmt3.result$
        @fmt3: pT[1, k, nP[1, k]] - pT[1, k, 1]
        appendInfoLine: "               drawn span ", spanA$, "-", spanB$, " s (", fmt3.result$, " s); pitch held outside it"
        appendInfoLine: "   waveform    ", nP[2, k], " breakpoints (attractor), drawn DC ", fixed$ (polyStats.mean, 3), " removed per frame"
        if nP[3, k] = 0
            appendInfoLine: "   envelope    none (0 dB, all members active)"
        else
            appendInfoLine: "   envelope    ", nP[3, k], " points (gain + density)"
        endif
        appendInfoLine: "   level       peak ", fixed$ (arcPeak[k], 3), ", RMS ", fixed$ (arcRms[k], 4)
    endif
endfor
appendInfoLine: ""
appendInfoLine: "Mix: ", mixArcs, " arcs summed, raw peak ", fixed$ (mixPeakRaw, 3), "; peak guard ", fixed$ (guardDb, 1), " dB; final peak ", fixed$ (mixPeak, 3), ", RMS ", fixed$ (mixRms, 4), " (not normalised)"
appendInfoLine: "Render time ", fixed$ (renderTime, 1), " s"
appendInfoLine: "Output: Sound UPIC_mix"

finalView = 1
status$ = "Playing the mix."
@drawAll
selectObject: mixSnd
Play
