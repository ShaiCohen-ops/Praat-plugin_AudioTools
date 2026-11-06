# ============================================================
# Praat AudioTools - Fractal_Spectral_Hologram.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.0 (2026) - complete engine redesign, native Praat only:
#   - REPLACED the single whole-file FFT + magnitude remapping + original
#     phase + iFFT engine. That engine could only re-weight bins that
#     already existed and re-used unrelated source phases, so the source
#     always dominated and "new" components were noise-like coloration.
#   - NEW ANALYSIS: time-resolved Gaussian-window spectrogram (Praat
#     To Spectrogram), vectorized local-maximum detection, log-parabolic
#     peak interpolation (exact for a Gaussian window), amplitude
#     calibration against a reference sine measured at run time.
#   - NEW SYNTHESIS: genuine additive resynthesis. Each analysed partial
#     f(t) drives phase-continuous oscillators at the fractal frequencies
#       f_k(t) = c + z^k (f(t) - c)
#     Phase is integrated sample by sample (in-place recursive Formula),
#     so every generated component is a real, coherent sinusoid.
#   - THREE SOURCE MODES: Tracked partials (frame-to-frame partial
#     tracking), Struck modes (captured modal set excited by onsets in
#     each mode's own band -> resonator bank), Frozen modes (captured
#     spectrum sustained over the whole output).
#   - INDEPENDENT TIME BEHAVIOUR per copy level: attack, ring (resonance
#     persistence, frequency-dependent), delayed spectral repetitions,
#     progressive fractal depth, zoom drift (spectral expansion /
#     contraction over time), deterministic fragmentation.
#   - SEPARATE DIFFUSE PATH: each generated component can be rendered as
#     a narrow noise band of explicit width in Hz (Blur_Hz) instead of a
#     line. Diffuse_mix = 0 gives a coherent output with no noise at all.
#   - SHARPEN is now prominence-based: each peak is weighted by its height
#     above a Hz-defined (~250 Hz) local spectral envelope, bounded at
#     +12 dB, so numerical-floor maxima cannot be amplified.
#   - OUTPUT: wet is level-matched to the dry RMS (no peak normalization);
#     Dry_wet = 0 returns an exact copy of the original; Dry_wet = 1
#     contains no dry signal. A safety gain is applied only if the mix
#     would exceed 0.99 and is reported.
#   - Optional tail (Tail_s) so rings and echoes are not truncated.
#   - Visualization: source vs pure-wet spectrograms on one time axis and
#     the measured map of every generated component f_k(t).
#
# Description:
#   Generates crystalline, metallic and fractal textures from a Sound by
#   synthesizing geometrically mapped copies of its partials. The term
#   "hologram" is a musical metaphor, not an optical holography model.
#   "Fractal" means self-similar geometric copy levels of one analysed
#   structure (f -> c + z^k (f - c)); it is not recursive feedback.
#
# Usage:
#   Select one mono or stereo Sound object in Praat and run this script.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Fractal Spectral Hologram v2.0
    optionmenu Preset: 2
        option Custom (opens parameter dialogs)
        option Subtle Shimmer (octave partial halo)
        option Crystal Echo (delayed geometric copies)
        option Fractal Storm (two-way expanding cluster)
        option Holographic Freeze (captured spectrum sustained)
        option Metallic Bell (struck inharmonic modes)
        option Glass Fracture (fragmented bright partials)
    real Dry_wet 0.8
    comment (0 = original unchanged, 1 = synthesized signal only)
    boolean Edit_parameters 0
    comment (opens the full parameter set of the preset for editing)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PARAMETER SETS
# ============================================================
# Custom defaults (also the base every preset starts from)
source_mode = 1
window_ms = 40
hop_ms = 10
partials = 16
sharpen = 0.5
min_track_frames = 3
fractal_zoom = 1.5
zoom_end = 1.5
zoom_centre_Hz = 600
fractal_levels = 3
level_decay = 0.6
mirror_levels = 0
source_level = 0.5
depth_growth = 0
attack_ms = 20
ring_s = 1.0
ring_tilt = 0.3
echo_delay_s = 0
fragment_rate_Hz = 0
fragment_density = 0.4
diffuse_mix = 0
blur_Hz = 40
tail_s = 1.0
capture_time_s = 0
capture_region_s = 0.5

if preset = 2
    presetName$ = "SubtleShimmer"
    # pure frequency scaling (c = 0, z = 2): octave halo over resynthesized partials
    fractal_zoom = 2.0
    zoom_end = 2.0
    zoom_centre_Hz = 0
    fractal_levels = 2
    level_decay = 0.45
    source_level = 0.7
    attack_ms = 40
    ring_s = 1.2
    ring_tilt = 0.4
    diffuse_mix = 0.15
    blur_Hz = 25
    tail_s = 0.6
    sharpen = 0.6
    min_track_frames = 4
elsif preset = 3
    presetName$ = "CrystalEcho"
    # each copy level arrives 170 ms later than the previous one and rings
    fractal_zoom = 1.5
    zoom_end = 1.5
    zoom_centre_Hz = 400
    fractal_levels = 4
    level_decay = 0.72
    source_level = 0
    attack_ms = 5
    ring_s = 2.0
    ring_tilt = 0.6
    echo_delay_s = 0.17
    diffuse_mix = 0.05
    blur_Hz = 20
    tail_s = 1.8
    sharpen = 1.0
    partials = 12
elsif preset = 4
    presetName$ = "FractalStorm"
    # expansion AND contraction copies, zoom grows 1.3 -> 1.75, levels enter progressively
    fractal_zoom = 1.3
    zoom_end = 1.75
    zoom_centre_Hz = 700
    fractal_levels = 4
    level_decay = 0.78
    mirror_levels = 1
    source_level = 0.3
    depth_growth = 1.0
    attack_ms = 25
    ring_s = 1.2
    ring_tilt = 0.3
    echo_delay_s = 0.06
    diffuse_mix = 0.45
    blur_Hz = 90
    tail_s = 1.5
    sharpen = 0.3
    min_track_frames = 2
    partials = 14
elsif preset = 5
    presetName$ = "HolographicFreeze"
    # capture the loudest 0.4 s, sustain it for the whole output, let depth and zoom evolve
    source_mode = 3
    capture_time_s = 0
    capture_region_s = 0.4
    fractal_zoom = 1.25
    zoom_end = 1.4
    zoom_centre_Hz = 300
    fractal_levels = 4
    level_decay = 0.7
    source_level = 1.0
    depth_growth = 0.8
    attack_ms = 1500
    ring_s = 4.0
    ring_tilt = 0.2
    diffuse_mix = 0.3
    blur_Hz = 12
    tail_s = 2.5
    sharpen = 0.8
elsif preset = 6
    presetName$ = "MetallicBell"
    # modal set from the whole file, golden-ratio copies, struck by band onsets
    source_mode = 2
    capture_region_s = 0
    fractal_zoom = 1.618
    zoom_end = 1.618
    zoom_centre_Hz = 90
    fractal_levels = 3
    level_decay = 0.7
    source_level = 0.8
    ring_s = 8.0
    ring_tilt = 0.7
    diffuse_mix = 0
    tail_s = 3.0
    sharpen = 1.2
    partials = 10
elsif preset = 7
    presetName$ = "GlassFracture"
    # bright wide-ratio copies chopped into short deterministic shards
    fractal_zoom = 2.3
    zoom_end = 2.3
    zoom_centre_Hz = 150
    fractal_levels = 3
    level_decay = 0.8
    source_level = 0
    attack_ms = 3
    ring_s = 0.4
    ring_tilt = 0.5
    fragment_rate_Hz = 11
    fragment_density = 0.38
    diffuse_mix = 0
    tail_s = 0.5
    sharpen = 1.5
    min_track_frames = 1
    partials = 12
else
    presetName$ = "Custom"
endif

# ---- Parameter dialogs (Custom always; any preset on request) ----
if preset = 1 or edit_parameters
    beginPause: "Fractal Spectral Hologram - analysis and fractal map"
        comment: "Source of the partials that are copied"
        choice: "Source_mode", source_mode
            option: "Tracked partials (follows the source)"
            option: "Struck modes (resonator bank)"
            option: "Frozen modes (captured spectrum sustained)"
        positive: "Window_ms", string$(window_ms)
        positive: "Hop_ms", string$(hop_ms)
        natural: "Partials", string$(partials)
        real: "Sharpen", string$(sharpen)
        natural: "Min_track_frames", string$(min_track_frames)
        comment: "Fractal map  f_k = c + z^k (f - c)"
        positive: "Fractal_zoom", string$(fractal_zoom)
        positive: "Zoom_end", string$(zoom_end)
        real: "Zoom_centre_Hz", string$(zoom_centre_Hz)
        integer: "Fractal_levels", string$(fractal_levels)
        real: "Level_decay", string$(level_decay)
        boolean: "Mirror_levels", mirror_levels
        real: "Source_level", string$(source_level)
        real: "Depth_growth", string$(depth_growth)
    clicked = endPause: "Cancel", "Continue", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
    beginPause: "Fractal Spectral Hologram - time and texture"
        comment: "Envelopes of the generated components"
        real: "Attack_ms", string$(attack_ms)
        real: "Ring_s", string$(ring_s)
        comment: "(Ring_s = T60 at 1 kHz; tilt shortens higher, lengthens lower copies)"
        real: "Ring_tilt", string$(ring_tilt)
        real: "Echo_delay_s", string$(echo_delay_s)
        real: "Fragment_rate_Hz", string$(fragment_rate_Hz)
        real: "Fragment_density", string$(fragment_density)
        comment: "Diffuse path (0 = coherent lines only)"
        real: "Diffuse_mix", string$(diffuse_mix)
        positive: "Blur_Hz", string$(blur_Hz)
        comment: "Output tail and mode capture (0 = auto / whole file)"
        real: "Tail_s", string$(tail_s)
        real: "Capture_time_s", string$(capture_time_s)
        real: "Capture_region_s", string$(capture_region_s)
    clicked = endPause: "Cancel", "Run", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
    if preset <> 1
        presetName$ = presetName$ + "Edited"
    endif
endif

# ============================================================
# SETUP AND VALIDATION (no objects are created before this passes)
# ============================================================
selectObject: originalID
numChannels = Get number of channels
srcDur = Get total duration
sampleRate = Get sampling frequency
origStart = Get start time
nSrc = Get number of samples
nyq = sampleRate / 2

if numChannels > 2
    exitScript: "Only mono and stereo Sounds are supported (this one has "
    ... + string$(numChannels) + " channels). Extract the channels you need first."
endif
if sampleRate < 4000
    exitScript: "Sample rate must be at least 4000 Hz."
endif
if dry_wet < 0 or dry_wet > 1
    exitScript: "Dry/Wet must be between 0 and 1."
endif
if window_ms < 10 or window_ms > 200
    exitScript: "Window_ms must be between 10 and 200."
endif
if hop_ms < 2 or hop_ms > window_ms
    exitScript: "Hop_ms must be at least 2 and not larger than Window_ms."
endif
if partials < 1 or partials > 40
    exitScript: "Partials must be between 1 and 40."
endif
if sharpen < 0 or sharpen > 4
    exitScript: "Sharpen must be between 0 and 4."
endif
if min_track_frames < 1 or min_track_frames > 50
    exitScript: "Min_track_frames must be between 1 and 50."
endif
if fractal_zoom < 0.25 or fractal_zoom > 4 or zoom_end < 0.25 or zoom_end > 4
    exitScript: "Fractal_zoom and Zoom_end must be between 0.25 and 4."
endif
if zoom_centre_Hz < 0 or zoom_centre_Hz > nyq
    exitScript: "Zoom_centre_Hz must be between 0 and Nyquist (" + fixed$(nyq, 0) + " Hz)."
endif
if fractal_levels < 0 or fractal_levels > 8
    exitScript: "Fractal_levels must be between 0 and 8."
endif
if level_decay < 0 or level_decay > 1.5
    exitScript: "Level_decay must be between 0 and 1.5."
endif
if source_level < 0 or source_level > 2
    exitScript: "Source_level must be between 0 and 2."
endif
if depth_growth < 0 or depth_growth > 4
    exitScript: "Depth_growth must be between 0 and 4."
endif
if attack_ms < 0 or attack_ms > 10000 or ring_s < 0 or ring_s > 60
    exitScript: "Attack_ms must be 0..10000 and Ring_s (T60) 0..60."
endif
if ring_tilt < 0 or ring_tilt > 2
    exitScript: "Ring_tilt must be between 0 and 2."
endif
if echo_delay_s < 0 or echo_delay_s > 2
    exitScript: "Echo_delay_s must be between 0 and 2."
endif
if fragment_rate_Hz < 0 or fragment_rate_Hz > 100 or fragment_density < 0 or fragment_density > 1
    exitScript: "Fragment_rate_Hz must be 0..100 and Fragment_density 0..1."
endif
if diffuse_mix < 0 or diffuse_mix > 1
    exitScript: "Diffuse_mix must be between 0 and 1."
endif
if blur_Hz < 2 or blur_Hz > 2000
    exitScript: "Blur_Hz must be between 2 and 2000."
endif
if tail_s < 0 or tail_s > 30
    exitScript: "Tail_s must be between 0 and 30."
endif
if capture_time_s < 0 or capture_region_s < 0
    exitScript: "Capture time and region must be 0 or positive."
endif
if srcDur < 2 * window_ms / 1000
    exitScript: "Sound is too short for a " + string$(window_ms) + " ms analysis window."
endif

# ---- Derived quantities ----
hopS = hop_ms / 1000
winS = window_ms / 1000
physWin = 2 * winS
anaMaxHz = min(0.95 * nyq, 12000)
tailN = round(tail_s * sampleRate)
nOut = nSrc + tailN
outDur = nOut / sampleRate
omegaDt = 2 * pi / sampleRate
zoomDynamic = abs(zoom_end - fractal_zoom) > 1e-6
zoomRatio = zoom_end / fractal_zoom
floorDb = 70
tolRel = 0.035

# Ring_s is the T60 (60 dB decay time) at 1 kHz; the envelope time constant is T60 / ln(1000).
ringTau = ring_s / 6.9078
if ring_s > 0
    if ring_tilt > 0
        tauMax = ringTau * min(3, 20 ^ ring_tilt)
    else
        tauMax = ringTau
    endif
    relFrames = max(1, min(500, ceiling(4.6 * tauMax / hopS) + 1))
else
    relFrames = 1
endif
if attack_ms / 1000 > hopS
    attCoef = 1 - exp(-hopS / (attack_ms / 1000))
else
    attCoef = 1
endif
if diffuse_mix > 0
    lineW = cos(diffuse_mix * pi / 2)
    bandW = sin(diffuse_mix * pi / 2)
else
    lineW = 1
    bandW = 0
endif

# ---- Copy levels: exponent p, delay (frames), weight ----
maxLev = 1 + 2 * fractal_levels
levP# = zero#(maxLev)
levDF# = zero#(maxLev)
levW# = zero#(maxLev)
nLev = 0
if source_level > 0
    nLev = 1
    levP#[1] = 0
    levDF#[1] = 0
    levW#[1] = source_level
endif
for k to fractal_levels
    wk = level_decay ^ k
    if wk > 1e-4
        nLev = nLev + 1
        levP#[nLev] = k
        levDF#[nLev] = round(k * echo_delay_s / hopS)
        levW#[nLev] = wk
        if mirror_levels
            nLev = nLev + 1
            levP#[nLev] = -k
            levDF#[nLev] = round(k * echo_delay_s / hopS)
            levW#[nLev] = wk
        endif
    endif
endfor
if nLev = 0
    exitScript: "Nothing to synthesize: Source_level is 0 and no copy level has weight (raise Fractal_levels or Level_decay)."
endif
maxDelayS = fractal_levels * echo_delay_s

# Earliest time each level can sound under depth growth. The ramp of level |p|
# is exactly 0 until (|p| - 1) * Depth_growth / Fractal_levels of the source
# duration; the envelope is interpolated from control frames, so start 3 frames
# early to include every sample where it can be non-zero. Used only to skip
# samples whose contribution is exactly 0 (no audible or numerical change).
levStart# = zero#(maxLev)
for li to nLev
    if depth_growth > 0 and levP#[li] <> 0
        levStart#[li] = max(0, (abs(levP#[li]) - 1) * depth_growth / fractal_levels * srcDur - 3 * hopS)
    endif
endfor

if source_mode = 1
    modeName$ = "tracked partials"
elsif source_mode = 2
    modeName$ = "struck modes"
else
    modeName$ = "frozen modes"
endif

clearinfo
writeInfoLine: "=== Fractal Spectral Hologram v2.0 ==="
appendInfoLine: "Input: ", originalName$, " (", fixed$(srcDur, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$, "   source mode: ", modeName$
appendInfoLine: "Analysis: Gaussian window ", window_ms, " ms, hop ", hop_ms, " ms, ",
    ... partials, " partials, sharpen ", fixed$(sharpen, 2), ", analysis band 0-", fixed$(anaMaxHz, 0), " Hz"
appendInfoLine: "Map: f_k = ", fixed$(zoom_centre_Hz, 1), " + z^k (f - ", fixed$(zoom_centre_Hz, 1), "),  z = ",
    ... fixed$(fractal_zoom, 3), if zoomDynamic then " -> " + fixed$(zoom_end, 3) else "" fi
appendInfoLine: "Levels (p : weight : delay s):"
for li to nLev
    appendInfoLine: "   p = ", levP#[li], " : ", fixed$(levW#[li], 3), " : ", fixed$(levDF#[li] * hopS, 3)
endfor
appendInfoLine: "Envelopes: attack ", attack_ms, " ms, ring T60 ", ring_s, " s at 1 kHz (tilt ", ring_tilt,
    ... "), depth growth ", depth_growth, ", fragments ", fragment_rate_Hz, " Hz @ ", fragment_density
appendInfoLine: "Diffuse: mix ", fixed$(diffuse_mix, 2), ", band width ", blur_Hz, " Hz   tail ", tail_s, " s"
appendInfoLine: "Dry/Wet: ", fixed$((1 - dry_wet) * 100, 0), "/", fixed$(dry_wet * 100, 0), "%"
appendInfoLine: ""

tStart = stopwatch
tTotal = 0

# ============================================================
# PROCEDURES
# ============================================================
# Log-parabolic peak interpolation on three power values.
# Exact for a Gaussian analysis window (its log spectrum is a parabola).
# Ring release (frames) for a track ending at frequency .f: long enough for the
# slowest AUDIBLE copy of this track to decay by 40 dB (4.6 time constants).
# Copies mapped below 25 Hz or above 0.95 Nyquist are muted and do not count.
procedure trackRelease: .f
    .tau = 0
    if ring_s > 0
        for .li to nLev
            for .zi to 2
                .z = if .zi = 1 then fractal_zoom else zoom_end fi
                .fm = zoom_centre_Hz + .z ^ levP#[.li] * (.f - zoom_centre_Hz)
                if .fm >= 25 and .fm <= 0.95 * nyq
                    .tau = max(.tau, ringTau * min(3, (1000 / max(50, .fm)) ^ ring_tilt))
                endif
            endfor
        endfor
    endif
    .frames = max(1, min(relFrames, ceiling(4.6 * .tau / hopS) + 1))
endproc

# Append a synthesis region for slot .s (control columns), merging with that
# slot's previous region when they overlap.
procedure addRegion: .s, .a, .b, .fl, .fh
    .a = max(1, .a)
    .last = lastReg#[.s]
    if .last > 0 and .a <= regB#[.last]
        regB#[.last] = max(regB#[.last], .b)
        regFl#[.last] = min(regFl#[.last], .fl)
        regFh#[.last] = max(regFh#[.last], .fh)
    else
        nReg = nReg + 1
        regS#[nReg] = .s
        regA#[nReg] = .a
        regB#[nReg] = .b
        regFl#[nReg] = .fl
        regFh#[nReg] = .fh
        lastReg#[.s] = nReg
    endif
endproc

procedure parab: .a, .b, .c
    .la = 10 * log10(max(.a, 1e-300))
    .lb = 10 * log10(max(.b, 1e-300))
    .lc = 10 * log10(max(.c, 1e-300))
    .den = .la - 2 * .lb + .lc
    if .den < 0
        .p = 0.5 * (.la - .lc) / .den
        .p = max(-0.5, min(0.5, .p))
    else
        .p = 0
    endif
    .power = 10 ^ ((.lb - 0.25 * (.la - .lc) * .p) / 10)
endproc

# ============================================================
# AMPLITUDE CALIBRATION (reference sine, amplitude 1, 1000 Hz)
# ============================================================
calSnd = Create Sound from formula: "fsh_cal", 1, 0, 4 * physWin + 0.2, sampleRate, "sin(2*pi*1000*x)"
calSpg = To Spectrogram: winS, anaMaxHz, hopS, 10, "Gaussian"
calM = To Matrix
calCols = Get number of columns
calV# = Get all values in column: round(calCols / 2)
calI = imax(calV#)
@parab: calV#[calI - 1], calV#[calI], calV#[calI + 1]
calPower = parab.power
removeObject: calSnd, calSpg, calM

# ============================================================
# DIFFUSE NOISE SOURCE (deterministic seed; only if used)
# ============================================================
nz = 0
nzN = 1
if diffuse_mix > 0
    random_initializeWithSeedUnsafelyButPredictably (271828)
    # Each copy reads this buffer at its own offset with wrap-around, so the
    # buffer must be CIRCULAR: its first 0.25 s is an equal-power crossfade with
    # the filtered noise that continues past the end, making the wrap seamless.
    nzX = round(0.25 * sampleRate)
    nzRaw = Create Sound from formula: "fsh_noise_raw", 1, 0, (nOut + nzX) / sampleRate, sampleRate, "randomGauss(0, 1)"
    random_initializeSafelyAndUnpredictably ()
    nzF = Filter (pass Hann band): 0, blur_Hz / 2, max(1, blur_Hz / 4)
    nz = Create Sound from formula: "fsh_noise", 1, 0, outDur, sampleRate,
        ... "if col <= nzX then sin(pi / 2 * (col - 0.5) / nzX) * object[nzF, 1, col]"
        ... + " + cos(pi / 2 * (col - 0.5) / nzX) * object[nzF, 1, col + nOut] else object[nzF, 1, col] fi"
    removeObject: nzRaw, nzF
    nzRms = Get root-mean-square: 0, 0
    if nzRms > 0
        Formula: "self / nzRms"
    endif
    nzN = Get number of samples
endif

# ============================================================
# PER-CHANNEL ANALYSIS + SYNTHESIS
# ============================================================
viz_fAll = 0
viz_eAll = 0
viz_src = 0
viz_S = 0
wetCh# = zero#(numChannels)

for ch to numChannels
    appendInfoLine: "Channel ", ch, ":"

    # ---- Working copy, zero-padded so analysis frames cover the edges ----
    selectObject: originalID
    chSnd = Extract one channel: ch
    Shift times to: "start time", 0
    padN = ceiling(physWin * sampleRate)
    anaSnd = Create Sound from formula: "fsh_ana", 1, -padN / sampleRate, (nSrc + padN) / sampleRate,
        ... sampleRate, "object[chSnd, 1, col - padN]"

    # ---- Time-resolved analysis ----
    spg = To Spectrogram: winS, anaMaxHz, hopS, 10, "Gaussian"
    anaT1 = Get time from frame number: 1
    anaStep = Get time step
    nFr = Get number of frames
    rawM = To Matrix
    Rename: "fsh_raw"
    removeObject: spg, anaSnd
    binHz = Get row distance
    anaY1 = Get y of row: 1
    nRows = Get number of rows
    gMax = Get maximum
    floorP = gMax * 10 ^ (-floorDb / 10)

    # ---- Local spectral envelope: 3 box passes of ~250 Hz (prefix sums) ----
    boxH = max(1, round(120 / binHz))
    csM = Copy: "fsh_cs"
    envM = Copy: "fsh_env"
    for pass to 3
        selectObject: csM
        Formula: "object[envM, row, col]"
        Formula: "if row = 1 then self else self[row - 1, col] + self fi"
        selectObject: envM
        Formula: "(object[csM, min(row + boxH, nRows), col] - (if row - boxH - 1 >= 1 then object[csM, row - boxH - 1, col] else 0 fi))"
            ... + " / (min(row + boxH, nRows) - max(row - boxH - 1, 0))"
    endfor
    removeObject: csM

    # ---- Control grid (frame rate), covering the whole output incl. tail ----
    ctlStart = anaT1 - anaStep / 2
    nCtl = max(nFr + 2, ceiling((outDur - ctlStart) / anaStep) + 2)
    ctlEnd = ctlStart + nCtl * anaStep
    ctlRate = 1 / anaStep

    nSlots = 0
    slotFirst# = zero#(1)
    statLine$ = ""
    # Synthesis regions (control columns): only where a slot actually sounds.
    # Each kept track adds [birth - 2, end of ring + echo delays + 2];
    # overlapping regions of the same slot are merged so no sample is synthesized twice.
    maxDelayF = round(maxDelayS / anaStep)
    maxReg = round(nFr * partials / min_track_frames) + 2 * partials + 10
    regS# = zero#(maxReg)
    regA# = zero#(maxReg)
    regB# = zero#(maxReg)
    regFl# = zero#(maxReg)
    regFh# = zero#(maxReg)
    nReg = 0

    if source_mode = 1
        # ====================================================
        # TRACKED PARTIALS
        # ====================================================
        # Peak mask + prominence weighting (sharpen) in ONE vectorized pass.
        # Score = power * G^2, G = min(4, (sqrt(power/env)/2)^sharpen)
        selectObject: rawM
        scoreM = Copy: "fsh_score"
        Formula: "if row > 1 and row < nRows and self > floorP and self > object[rawM, row - 1, col]"
            ... + " and self >= object[rawM, row + 1, col]"
            ... + " then self * min(16, (self / (4 * max(object[envM, row, col], 1e-300))) ^ sharpen) else 0 fi"

        nSlots = min(48, round(1.5 * partials) + 4)
        slotF# = zero#(nSlots)
        slotState# = zero#(nSlots)
        slotStart# = zero#(nSlots)
        slotRel# = zero#(nSlots)
        slotFirst# = zero#(nSlots)
        lastReg# = zero#(nSlots)
        slotFlo# = zero#(nSlots)
        slotFhi# = zero#(nSlots)
        matchPen# = zero#(nSlots)
        matched# = zero#(nSlots)
        justFreed# = zero#(nSlots)
        pkF# = zero#(partials)
        pkA# = zero#(partials)
        fr## = zero##(nSlots, nCtl)
        ex## = zero##(nSlots, nCtl)
        tolMinHz = max(1.5 * binHz, 12)
        nBirth = 0
        nSteal = 0
        nShort = 0
        nPeaksTotal = 0

        for j to nFr
            selectObject: scoreM
            sc# = Get all values in column: j
            selectObject: rawM
            rw# = Get all values in column: j

            # releases advance; slots whose ring has ended are reset and freed
            for s to nSlots
                justFreed#[s] = 0
                matched#[s] = 0
                if slotState#[s] = 2
                    slotRel#[s] = slotRel#[s] - 1
                    if slotRel#[s] <= 0
                        slotState#[s] = 0
                        ex##[s, j] = -1
                        justFreed#[s] = 1
                    endif
                endif
                if slotState#[s] = 1
                    matchPen#[s] = 0
                else
                    matchPen#[s] = 1e30
                endif
            endfor

            # strongest prominent peaks of this frame, interpolated
            nPk = 0
            goOn = 1
            while goOn and nPk < partials
                iPk = imax(sc#)
                if sc#[iPk] <= 0
                    goOn = 0
                else
                    @parab: rw#[iPk - 1], rw#[iPk], rw#[iPk + 1]
                    nPk = nPk + 1
                    pkF#[nPk] = anaY1 + (iPk - 1 + parab.p) * binHz
                    pkA#[nPk] = sqrt(parab.power / calPower) * sqrt(sc#[iPk] / rw#[iPk])
                    sc#[iPk] = 0
                endif
            endwhile
            nPeaksTotal = nPeaksTotal + nPk

            # continue existing tracks (strongest peaks choose first) or give birth
            for q to nPk
                fp = pkF#[q]
                dist# = abs#(slotF# - fp) + matchPen#
                sB = imin(dist#)
                if dist#[sB] < max(tolMinHz, tolRel * fp)
                    slotF#[sB] = fp
                    matched#[sB] = 1
                    matchPen#[sB] = 1e30
                    ex##[sB, j] = pkA#[q]
                    slotFlo#[sB] = min(slotFlo#[sB], fp)
                    slotFhi#[sB] = max(slotFhi#[sB], fp)
                else
                    sN = 0
                    for s to nSlots
                        if sN = 0 and slotState#[s] = 0 and justFreed#[s] = 0
                            sN = s
                        endif
                    endfor
                    if sN = 0
                        bestRel = 1e30
                        for s to nSlots
                            if slotState#[s] = 2 and slotRel#[s] < bestRel
                                bestRel = slotRel#[s]
                                sN = s
                            endif
                        endfor
                        if sN > 0
                            nSteal = nSteal + 1
                            if j > 1
                                ex##[sN, j - 1] = -1
                            endif
                        endif
                    endif
                    if sN > 0
                        slotState#[sN] = 1
                        slotF#[sN] = fp
                        slotStart#[sN] = j
                        slotFlo#[sN] = fp
                        slotFhi#[sN] = fp
                        matched#[sN] = 1
                        matchPen#[sN] = 1e30
                        ex##[sN, j] = pkA#[q]
                        if j > 1
                            fr##[sN, j - 1] = fp
                        endif
                        if slotFirst#[sN] = 0
                            slotFirst#[sN] = j
                        endif
                        nBirth = nBirth + 1
                    endif
                endif
            endfor

            # unmatched tracks: too short -> erased; otherwise -> ring (release)
            for s to nSlots
                if slotState#[s] = 1 and matched#[s] = 0
                    if j - slotStart#[s] < min_track_frames
                        for jj from slotStart#[s] to j - 1
                            ex##[s, jj] = 0
                        endfor
                        ex##[s, j] = -1
                        slotState#[s] = 0
                        nShort = nShort + 1
                    else
                        slotState#[s] = 2
                        @trackRelease: slotF#[s]
                        slotRel#[s] = trackRelease.frames
                        @addRegion: s, slotStart#[s] - 2, j + trackRelease.frames + maxDelayF + 2, slotFlo#[s], slotFhi#[s]
                    endif
                endif
                fr##[s, j] = slotF#[s]
            endfor
        endfor

        # end of analysis: close tracks, hold frequencies through the tail
        for s to nSlots
            if slotState#[s] = 1
                if nFr + 1 - slotStart#[s] < min_track_frames
                    for jj from slotStart#[s] to nFr
                        ex##[s, jj] = 0
                    endfor
                    nShort = nShort + 1
                else
                    @trackRelease: slotF#[s]
                    @addRegion: s, slotStart#[s] - 2, nFr + trackRelease.frames + maxDelayF + 2, slotFlo#[s], slotFhi#[s]
                    # explicit reset where the ring ends, so the synthesis region
                    # never cuts a still-sounding envelope
                    if nFr + 1 + trackRelease.frames <= nCtl
                        ex##[s, nFr + 1 + trackRelease.frames] = -1
                    endif
                endif
            elsif slotState#[s] = 2
                if nFr + 1 + slotRel#[s] <= nCtl
                    ex##[s, nFr + 1 + slotRel#[s]] = -1
                endif
            endif
            for c from nFr + 1 to nCtl
                fr##[s, c] = slotF#[s]
            endfor
        endfor
        removeObject: scoreM

        slotsUsed = 0
        for s to nSlots
            if slotFirst#[s] > 0
                slotsUsed = slotsUsed + 1
            endif
        endfor
        statLine$ = "  frames " + string$(nFr) + ", mean peaks/frame " + fixed$(nPeaksTotal / nFr, 1)
            ... + ", tracks born " + string$(nBirth) + ", erased short " + string$(nShort)
            ... + ", slots used " + string$(slotsUsed) + "/" + string$(nSlots) + ", steals " + string$(nSteal)

        frS = Create Sound from formula: "fsh_fr", nSlots, ctlStart, ctlEnd, ctlRate, "fr##[row, col]"
        exS = Create Sound from formula: "fsh_ex", nSlots, ctlStart, ctlEnd, ctlRate, "ex##[row, col]"
    else
        # ====================================================
        # CAPTURED MODAL SET (struck or frozen)
        # ====================================================
        if capture_region_s <= 0
            capT1 = 0
            capT2 = srcDur
        else
            capT = capture_time_s
            if capT <= 0
                selectObject: chSnd
                capInt = To Intensity: 100, 0, "yes"
                capT = Get time of maximum: 0, 0, "Parabolic"
                removeObject: capInt
                if capT = undefined
                    capT = srcDur / 2
                endif
            endif
            capT = min(srcDur, capT)
            capT1 = max(0, capT - capture_region_s / 2)
            capT2 = min(srcDur, capT + capture_region_s / 2)
        endif
        cA = max(1, min(nFr, round((capT1 - anaT1) / anaStep) + 1))
        cB = max(cA, min(nFr, round((capT2 - anaT1) / anaStep) + 1))
        avgRaw# = zero#(nRows)
        avgEnv# = zero#(nRows)
        for j from cA to cB
            selectObject: rawM
            v# = Get all values in column: j
            avgRaw# = avgRaw# + v#
            selectObject: envM
            v# = Get all values in column: j
            avgEnv# = avgEnv# + v#
        endfor
        avgRaw# = avgRaw# / (cB - cA + 1)
        avgEnv# = avgEnv# / (cB - cA + 1)
        capMax = max(avgRaw#)
        capFloor = capMax * 10 ^ (-floorDb / 10)

        modeF# = zero#(partials)
        modeA# = zero#(partials)
        nModes = 0
        fallback$ = ""
        if capMax > 0
            # pass 1: prominent peaks (>= 3 dB above the local envelope).
            # pass 2 (frozen only): any local maximum, so a noise snapshot freezes its own ripple.
            # Struck mode skips pass 2: random ripple of a flat spectrum is not a resonance.
            if source_mode = 3
                nPasses = 2
            else
                nPasses = 1
            endif
            for fbPass to nPasses
                if nModes = 0
                    if fbPass = 1
                        promMin = 2
                    else
                        promMin = 0
                        capFloor = capMax * 1e-4
                        fallback$ = " (weak structure: plain local maxima used)"
                    endif
                    cand# = zero#(nRows)
                    for b from 2 to nRows - 1
                        if avgRaw#[b] > avgRaw#[b - 1] and avgRaw#[b] >= avgRaw#[b + 1] and avgRaw#[b] > capFloor
                            prom = avgRaw#[b] / max(avgEnv#[b], 1e-300)
                            if prom >= promMin
                                cand#[b] = avgRaw#[b] * min(16, (prom / 4) ^ sharpen)
                            endif
                        endif
                    endfor
                    nModes = 0
                    goOn = 1
                    while goOn and nModes < partials
                        b = imax(cand#)
                        if cand#[b] <= 0
                            goOn = 0
                        else
                            @parab: avgRaw#[b - 1], avgRaw#[b], avgRaw#[b + 1]
                            nModes = nModes + 1
                            modeF#[nModes] = anaY1 + (b - 1 + parab.p) * binHz
                            modeA#[nModes] = sqrt(parab.power / calPower) * sqrt(cand#[b] / avgRaw#[b])
                            cand#[b] = 0
                        endif
                    endwhile
                endif
            endfor
            if nModes = 0
                # no usable spectral structure (impulse, white noise): nothing to capture
                fallback$ = " (no prominent peaks: FALLBACK harmonic set on 220 Hz)"
                nModes = 0
                for m to partials
                    if 220 * m < 0.9 * anaMaxHz
                        nModes = nModes + 1
                        modeF#[nModes] = 220 * m
                        modeA#[nModes] = sqrt(capMax / calPower) / m
                    endif
                endfor
            endif
        else
            fallback$ = " (silent capture region: no modes)"
        endif

        nSlots = max(1, nModes)
        slotFirst# = zero#(nSlots)
        brR# = zero#(nSlots)
        brT# = zero#(nSlots)
        modeAmax = 1e-30
        for m to nModes
            slotFirst#[m] = 1
            nReg = nReg + 1
            regS#[nReg] = m
            regA#[nReg] = 1
            regB#[nReg] = nCtl
            regFl#[nReg] = modeF#[m]
            regFh#[nReg] = modeF#[m]
            modeAmax = max(modeAmax, modeA#[m])
            brR#[m] = 0.05 + 0.13 * ((0.6180339887 * m) mod 1)
            brT#[m] = 2 * pi * ((0.7548776662 * m) mod 1)
        endfor
        modeList$ = ""
        for m to min(nModes, 8)
            modeList$ = modeList$ + fixed$(modeF#[m], 1) + " "
        endfor
        statLine$ = "  capture " + fixed$(capT1, 2) + "-" + fixed$(capT2, 2) + " s, modes "
            ... + string$(nModes) + fallback$ + ": " + modeList$ + if nModes > 8 then "..." else "" fi

        frS = Create Sound from formula: "fsh_fr", nSlots, ctlStart, ctlEnd, ctlRate,
            ... "if row <= nModes then modeF#[row] else 0 fi"
        if source_mode = 3
            # frozen: constant excitation over the source duration, then ring out
            exS = Create Sound from formula: "fsh_ex", nSlots, ctlStart, ctlEnd, ctlRate,
                ... "if row <= nModes and x >= 0 and x <= srcDur then modeA#[row] else 0 fi"
        else
            # struck: half-wave rectified rise of the band amplitude AT each mode's own frequency
            exS = Create Sound from formula: "fsh_ex", nSlots, ctlStart, ctlEnd, ctlRate,
                ... "if row <= nModes then sqrt(max(0, object(envM, x, modeF#[row])) / calPower) else 0 fi"
            bS = Copy: "fsh_band"
            selectObject: exS
            Formula: "max(0, object[bS, row, col] - object[bS, row, col - 1])"
            removeObject: bS
            strikeMax = Get maximum: 0, 0, "None"
            if strikeMax > 0
                Formula: "if row <= nModes then max(0, self - 0.04 * strikeMax) * sqrt(modeA#[row] / modeAmax) else 0 fi"
            endif
        endif
    endif
    removeObject: rawM, envM
    appendInfoLine: statLine$

    # ========================================================
    # COPY-LEVEL CONTROLS: frequency f_k(t) and envelope env_k(t)
    # channel layout: (level - 1) * nSlots + slot
    # ========================================================
    nAll = nSlots * nLev
    fAll = Create Sound from formula: "fsh_fAll", nAll, ctlStart, ctlEnd, ctlRate, "0"
    eAll = Create Sound from formula: "fsh_eAll", nAll, ctlStart, ctlEnd, ctlRate, "0"
    if ring_s > 0
        decay$ = "exp(-anaStep / (ringTau * min(3, (1000 / max(50, object[fAll, row, col])) ^ ring_tilt)))"
    else
        decay$ = "0"
    endif
    alias$ = "min(1, max(0, (0.95 * nyq - object[fAll, row, col]) / (0.1 * nyq)))"
        ... + " * min(1, max(0, (object[fAll, row, col] - 25) / 25))"
    for li to nLev
        lp = levP#[li]
        alp = abs(lp)
        ldf = levDF#[li]
        lw = levW#[li]
        off = (li - 1) * nSlots
        cFirst = off + 1
        cLast = off + nSlots
        zk = fractal_zoom ^ lp

        selectObject: fAll
        if lp = 0
            Formula (part): ctlStart - 1, ctlEnd + 1, cFirst, cLast, "object[frS, row - off, col]"
        elsif zoomDynamic
            Formula (part): ctlStart - 1, ctlEnd + 1, cFirst, cLast,
                ... "zoom_centre_Hz + (fractal_zoom * zoomRatio ^ min(1, max(0, x / srcDur))) ^ lp"
                ... + " * (object[frS, row - off, col - ldf] - zoom_centre_Hz)"
        else
            Formula (part): ctlStart - 1, ctlEnd + 1, cFirst, cLast,
                ... "zoom_centre_Hz + zk * (object[frS, row - off, col - ldf] - zoom_centre_Hz)"
        endif

        # envelope recursion (left to right, in place): attack / ring / reset
        selectObject: eAll
        tgt$ = "object[exS, row - off, col - ldf]"
        if source_mode = 2
            Formula (part): ctlStart - 1, ctlEnd + 1, cFirst, cLast,
                ... "if col = 1 then 0 else self[row, col - 1] * " + decay$ + " + max(0, " + tgt$ + ") fi"
        else
            Formula (part): ctlStart - 1, ctlEnd + 1, cFirst, cLast,
                ... "if col = 1 then 0 else if " + tgt$ + " < 0 then 0 else"
                ... + " if " + tgt$ + " > self[row, col - 1] then self[row, col - 1] + attCoef * (" + tgt$ + " - self[row, col - 1])"
                ... + " else max(" + tgt$ + ", self[row, col - 1] * " + decay$ + ") fi fi fi"
        endif

        # weights, alias/low-frequency fade, progressive depth, breathing
        mult$ = "self * lw * " + alias$
        if alp >= 1 and depth_growth > 0
            u$ = "min(1, max(0, (x / srcDur) * fractal_levels / depth_growth - (alp - 1)))"
            mult$ = mult$ + " * (" + u$ + ")^2 * (3 - 2 * (" + u$ + "))"
        endif
        if source_mode = 3
            mult$ = mult$ + " * (1 - 0.35 * (0.5 - 0.5 * cos(2 * pi * brR#[row - off] * x + brT#[row - off])))"
        endif
        Formula (part): ctlStart - 1, ctlEnd + 1, cFirst, cLast, mult$
    endfor

    # ========================================================
    # ADDITIVE SYNTHESIS: phase-continuous oscillators per slot
    # ========================================================
    if zoomDynamic
        nPh = nLev
    else
        nPh = 1
    endif
    ph = Create Sound from formula: "fsh_phase", nPh, 0, outDur, sampleRate, "0"
    outW = Create Sound from formula: "fsh_wet_ch" + string$(ch), 1, 0, outDur, sampleRate, "0"
    nSynth = 0
    synthSec = 0
    termSec = 0
    levOn# = zero#(nLev)
    for iReg to nReg
        sIdx = regS#[iReg]
        tA = max(0, ctlStart + (regA#[iReg] - 1) * anaStep)
        tB = min(outDur, ctlStart + regB#[iReg] * anaStep)
        if sIdx > 0
            # Skip copy levels that cannot sound in this region: mapped entirely
            # outside 25 Hz .. 0.95 Nyquist (muted by the alias/low fade), or not
            # yet entered when depth growth is active. The map is monotone in f and
            # in z, so the four corners (f range x zoom range) bound it exactly.
            nOn = 0
            for li to nLev
                lp = levP#[li]
                levOn#[li] = 1
                if lp <> 0
                    mLo = 1e30
                    mHi = -1e30
                    for zi to 2
                        zz = if zi = 1 then fractal_zoom else zoom_end fi
                        for fi2 to 2
                            ff = if fi2 = 1 then regFl#[iReg] else regFh#[iReg] fi
                            mv = zoom_centre_Hz + zz ^ lp * (ff - zoom_centre_Hz)
                            mLo = min(mLo, mv)
                            mHi = max(mHi, mv)
                        endfor
                    endfor
                    if mHi < 25 or mLo > 0.95 * nyq
                        levOn#[li] = 0
                    endif
                    if depth_growth > 0
                        if (tB / srcDur) * fractal_levels / depth_growth - (abs(lp) - 1) <= 0
                            levOn#[li] = 0
                        endif
                    endif
                else
                    if regFh#[iReg] < 25 or regFl#[iReg] > 0.95 * nyq
                        levOn#[li] = 0
                    endif
                endif
                nOn = nOn + levOn#[li]
            endfor
            if tB > tA and nOn > 0
                nSynth = nSynth + 1
                synthSec = synthSec + (tB - tA) * nOn
                # phase integration: phi[n] = phi[n-1] + 2 pi f(t) / sr
                selectObject: ph
                if zoomDynamic
                    for li to nLev
                        if levOn#[li]
                            Formula (part): tA, tB, li, li,
                                ... "self[row, col - 1] + omegaDt * object(fAll, x, (row - 1) * nSlots + sIdx)"
                        endif
                    endfor
                else
                    Formula (part): tA, tB, 1, 1, "self[1, col - 1] + omegaDt * object(frS, x, sIdx)"
                endif

                # Sum of all audible copy levels of this slot. Levels are written in
                # groups that share a start time: with depth growth, a level's output
                # term starts one control frame before its ramp leaves zero (levStart#).
                # Before that point its envelope is exactly 0, so the samples skipped
                # are ones where the full sum would have added exactly 0.0; the phase
                # integration above still runs over the whole region, so the phase of
                # an entering level is the same as if it had been computed throughout.
                expr$ = "self"
                grpStart = -1
                for li to nLev
                  if levOn#[li]
                    if levStart#[li] <> grpStart
                        if expr$ <> "self" and max(tA, grpStart) < tB
                            selectObject: outW
                            Formula (part): max(tA, grpStart), tB, 1, 1, expr$
                        endif
                        expr$ = "self"
                        grpStart = levStart#[li]
                    endif
                    termSec = termSec + max(0, tB - max(tA, grpStart))
                    lp = levP#[li]
                    chI = (li - 1) * nSlots + sIdx
                    theta = 2 * pi * ((0.6180339887 * (chI + 37 * ch)) mod 1)
                    if zoomDynamic
                        phase$ = "object[ph, " + string$(li) + ", col]"
                    elsif lp = 0
                        phase$ = "object[ph, 1, col]"
                    else
                        zkL = fractal_zoom ^ lp
                        dS = round(levDF#[li] * anaStep * sampleRate)
                        w0 = (1 - zkL) * 2 * pi * zoom_centre_Hz
                        phase$ = string$(zkL) + " * object[ph, 1, col - " + string$(dS) + "] + "
                            ... + string$(w0) + " * (x - " + string$(dS / sampleRate) + ")"
                    endif
                    term$ = "object(eAll, x, " + string$(chI) + ") * sin(" + phase$ + " + " + string$(theta) + ")"
                    if diffuse_mix > 0
                        nOff = round(nzN * ((0.7548776662 * chI + 0.5698402910 * ch) mod 1))
                        term$ = term$ + " * (lineW + bandW * object[nz, 1, ((col + " + string$(nOff) + ") mod nzN) + 1])"
                    endif
                    if fragment_rate_Hz > 0
                        fRate = fragment_rate_Hz * (0.75 + 0.5 * ((0.6180339887 * chI) mod 1))
                        fOff = (0.3819660113 * chI + 0.5 * ch) mod 1
                        fSeed = 17.31 * chI + 101.7 * ch
                        fAtt = max(1e-4, 0.003 * fRate)
                        u$ = "(x * " + string$(fRate) + " + " + string$(fOff) + ")"
                        term$ = term$ + " * (if ((abs(sin(floor(" + u$ + ") * 12.9898 + " + string$(fSeed)
                            ... + ")) * 43758.5453) mod 1) < fragment_density then min(1, (" + u$ + " - floor(" + u$ + "))/"
                            ... + string$(fAtt) + ") * exp(-4.6 * (" + u$ + " - floor(" + u$ + "))) else 0 fi)"
                    endif
                    expr$ = expr$ + " + " + term$
                  endif
                endfor
                if expr$ <> "self" and max(tA, grpStart) < tB
                    selectObject: outW
                    Formula (part): max(tA, grpStart), tB, 1, 1, expr$
                endif
            endif
        endif
    endfor
    removeObject: ph
    appendInfoLine: "  synthesis regions: ", nSynth, ", oscillator-seconds (all levels): ", fixed$(synthSec, 1),
        ... ", of which sounding (sin terms evaluated): ", fixed$(termSec, 1)
    wetCh#[ch] = outW

    if ch = 1 and draw_visualization
        viz_fAll = fAll
        viz_eAll = eAll
        viz_src = chSnd
        viz_S = nSlots
        removeObject: frS, exS
    else
        removeObject: frS, exS, fAll, eAll, chSnd
    endif
endfor
if nz > 0
    removeObject: nz
endif

# ============================================================
# WET ASSEMBLY, LEVEL MATCH, DRY/WET MIX
# ============================================================
if numChannels = 2
    selectObject: wetCh#[1]
    plusObject: wetCh#[2]
    wetID = Combine to stereo
    Rename: "fsh_wet"
    removeObject: wetCh#[1], wetCh#[2]
else
    wetID = wetCh#[1]
endif

selectObject: originalID
dryRms = Get root-mean-square: 0, 0
selectObject: wetID
wetRms = Get root-mean-square: 0, srcDur
wetNote$ = ""
if wetRms = undefined
    exitScript: "Internal error: the synthesized signal contains undefined values."
endif
if wetRms > 1e-12 and dryRms > 0
    gainW = dryRms / wetRms
else
    gainW = 1
    if wetRms <= 1e-12
        wetNote$ = "  (wet path produced no partials: input silent or without spectral peaks)"
    endif
endif
selectObject: wetID
# level match + a short raised-cosine fade at the very end of the WET signal only,
# so rings still sounding when the output (source + tail) ends do not stop abruptly
fadeT = min(0.05, outDur / 4)
Formula: "self * gainW * (if x > outDur - fadeT then 0.5 - 0.5 * cos(pi * (outDur - x) / fadeT) else 1 fi)"

safeGain = 1
if dry_wet = 0
    selectObject: originalID
    resultID = Copy: originalName$ + "_hologram_" + presetName$
else
    resultID = Create Sound from formula: originalName$ + "_hologram_" + presetName$, numChannels,
        ... origStart, origStart + outDur, sampleRate,
        ... "dry_wet * object[wetID, row, col] + (1 - dry_wet) * object[originalID, row, col]"
    rMax = Get maximum: 0, 0, "None"
    rMin = Get minimum: 0, 0, "None"
    outPeak = max(abs(rMax), abs(rMin))
    if outPeak > 0.99
        safeGain = 0.99 / outPeak
        Formula: "self * safeGain"
    endif
endif
selectObject: resultID
outRms = Get root-mean-square: 0, 0
if outRms = undefined
    exitScript: "Internal error: output contains undefined values."
endif

tTotal = stopwatch
processingTime = tTotal

appendInfoLine: ""
appendInfoLine: "Wet level match: x", fixed$(gainW, 4), " (wet RMS -> dry RMS ", fixed$(dryRms, 4), ")", wetNote$
if safeGain < 1
    appendInfoLine: "Safety gain applied to mix: ", fixed$(20 * log10(safeGain), 2), " dB (mix exceeded 0.99)"
endif
appendInfoLine: "Output duration: ", fixed$(outDur, 3), " s (source ", fixed$(srcDur, 3), " s + tail ", fixed$(outDur - srcDur, 3), " s)"
if dry_wet = 0
    appendInfoLine: "Dry/Wet = 0: output is an exact copy of the original."
endif

# ============================================================
# VISUALIZATION
# ============================================================
procedure clean: .s$
    .s$ = replace$(.s$, "\", "/", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
endproc

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    vizH = 8.1

    # generated-component controls of channel 1, and the frequency range they occupy
    selectObject: viz_fAll
    fMat = Down to Matrix
    selectObject: viz_eAll
    eMat = Down to Matrix
    eMax = Get maximum
    nVizCols = Get number of columns
    nVizRows = Get number of rows
    vDec = max(1, ceiling(nVizCols / 220))
    nVizPts = floor((nVizCols - 1) / vDec) + 1
    fTop = 0
    if eMax > 0
        thrTop = eMax * 10 ^ (-42 / 20)
        for r to nVizRows
            selectObject: eMat
            ev# = Get all values in row: r
            if max(ev#) >= thrTop
                selectObject: fMat
                fv# = Get all values in row: r
                for ip to nVizPts
                    c0 = 1 + (ip - 1) * vDec
                    if ev#[c0] >= thrTop and fv#[c0] > fTop and fv#[c0] < nyq
                        fTop = fv#[c0]
                    endif
                endfor
            endif
        endfor
    endif
    # frequency axis: 15 % above the highest audible component, in round steps
    vizFmax = max(2000, 1.15 * fTop)
    if vizFmax <= 4000
        vizFmax = 500 * ceiling(vizFmax / 500)
    elsif vizFmax <= 10000
        vizFmax = 1000 * ceiling(vizFmax / 1000)
    else
        vizFmax = 2000 * ceiling(vizFmax / 2000)
    endif
    vizFmax = min(vizFmax, min(nyq, 16000))
    if vizFmax <= 3000
        vizStepK = 0.5
    elsif vizFmax <= 8000
        vizStepK = 1
    else
        vizStepK = 2
    endif

    # pure-wet channel 1 (level-matched, before mixing)
    selectObject: wetID
    if numChannels = 2
        vizWet = Extract one channel: 1
    else
        vizWet = Copy: "fsh_viz_wet"
    endif
    selectObject: viz_src
    srcSpg = To Spectrogram: 0.025, vizFmax, 0.005, 20, "Gaussian"
    selectObject: vizWet
    wetSpg = To Spectrogram: 0.025, vizFmax, 0.005, 20, "Gaussian"

    Erase all
    Line width: 1
    Solid line

    # ---- header ----
    Font size: 13
    Select inner viewport: 0, 8, 0, 0.42
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Fractal Spectral Hologram v2.0##"
    Font size: 7
    Select inner viewport: 0, 8, 0.42, 0.68
    Axes: 0, 1, 0, 1
    Colour: "{0.34, 0.34, 0.42}"
    @clean: originalName$
    hdr$ = clean.s$ + "  |  " + presetName$ + "  |  " + modeName$ + "  |  f_k = c + z^k (f - c),  c = "
        ... + fixed$(zoom_centre_Hz, 0) + " Hz,  z = " + fixed$(fractal_zoom, 3)
    if zoomDynamic
        hdr$ = hdr$ + " -> " + fixed$(zoom_end, 3)
    endif
    Text: 0.5, "centre", 0.5, "half", hdr$

    # ---- A: source spectrogram ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.80, 2.30
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0, "left", 1.06, "bottom", "##A  Source spectrogram (channel 1)##"
    selectObject: srcSpg
    Select inner viewport: 0.6, 7.7, 0.80, 2.30
    Paint: 0, outDur, 0, vizFmax, 100, "yes", 60, 6, 0, "no"
    Select inner viewport: 0.6, 7.7, 0.80, 2.30
    Axes: 0, outDur, 0, vizFmax
    Colour: "{0.20, 0.60, 0.30}"
    Dashed line
    if zoom_centre_Hz > 0 and zoom_centre_Hz < vizFmax
        Draw line: 0, zoom_centre_Hz, outDur, zoom_centre_Hz
    endif
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.80, 2.30
    Axes: 0, outDur, 0, vizFmax / 1000
    Marks left every: 1, vizStepK, "yes", "yes", "no"
    Text left: "yes", "kHz"

    # ---- B: pure wet spectrogram ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.62, 4.12
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0, "left", 1.06, "bottom", "##B  Synthesized (pure wet, level-matched, before mix)##"
    selectObject: wetSpg
    Select inner viewport: 0.6, 7.7, 2.62, 4.12
    Paint: 0, outDur, 0, vizFmax, 100, "yes", 60, 6, 0, "no"
    Select inner viewport: 0.6, 7.7, 2.62, 4.12
    Axes: 0, outDur, 0, vizFmax
    Colour: "{0.20, 0.60, 0.30}"
    Dashed line
    if zoom_centre_Hz > 0 and zoom_centre_Hz < vizFmax
        Draw line: 0, zoom_centre_Hz, outDur, zoom_centre_Hz
    endif
    Colour: "{0.80, 0.30, 0.20}"
    if srcDur < outDur
        Draw line: srcDur, 0, srcDur, vizFmax
    endif
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.6, 7.7, 2.62, 4.12
    Axes: 0, outDur, 0, vizFmax / 1000
    Marks left every: 1, vizStepK, "yes", "yes", "no"
    Text left: "yes", "kHz"

    # ---- C: generated component map f_k(t), colour = level, shade = envelope ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 4.44, 6.24
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0, "left", 1.05, "bottom", "##C  Generated components f_k(t): colour = copy level, shade = envelope (channel 1)##"
    Select inner viewport: 0.6, 7.7, 4.44, 6.24
    Axes: 0, outDur, 0, vizFmax
    Paint rectangle: "{0.985, 0.985, 0.988}", 0, outDur, 0, vizFmax

    # level colours: p = 0 grey, +k blues/teals, -k oranges
    for li to nLev
        lp = levP#[li]
        if lp = 0
            cr = 0.25
            cg = 0.25
            cb = 0.30
        elsif lp > 0
            cr = 0.10 + 0.05 * (lp - 1)
            cg = 0.30 + 0.12 * (lp - 1)
            cb = 0.85 - 0.08 * (lp - 1)
        else
            cr = 0.90 - 0.04 * (-lp - 1)
            cg = 0.40 + 0.10 * (-lp - 1)
            cb = 0.15
        endif
        for sh to 3
            a = 1.0 - 0.3 * (sh - 1)
            levCol'li'_'sh'$ = "{" + fixed$(1 - a * (1 - cr), 3) + ", " + fixed$(1 - a * (1 - cg), 3) + ", "
                ... + fixed$(1 - a * (1 - cb), 3) + "}"
        endfor
    endfor

    nSeg = 0
    if eMax > 0
        thr1 = eMax * 10 ^ (-12 / 20)
        thr2 = eMax * 10 ^ (-24 / 20)
        thr3 = eMax * 10 ^ (-42 / 20)
        Select inner viewport: 0.6, 7.7, 4.44, 6.24
        Axes: 0, outDur, 0, vizFmax
        Line width: 1.5
        # weakest first so strong components are drawn on top
        for shPass to 3
            sh = 4 - shPass
            if sh = 1
                thrLo = thr1
                thrHi = 1e300
            elsif sh = 2
                thrLo = thr2
                thrHi = thr1
            else
                thrLo = thr3
                thrHi = thr2
            endif
            for r to nVizRows
                selectObject: eMat
                ev# = Get all values in row: r
                if max(ev#) >= thrLo
                    selectObject: fMat
                    fv# = Get all values in row: r
                    li = floor((r - 1) / viz_S) + 1
                    Colour: levCol'li'_'sh'$
                    for ip from 1 to nVizPts - 1
                        c0 = 1 + (ip - 1) * vDec
                        c1 = c0 + vDec
                        eSeg = min(ev#[c0], ev#[c1])
                        if eSeg >= thrLo and eSeg < thrHi
                            f0 = fv#[c0]
                            f1 = fv#[c1]
                            if f0 > 0 and f1 > 0 and f0 < vizFmax and f1 < vizFmax
                                t0 = ctlStart + (c0 - 0.5) * anaStep
                                t1 = ctlStart + (c1 - 0.5) * anaStep
                                Draw line: t0, f0, t1, f1
                                nSeg = nSeg + 1
                            endif
                        endif
                    endfor
                endif
            endfor
        endfor
        Line width: 1
    endif
    removeObject: fMat, eMat
    Select inner viewport: 0.6, 7.7, 4.44, 6.24
    Axes: 0, outDur, 0, vizFmax
    Colour: "{0.20, 0.60, 0.30}"
    Dashed line
    if zoom_centre_Hz > 0 and zoom_centre_Hz < vizFmax
        Draw line: 0, zoom_centre_Hz, outDur, zoom_centre_Hz
    endif
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.6, 7.7, 4.44, 6.24
    Axes: 0, outDur, 0, vizFmax / 1000
    Marks left every: 1, vizStepK, "yes", "yes", "no"
    Text left: "yes", "kHz"
    tStep = 0.1
    if outDur > 1.5
        tStep = 0.2
    endif
    if outDur > 3
        tStep = 0.5
    endif
    if outDur > 7
        tStep = 1
    endif
    if outDur > 15
        tStep = 2
    endif
    if outDur > 35
        tStep = 5
    endif
    if outDur > 80
        tStep = 10
    endif
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Text bottom: "yes", "time (s)   |   dashed green = centre c   |   red dashed (B) = end of source"

    # ---- legend strip for levels ----
    Font size: 6
    Select inner viewport: 0.6, 7.7, 6.68, 6.86
    Axes: 0, nLev, 0, 1
    for li to nLev
        Paint rectangle: levCol'li'_1$, li - 1 + 0.05, li - 1 + 0.25, 0.2, 0.8
    endfor
    Select inner viewport: 0.6, 7.7, 6.68, 6.86
    Axes: 0, nLev, 0, 1
    Colour: "Black"
    for li to nLev
        lp = levP#[li]
        Text: li - 1 + 0.3, "left", 0.5, "half", "p=" + string$(lp) + " w=" + fixed$(levW#[li], 2)
    endfor

    # ---- summary panel ----
    Font size: 6
    Select inner viewport: 0.6, 7.7, 7.0, 7.9
    Axes: 0, 1, 0, 4
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 4
    Select inner viewport: 0.6, 7.7, 7.0, 7.9
    Axes: 0, 1, 0, 4
    Colour: "Black"
    Text: 0.01, "left", 3.4, "half", "Analysis: Gaussian " + string$(window_ms) + " ms / hop " + string$(hop_ms)
        ... + " ms, " + string$(partials) + " partials, sharpen " + fixed$(sharpen, 2) + ", log-parabolic peak interpolation"
    Text: 0.01, "left", 2.4, "half", "Envelopes: attack " + string$(attack_ms) + " ms, ring T60 " + string$(ring_s)
        ... + " s (tilt " + string$(ring_tilt) + "), echo " + string$(echo_delay_s) + " s/level, depth growth "
        ... + string$(depth_growth) + ", fragments " + string$(fragment_rate_Hz) + " Hz"
    Text: 0.01, "left", 1.4, "half", "Diffuse mix " + fixed$(diffuse_mix, 2) + " (band " + string$(blur_Hz)
        ... + " Hz)  |  wet gain x" + fixed$(gainW, 3) + "  |  dry/wet " + fixed$(dry_wet, 2)
        ... + "  |  safety " + fixed$(20 * log10(safeGain), 1) + " dB"
    Text: 0.01, "left", 0.4, "half", "Output " + fixed$(outDur, 2) + " s (tail " + fixed$(outDur - srcDur, 2)
        ... + " s)  |  " + string$(nSeg) + " drawn component segments  |  render " + fixed$(processingTime, 2) + " s"
    Select inner viewport: 0.6, 7.7, 7.0, 7.9
    Axes: 0, 1, 0, 4
    Draw inner box

    removeObject: srcSpg, wetSpg, vizWet
    Select outer viewport: 0, 8, 0, vizH
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif
if viz_fAll > 0
    removeObject: viz_fAll, viz_eAll, viz_src
endif
removeObject: wetID

# ============================================================
# OUTPUT
# ============================================================
selectObject: resultID
appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " s"
appendInfoLine: "Created: ", selected$("Sound")
if play_result
    Play
endif
selectObject: resultID
