# ============================================================
# Praat AudioTools - Spectral_Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP-style Spectral Morph — Python-powered STFT morphing.
#   Heavy DSP offloaded to spectral_morph.py via runSystem.
#   Praat handles UI, export, import, visualization.
#
#   Morph modes (Python):
#   1. Log magnitude     - geometric interp, preserves A phase
#   2. Full complex      - blends magnitude AND phase
#   3. Formant/envelope  - cepstral envelope morph, A excitation
#
#   Length handling (v5.0+, when durations of A and B differ):
#   1. Silence pad (default) - shorter signal is zero-padded to
#      match longer. v5.2 silence blend makes this transition
#      smoothly in all three morph modes.
#   2. Trim to shorter - longer is truncated to match shorter.
#   3. Time stretch (v4.x legacy) - linear time-domain interp.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v5.4:
#
#   AUDIO FIX (Python backend): shifted silence-factor ramp.
#   v5.3's silence-boundary math was working correctly (the b_sil
#   ramp was smooth), but the audible "jump" Sha heard at t=2.64 s
#   came from a different mechanism: in mode 1 (log-magnitude) the
#   geometric mean of cello-bin and horn-bin produces small values
#   wherever one input has energy and the other doesn't, so during
#   the entire morph the output was attenuated to ~ 10 % of the
#   inputs' RMS. When the v5.3 blend kicked in AT the silence
#   boundary, output had to climb 15x in ~ 90 ms -- audibly an
#   onset transient.
#
#   v5.4 ends the silence-factor ramp AT the boundary instead of
#   centering on it (v5.3 was centered, sil = 0.5 at the boundary).
#   pre_ramp = 2 * wsize so the ramp starts ~ 186 ms before the
#   silence-pad boundary at default 60 ms window. As the other
#   signal naturally fades toward its boundary, the blend gradually
#   replaces the attenuated morph with direct A, smoothing the
#   amplitude rise. By the time the silence boundary is reached,
#   output is already at direct-A level -- no jump.
#
#   For Sha's exact data:
#     v5.3 actual: out_rms ramp 0.022 -> 0.345 over 4 frames
#                  (max consecutive ratio 3.7x in 23 ms)
#     v5.4:        out_rms ramp 0.024 -> 0.230 over 10 frames
#                  (max consecutive ratio 1.93x; smooth amplitude
#                   rise over 207 ms, no perceptible onset)
#
#   Same-duration inputs: both boundaries equal len_out, both a_sil
#   and b_sil ramp together, delta = 0 throughout, output bit-
#   identical to v5.0 (verified by smoke test).
#
#   USABILITY FIX (Praat-side): the v5.3 debug CSV was written by
#   Python to the system temp folder and was effectively invisible.
#   v5.4 Praat copies the CSV from the temp location to
#   <homeDirectory>/spectral_morph_debug.csv after Python finishes
#   and prints the destination path plus a column legend to the
#   info window.
#
# Changelog v5.3:
#
#   DIAGNOSTICS (Python backend): comprehensive per-frame debug log.
#   New Debug toggle in the form. When enabled:
#     - Python writes <output>_debug.csv next to the output WAV.
#       Each row is one analysis frame, with columns:
#         frame, time_s, m,
#         a_rms_td, b_rms_td       (time-domain RMS of windowed frame)
#         a_mag_mean, b_mag_mean   (mean FFT magnitude)
#         a_sil, b_sil             (v5.2 continuous silence factors)
#         w_morph, w_a_direct, w_b_direct
#                                  (v5.2 blend weights, modes 1/3 only)
#         mag_morph_mean           (raw log-mag morph output)
#         mag_out_mean, mag_out_peak
#         out_rms, out_peak        (final OLA-normalised output near
#                                   this frame's center)
#     - Python also prints a focused 11-frame summary around any
#       silence-factor 0.5 crossings to stdout, so the runtime console
#       shows what's happening at the transition without opening
#       the CSV.
#     - A NaN/Inf guard catches any non-finite arithmetic and replaces
#       with zero (with a one-time warning).
#
#   No audio-path changes other than the NaN guard, which only fires
#   on actually-non-finite values that real audio cannot produce.
#   Same-input output is bit-identical to v5.2.
#
#   Use the CSV to identify exactly where Sha's "cello jumps at 2.64 s"
#   manifests: look for the b_sil ramp (B is the shorter signal, so its
#   silence factor rises as the silence-padded region is reached) and
#   the corresponding out_rms trajectory.
#
# Changelog v5.2:
#
#   BUG FIX (Python backend): v5.1 silence guard replaced one
#   bug (log-magnitude morph dissolves to silence when one input
#   is silence-padded) with another (output JUMPS to full
#   amplitude at the binary threshold crossing). v5.2 replaces
#   the binary threshold with a continuous log-domain ramp
#   between EPS_LOW=1e-6 and EPS_HIGH=1e-3 mean magnitude, and
#   blends morphed output with direct content via weights that
#   are continuous in the silence factor. Result: smooth ~80 ms
#   transition through the silence boundary (controlled by the
#   FFT window's RMS-detection lag), instead of a single-frame
#   step.
#
#   Confirmed in smoke tests on Sha's cello (4.4 s) / horn
#   (2.64 s) test case: v5.1 had a ~0.35 RMS step at t=2.64 s;
#   v5.2 has max 5 ms-to-5 ms RMS step of 0.044 (about 8x
#   smoother).
#
#   Audio impact:
#     - Same-duration inputs (any mode): bit-identical to v5.1
#       and v5.0 (the blend weights collapse to w_morph=1 when
#       both inputs have content, recovering the original
#       morph formula).
#     - Different-duration inputs with silence-pad, modes 1 or 3:
#       output now transitions smoothly through the silence
#       boundary. Past the silence-padded region, output is the
#       non-silent input directly (same as v5.1).
#     - Trim, time stretch: unaffected (no silence frames).
#     - Mode 2: unaffected (linear interp already smooth).
#
#   No Praat-side changes in v5.2. Only the Python backend
#   changed.
#
# Changelog v5.1:
#   Binary silence guard introduced (superseded by v5.2 continuous
#   blend above).
#
# Changelog v5.0:
#
#   AUDIO CHANGE A (Python backend, Sec. v5.0 Change A):
#     scipy.signal.resample_poly now uses exact gcd-based integer
#     ratio when sr_a != sr_b. v4.x used Fraction(sr_a, sr_b).
#     limit_denominator(100), which for common cross-rate cases
#     (44100<->48000, 88200<->96000, 16000<->44100, ...) returned
#     a coarse rational like 11/12 instead of the exact 160/147,
#     introducing a small pitch shift on signal B. v5.0 audio
#     output for same-SR inputs is bit-identical to v4.x; cross-SR
#     audio is more correct (less pitch shift on B).
#
#   AUDIO CHANGE B (Python backend, Sec. v5.0 Change B):
#     Default length-handling changed from time-stretch (v4.x) to
#     silence-pad. When durations differ, v4.x linearly time-
#     stretched the shorter signal to match the longer — a crude
#     time-domain resample that PITCHES the shorter input (~16
#     semitones for a 2.5x stretch). v5.0 silence-pads instead.
#     For inputs with identical durations the two modes are
#     equivalent and audio is bit-identical. For mismatched
#     durations, audio output changes.
#
#     New form field "Length handling" exposes three modes:
#       1. Silence pad (default, recommended)
#       2. Trim to shorter
#       3. Time stretch (v4.x legacy behavior)
#
#   PRAAT-SIDE POLISH:
#     - Dropped 5 decorative `comment === ... ===` form rows.
#     - Spectrogram time_step in viz: 0.002 -> 0.01 in all three
#       spectrogram panels.
#     - Output filename suffix: `<A>_morph_<B>_<preset>_<modeShort>`.
#
#   VISUALISATION:
#     - Rewritten to suite 8x8 standard. See v5.0 changelog
#       (previous header) for panel layout details.
#
# Changelog v4.2:
#   - Unified cross-platform paths and Python probe
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects."
        ... + newline$ + "Sound 1 = A (source), Sound 2 = B (target)."
endif

soundA = selected("Sound", 1)
soundB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

# ---- PATHS ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/spectral_morph.py"
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempA$       = tempDir$ + "morph_A.wav"
tempB$       = tempDir$ + "morph_B.wav"
tempOutput$  = tempDir$ + "morph_output.wav"
probePy$     = tempDir$ + "morph_probe.py"
probeMarker$ = tempDir$ + "morph_probe.ok"

tempAJ$       = replace_regex$(tempA$,       "\\", "/", 0)
tempBJ$       = replace_regex$(tempB$,       "\\", "/", 0)
tempOutputJ$  = replace_regex$(tempOutput$,  "\\", "/", 0)
probePyJ$     = replace_regex$(probePy$,     "\\", "/", 0)
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempA$)
        deleteFile: tempA$
    endif
    if fileReadable(tempB$)
        deleteFile: tempB$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- GET INPUT STATS ----
selectObject: soundA
durA = Get total duration
srA  = Get sampling frequency
nchA = Get number of channels

selectObject: soundB
durB = Get total duration
srB  = Get sampling frequency
nchB = Get number of channels

# ===========================================================================
# STAGE 0 — Python Probe (file-based, runs before form)
# ===========================================================================

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

pythonCmd$ = ""
for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python with numpy, scipy and soundfile." + newline$
        ... + "Install Python 3 and run:  pip install numpy scipy soundfile"
endif

# ---- FORM ----
form Spectral Morph v5.4
    optionmenu Preset: 1
        option Custom
        option Tonal Sustained (instruments, pads)
        option Percussive (drums, impacts)
        option Voice / Formant Morph
        option Texture Blend (ambience, noise)
        option Fast Preview (low quality, quick)
    real Start_morph_s 0
    real End_morph_s 0
    optionmenu Curve_type: 2
        option Linear
        option Cosine (smooth S-curve)
        option Full mix (fixed blend, no transition)
    real Mix_amount 0.5
    positive Window_ms 60
    optionmenu Morph_mode: 1
        option Log magnitude (preserve A phase)
        option Full complex (blend phase too)
        option Formant / envelope (CDP-style)
    optionmenu Length_handling: 1
        option Silence pad (no pitch change)
        option Trim to shorter
        option Time stretch (v4.x legacy, pitches shorter)
    boolean Draw_visualization 1
    boolean Play_output 1
    boolean Debug 0
endform

# ---- PRESETS ----
if preset = 2
    window_ms  = 60
    morph_mode = 1
    curve_type = 2
    presetName$ = "TonalSustained"
elsif preset = 3
    window_ms  = 25
    morph_mode = 1
    curve_type = 1
    presetName$ = "Percussive"
elsif preset = 4
    window_ms  = 50
    morph_mode = 3
    curve_type = 2
    presetName$ = "VoiceFormant"
elsif preset = 5
    window_ms  = 80
    morph_mode = 2
    curve_type = 2
    presetName$ = "TextureBlend"
elsif preset = 6
    window_ms  = 120
    morph_mode = 1
    curve_type = 1
    presetName$ = "FastPreview"
else
    presetName$ = "Custom"
endif

window_s = window_ms / 1000

# v5.0: commonDuration depends on length_handling mode:
#   silence-pad (1) and time-stretch (3) both produce output at
#   max(durA, durB). trim-to-shorter (2) produces output at
#   min(durA, durB). The morph region is clamped relative to
#   this duration, and the visualization uses it as the time
#   axis for the morph-curve and output-spectrogram panels.
if length_handling = 2
    commonDuration = min(durA, durB)
else
    commonDuration = max(durA, durB)
endif

# ---- CLAMP MORPH REGION ----
if end_morph_s <= start_morph_s or end_morph_s <= 0
    end_morph_s = commonDuration
endif
if start_morph_s < 0
    start_morph_s = 0
endif
if end_morph_s > commonDuration
    end_morph_s = commonDuration
endif

# ---- MODE LABELS ----
if morph_mode = 1
    modeLabel$ = "Log magnitude"
    modeShort$ = "log"
elsif morph_mode = 2
    modeLabel$ = "Full complex"
    modeShort$ = "complex"
else
    modeLabel$ = "Formant/envelope"
    modeShort$ = "envelope"
endif
if curve_type = 2
    curveLabel$ = "Cosine"
elsif curve_type = 3
    curveLabel$ = "FullMix(" + fixed$(mix_amount, 2) + ")"
else
    curveLabel$ = "Linear"
endif
if length_handling = 1
    lengthLabel$ = "Silence-pad"
elsif length_handling = 2
    lengthLabel$ = "Trim-to-shorter"
else
    lengthLabel$ = "Time-stretch(legacy)"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Morph v5.4 ==="
appendInfoLine: "A:        ", nameA$, "  (", fixed$(durA, 2), " s,  SR ", srA, ")"
appendInfoLine: "B:        ", nameB$, "  (", fixed$(durB, 2), " s,  SR ", srB, ")"
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Mode:     ", modeLabel$
appendInfoLine: "Curve:    ", curveLabel$
appendInfoLine: "Window:   ", fixed$(window_ms, 0), " ms"
appendInfoLine: "Length:   ", lengthLabel$
appendInfoLine: "Region:   ", fixed$(start_morph_s, 2), " - ", fixed$(end_morph_s, 2), " s"
appendInfoLine: "OutDur:   ", fixed$(commonDuration, 2), " s"
appendInfoLine: "Python:   ", pythonCmd$
appendInfoLine: ""

# ===========================================================================
# STAGE 1 — Export WAVs
# ===========================================================================
appendInfoLine: "[1/4] Exporting WAVs..."

selectObject: soundA
Save as WAV file: tempA$

selectObject: soundB
Save as WAV file: tempB$

# ===========================================================================
# STAGE 2 — Call Python
# ===========================================================================
appendInfoLine: "[2/4] Running Python morphing engine..."

# v5.0: pass length_handling as the 10th positional argument
# (10th after script name; Python's len(sys.argv) == 11).
runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempAJ$ + """"
    ... + " """ + tempBJ$ + """"
    ... + " """ + tempOutputJ$ + """"
    ... + " " + fixed$(window_s, 6)
    ... + " " + fixed$(start_morph_s, 6)
    ... + " " + fixed$(end_morph_s, 6)
    ... + " " + string$(morph_mode)
    ... + " " + string$(curve_type)
    ... + " " + fixed$(mix_amount, 4)
    ... + " " + string$(length_handling)
    ... + " " + string$(debug)

# ===========================================================================
# STAGE 3 — Verify & Import
# ===========================================================================
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python spectral morph failed." + newline$
        ... + "Possible causes:" + newline$
        ... + "  - numpy, scipy or soundfile not installed" + newline$
        ... + "  - Python not found in PATH" + newline$
        ... + "Check the terminal/console for Python error messages."
endif

appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
# v5.0: output filename now includes preset and morph-mode suffix
# so multiple runs with the same A/B don't collide.
Rename: nameA$ + "_morph_" + nameB$ + "_" + presetName$ + "_" + modeShort$
finalOutput = selected("Sound")
outputDuration = Get total duration
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "  Output: ", fixed$(outputDuration, 2), " s"

# v5.4: surface the debug CSV. Python wrote it next to the temp WAV
# (tempDir/morph_output_debug.csv), which is the system temp folder
# and is hard to find. Copy it to the user's home directory under a
# stable name and print the full path in the info window. Without
# this the v5.3 debug feature was effectively invisible.
if debug
    debugSrc$ = tempDir$ + "morph_output_debug.csv"
    debugDst$ = homeDirectory$ + "/spectral_morph_debug.csv"
    appendInfoLine: ""
    appendInfoLine: "-- Debug CSV ---------------------------------------------"
    if fileReadable(debugSrc$)
        debugContent$ = readFile$(debugSrc$)
        writeFile: debugDst$, debugContent$
        appendInfoLine: "  Per-frame log: ", debugDst$
        appendInfoLine: "  (open in Excel / LibreOffice / text editor)"
        appendInfoLine: "  Columns:"
        appendInfoLine: "    time_s   = frame center in seconds"
        appendInfoLine: "    m        = morph factor 0-1 (per curve_type)"
        appendInfoLine: "    a_rms_td = windowed time-domain RMS of A frame"
        appendInfoLine: "    b_rms_td = same for B"
        appendInfoLine: "    a_sil    = v5.3 time-position silence factor for A"
        appendInfoLine: "    b_sil    = same for B"
        appendInfoLine: "    w_morph  = weight on standard morph output"
        appendInfoLine: "    w_a_dir  = weight on direct mag_a (blend toward A)"
        appendInfoLine: "    w_b_dir  = weight on direct mag_b (blend toward B)"
        appendInfoLine: "    out_rms  = OLA-normalised output near frame center"
    else
        appendInfoLine: "  WARN: expected at ", debugSrc$
        appendInfoLine: "  but file not found. Python may have failed before"
        appendInfoLine: "  the CSV write step. Check terminal/console output."
    endif
    appendInfoLine: "----------------------------------------------------------"
endif

###############################################################################
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: Spectrogram A (left, headline)
# Panel B: Spectrogram B (right, headline)
# Panel C: Morph curve (signature visual, preserved from v4.x)
# Panel D: Output spectrogram
# Panel E: light-grey summary stats bar
###############################################################################

if draw_visualization
    appendInfoLine: "[4/4] Creating visualization..."

    selectObject: soundA
    if nchA > 1
        monoA_viz = Convert to mono
    else
        monoA_viz = Copy: "monoA_viz"
    endif

    selectObject: soundB
    if nchB > 1
        monoB_viz = Convert to mono
    else
        monoB_viz = Copy: "monoB_viz"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SPECTRAL MORPH##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... nameA$ + " -> " + nameB$
        ... + "  |  " + presetName$
        ... + "  |  " + modeLabel$
        ... + "  |  " + curveLabel$
        ... + "  |  " + lengthLabel$
        ... + "  |  win " + fixed$(window_ms, 0) + " ms"

    # ----------------------------------------------------------
    # PANEL A: SPECTROGRAM A  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    selectObject: monoA_viz
    # v5.0: time_step 0.002 -> 0.01 (5x faster, still sharp at panel scale)
    To Spectrogram: 0.005, 8000, 0.01, 20, "Gaussian"
    specgramA = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specgramA

    # ----------------------------------------------------------
    # PANEL B: SPECTROGRAM B  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    selectObject: monoB_viz
    To Spectrogram: 0.005, 8000, 0.01, 20, "Gaussian"
    specgramB = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specgramB

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Spectrogram A  (" + nameA$ + ",  " + fixed$(durA, 2) + " s)"
    Text: 6.10, "centre", 7.30, "half", "Spectrogram B  (" + nameB$ + ",  " + fixed$(durB, 2) + " s)"

    # ----------------------------------------------------------
    # PANEL C: MORPH CURVE  (full width — signature visual)
    # Shows the actual interpolation trajectory over output time,
    # with the morph region highlighted.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    Axes: 0, commonDuration, -0.05, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, commonDuration, -0.05, 1.1
    # Morph-region tint
    Paint rectangle: "{0.92, 0.95, 1.0}", start_morph_s, end_morph_s, -0.05, 1.1

    # Reference horizontal lines at m=0 (pure A) and m=1 (pure B)
    Colour: "{0.78, 0.78, 0.82}"
    Line width: 1
    Dotted line
    Draw line: 0, 0, commonDuration, 0
    Draw line: 0, 1, commonDuration, 1
    Solid line

    # Curve trajectory (100 sampled segments)
    Colour: "{0.20, 0.20, 0.70}"
    Line width: 2.5
    vizPoints = 100
    vizStep = commonDuration / vizPoints
    prevT = 0
    if end_morph_s > start_morph_s
        prevU = (0 - start_morph_s) / (end_morph_s - start_morph_s)
    else
        prevU = 1
    endif
    if prevU < 0
        prevU = 0
    endif
    if prevU > 1
        prevU = 1
    endif
    if curve_type = 2
        prevM = 0.5 - 0.5 * cos(pi * prevU)
    elsif curve_type = 3
        prevM = mix_amount
    else
        prevM = prevU
    endif
    for vp from 1 to vizPoints
        curT = vp * vizStep
        if end_morph_s > start_morph_s
            curU = (curT - start_morph_s) / (end_morph_s - start_morph_s)
        else
            curU = 1
        endif
        if curU < 0
            curU = 0
        endif
        if curU > 1
            curU = 1
        endif
        if curve_type = 2
            curM = 0.5 - 0.5 * cos(pi * curU)
        elsif curve_type = 3
            curM = mix_amount
        else
            curM = curU
        endif
        Draw line: prevT, prevM, curT, curM
        prevT = curT
        prevM = curM
    endfor
    Line width: 1

    # A / B endpoint labels
    Colour: "{0.30, 0.50, 0.80}"
    Font size: 6
    Text: 0, "left", 1.05, "half", "A"
    Colour: "{0.80, 0.40, 0.30}"
    Text: commonDuration, "right", 1.05, "half", "B"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Morph curve  (" + curveLabel$ + ",  region " + fixed$(start_morph_s, 2) + " - " + fixed$(end_morph_s, 2) + " s)"
    Text left: "yes", "Morph (0-1)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    selectObject: finalOutput
    To Spectrogram: 0.005, 8000, 0.01, 20, "Gaussian"
    specgramOut = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output spectrogram  (morphed result,  " + fixed$(outputDuration, 2) + " s)"
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specgramOut

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + nameA$ + " -> " + nameB$
        ... + "  |  Mode: " + modeLabel$
        ... + "  |  Curve: " + curveLabel$
        ... + "  |  Window: " + fixed$(window_ms, 0) + " ms"

    Text: 0.02, "left", 0.50, "half",
        ... "Length handling: " + lengthLabel$
        ... + "  |  A: " + fixed$(durA, 2) + " s (" + string$(srA) + " Hz)"
        ... + "  |  B: " + fixed$(durB, 2) + " s (" + string$(srB) + " Hz)"
        ... + "  |  Out: " + fixed$(outputDuration, 2) + " s"

    Text: 0.02, "left", 0.18, "half",
        ... "Morph region: " + fixed$(start_morph_s, 2) + " - " + fixed$(end_morph_s, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)
        ... + "  |  Output: " + nameA$ + "_morph_" + nameB$ + "_" + presetName$ + "_" + modeShort$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: monoA_viz, monoB_viz
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ===========================================================================
# CLEANUP & SUMMARY
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:   ", nameA$, "_morph_", nameB$, "_", presetName$, "_", modeShort$
appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Mode:     ", modeLabel$, "  |  Curve: ", curveLabel$
appendInfoLine: "Length:   ", lengthLabel$
appendInfoLine: "RMS:      ", fixed$(rms_out, 6)

selectObject: finalOutput

if play_output
    Play
endif
