# ============================================================
# Praat AudioTools - SelfAttentionLatent.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Self-Attention Latent Navigation Engine
#   Part of Praat AudioTools plugin
#
# Pipeline:
#   1. User selects audio file
#   2. Praat segments into events → writes temp events.csv
#   3. Praat calls Python (self_attention_latent.py)
#   4. Python: VAE encode → self-attention → plan (in memory) → mix → output.wav
#   5. Praat loads output.wav, shows visualization, deletes temp files
#
# No plan.csv is ever written.
# Only output.wav persists after execution.
#
# Changelog v1.2:
#
#   TIER 1 (Praat polish, audio bit-identical):
#     - Dropped 8 decorative `comment ── ... ───────` form rows
#       (Preset / Segmentation / VAE / Self-attention / Navigation
#       plan / Output duration / Pitch / Misc). Form: 28 rows ->
#       20 rows. All 4 optionmenus already had colons.
#     - Replaced unicode `══` info window banners with plain
#       ASCII `===` separators (same gotcha as Auto-Harmonic
#       v1.7 -- non-ASCII chars in Praat's info window render
#       inconsistently across platforms).
#     - Replaced unicode `proportional-to` and `middle-dot` in
#       the viz footer formula with ASCII (`~` and `*`). Same
#       reasoning, but for Text() in graphics.
#     - Output filename: `<name>_sal` -> `<name>_sal_<preset>`
#       so multiple runs with different presets don't collide.
#     - Visualization rewritten from custom 8-panel stacked
#       layout to suite 8x8 with side-by-side pairs:
#         Title bar (light) + metadata subtitle
#         Phase bar (full width, signature, color-coded phases)
#         Original waveform / Output waveform (side-by-side)
#         Original spectrogram / Output spectrogram (side-by-side)
#         Light-grey 3-line summary including the formula
#
#   TIER 2 (real bugs, audio bit-identical):
#     - FIXED: subtitle text overflowing into Phase bar. v1.1
#       had axis y=-1.2 with viewport 0,8,0,0.5 -> outer y=1.1
#       inches, which is INSIDE the Phase bar panel (outer
#       0.6-1.4). The subtitle was drawn on top of the phase
#       bar. v1.2 uses suite-standard subtitle position (axis
#       y=-0.22 in a 0-0.65 title viewport).
#     - FIXED: `;` accidentally commented out inline if-statements
#       on v1.1 lines 588-591:
#         nd = number(driftStat$);  if nd = undefined then nd = 0 endif
#       Praat's `;` starts a line comment, so the `if ... endif`
#       portion was NEVER executed. When the Python stats file
#       is missing or any phase count fails to parse, `nd` /
#       `nm` / `nr` / `ns` would stay `undefined`, propagating to
#       `xd = nd / nTotal = undefined`, breaking the phase bar.
#       Only triggers on the failure path, which is why this hasn't
#       been seen in normal runs. v1.2 uses proper multi-line
#       `if ... endif` blocks.
#     - FIXED: `!=` is not valid Praat syntax (v1.1 line 587:
#       `if nTotal > 0 and nTotal != undefined`). Praat uses `<>`
#       for inequality. Replaced with `<>` for portability.
#     - FIXED: probe loop "break early" never actually breaks.
#       v1.1 line 363 had `iCand = nCandidates + 1 ; Break early`.
#       The `;` makes "Break early" a comment, but more importantly,
#       Praat's `for` loop doesn't honor mid-body modifications to
#       the loop variable. The loop ran all candidates regardless,
#       and the LAST successful candidate (not the first) overwrote
#       pythonCmd$. v1.2 uses a `pythonFound` flag and guards the
#       loop body so subsequent iterations skip after the first
#       success.
#
#   TIER 3 (Python backend cleanup):
#     - self_attention_latent.py: removed `"loudness"` alias in
#       `_rms_compensate`. The Praat front-end only ever passes
#       "none", "peak", or "rms" -- the "loudness" branch was
#       unreachable. Cosmetic-only; output is bit-identical.
#
#   Audio output is bit-identical to v1.1 for any input and seed.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-SPECIFIC PYTHON DISCOVERY ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/self_attention_latent.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/self_attention_latent.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: self_attention_latent.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempWav$     = tempDir$ + "temp_sal_input.wav"
eventsCSV$   = tempDir$ + "temp_sal_events.csv"
output_wav$  = tempDir$ + "temp_sal_output.wav"
stats_txt$   = tempDir$ + "temp_sal_stats.txt"
probePy$     = tempDir$ + "temp_sal_probe.py"
probeMarker$ = tempDir$ + "temp_sal_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempWavJ$      = replace_regex$(tempWav$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
output_wavJ$   = replace_regex$(output_wav$, "\\", "/", 0)
stats_txtJ$    = replace_regex$(stats_txt$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempWav$)
        deleteFile: tempWav$
    endif
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(output_wav$)
        deleteFile: output_wav$
    endif
    if fileReadable(stats_txt$)
        deleteFile: stats_txt$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Self-Attention Latent Navigation v1.2
    optionmenu Preset: 1
        option Custom
        option Gentle drift
        option Vocal texture
        option Fragmented echo
        option Deep mutation
        option Rhythmic grid
        option Spectral smear
        option Chaotic plasma
    optionmenu Segmentation_method: 1
        option Silences
        option Equal_intervals
    positive Silence_threshold_(dB) 25.0
    positive Min_event_duration_(s) 0.05
    positive Min_silence_duration_(s) 0.03
    positive Interval_size_(s) 0.25
    integer Latent_size 8
    integer Random_seed 42
    integer Attention_heads 4
    integer Plan_steps 72
    positive Duration_scale 1.0
    real Duration_jitter 0.0
    positive Energy_scale 1.0
    real Energy_jitter 0.0
    real Target_duration_(s) 0.0
    optionmenu Pitch_mode: 2
        option off
        option preserve_f0
        option preserve_spectral_envelope
    optionmenu Normalize_mode: 3
        option none
        option peak
        option rms
    boolean Load_output 1
    boolean Show_visualization 1
    boolean Play_result 1
endform

# ── Presets ────────────────────────────────────────────────────────────────
if preset = 2
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.25
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 24
    duration_scale       = 1.0
    duration_jitter      = 0.05
    energy_scale         = 1.0
    energy_jitter        = 0.0
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "GentleDrift"
elsif preset = 3
    segmentation_method  = 1
    silence_threshold    = 20.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    interval_size        = 0.1
    latent_size          = 12
    attention_heads      = 8
    plan_steps           = 48
    duration_scale       = 0.8
    duration_jitter      = 0.1
    energy_scale         = 1.0
    energy_jitter        = 0.05
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "VocalTexture"
elsif preset = 4
    segmentation_method  = 1
    silence_threshold    = 15.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 96
    duration_scale       = 0.5
    duration_jitter      = 0.3
    energy_scale         = 0.8
    energy_jitter        = 0.2
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "FragmentedEcho"
elsif preset = 5
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.25
    latent_size          = 24
    attention_heads      = 8
    plan_steps           = 72
    duration_scale       = 1.2
    duration_jitter      = 0.15
    energy_scale         = 1.1
    energy_jitter        = 0.1
    pitch_mode           = 3
    normalize_mode       = 3
    presetName$          = "DeepMutation"
elsif preset = 6
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.125
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 64
    duration_scale       = 1.0
    duration_jitter      = 0.02
    energy_scale         = 1.0
    energy_jitter        = 0.05
    pitch_mode           = 1
    normalize_mode       = 2
    presetName$          = "RhythmicGrid"
elsif preset = 7
    segmentation_method  = 1
    silence_threshold    = 30.0
    min_event_duration   = 0.1
    min_silence_duration = 0.05
    interval_size        = 0.5
    latent_size          = 16
    attention_heads      = 4
    plan_steps           = 36
    duration_scale       = 1.5
    duration_jitter      = 0.2
    energy_scale         = 0.9
    energy_jitter        = 0.1
    pitch_mode           = 3
    normalize_mode       = 3
    presetName$          = "SpectralSmear"
elsif preset = 8
    segmentation_method  = 1
    silence_threshold    = 10.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 32
    attention_heads      = 16
    plan_steps           = 120
    duration_scale       = 1.0
    duration_jitter      = 0.5
    energy_scale         = 1.0
    energy_jitter        = 0.4
    pitch_mode           = 1
    normalize_mode       = 3
    presetName$          = "ChaoticPlasma"
else
    presetName$ = "Custom"
endif

# ── pitch mode string ──────────────────────────────────────────────────────
if pitch_mode = 1
    pitchStr$ = "off"
elsif pitch_mode = 2
    pitchStr$ = "preserve_f0"
else
    pitchStr$ = "preserve_spectral_envelope"
endif

# ── normalize mode string ─────────────────────────────────────────────────
if normalize_mode = 1
    normStr$ = "none"
elsif normalize_mode = 2
    normStr$ = "peak"
else
    normStr$ = "rms"
endif

# ── Clamp parameters ─────────────────────────────────────────────────────
if attention_heads < 1
    attention_heads = 1
endif
if attention_heads > 16
    attention_heads = 16
endif
if plan_steps < 8
    plan_steps = 8
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 0 — Early Python Dependency Probe
# ═════════════════════════════════════════════════════════════════════════════
clearinfo
appendInfoLine: "=== Self-Attention Latent Navigation v1.2 ==="
appendInfoLine: "Input:  ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "[0/4] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

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

# v1.2: use a `pythonFound` flag instead of trying to mutate the loop
# variable. Praat's for loop doesn't honor mid-body modifications to
# the loop counter, so v1.1's `iCand = nCandidates + 1 ; Break early`
# was a no-op (the loop ran all candidates and the LAST successful one
# overwrote pythonCmd$). v1.2 guards the loop body with the flag so
# subsequent iterations skip cleanly after the first success.
pythonCmd$ = ""
pythonFound = 0

for iCand from 1 to nCandidates
    if pythonFound = 0
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
            pythonFound = 1
        endif
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ═════════════════════════════════════════════════════════════════════════════
# Stage 1 — Load / prepare the Sound
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[1/4] Loading and preparing audio..."

selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# Write as wav so Python can read it reliably
Save as WAV file: tempWav$

# ═════════════════════════════════════════════════════════════════════════════
# Stage 2 — Segmentation → events.csv
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[2/4] Segmenting audio..."

selectObject: sound
tg = To TextGrid (silences): 100, 0, -silence_threshold, min_silence_duration, min_event_duration, "silent", "sounding"

selectObject: tg
nInt = Get number of intervals: 1

# Write events CSV
writeFileLine: eventsCSV$, "start_time,end_time,label,duration"

n_events = 0
for i from 1 to nInt
    selectObject: tg
    lab$ = Get label of interval: 1, i
    if segmentation_method = 1
        # Silences method: keep "sounding" intervals
        isEvent = (lab$ = "sounding")
    else
        # Equal intervals: keep everything above min duration
        isEvent = 1
    endif

    if isEvent
        st = Get start time of interval: 1, i
        en = Get end time of interval: 1, i
        evDur = en - st
        if evDur >= min_event_duration
            appendFileLine: eventsCSV$, fixed$(st, 6), ",",
                ... fixed$(en, 6), ",", lab$, ",", fixed$(evDur, 6)
            n_events = n_events + 1
        endif
    endif
endfor

removeObject: tg

if n_events < 2
    # Fall back to equal intervals
    appendInfoLine: "  Warning: too few events from silence detection, using equal intervals"
    writeFileLine: eventsCSV$, "start_time,end_time,label,duration"
    n_events = 0
    t = 0
    while t < dur - interval_size
        en = min(t + interval_size, dur)
        appendFileLine: eventsCSV$, fixed$(t, 6), ",", fixed$(en, 6), ",", "interval", ",", fixed$(en-t, 6)
        n_events = n_events + 1
        t = t + interval_size
    endwhile
endif

appendInfoLine: "  Events: " + string$(n_events)

# ═════════════════════════════════════════════════════════════════════════════
# Stage 3 — Call Python
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[3/4] Running Python engine..."

targetDurArg$ = ""
if target_duration > 0
    targetDurArg$ = " --duration " + string$(target_duration)
endif

cmd$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempWavJ$ + """"
    ... + " """ + eventsCSVJ$ + """"
    ... + " """ + output_wavJ$ + """"
    ... + " """ + stats_txtJ$ + """"
    ... + " --latent_size " + string$(latent_size)
    ... + " --seed " + string$(random_seed)
    ... + " --attn_heads " + string$(attention_heads)
    ... + " --plan_steps " + string$(plan_steps)
    ... + " --plan_dur_scale " + string$(duration_scale)
    ... + " --plan_dur_jitter " + string$(duration_jitter)
    ... + " --plan_eng_scale " + string$(energy_scale)
    ... + " --plan_eng_jitter " + string$(energy_jitter)
    ... + " --pitch_mode " + pitchStr$
    ... + " --normalize_mode " + normStr$
    ... + targetDurArg$
    ... + " --cleanup"

runSystem_nocheck: cmd$

if not fileReadable(stats_txt$)
    @cleanUpTempFiles
    exitScript: "Python engine failed. Check terminal for error details."
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 4 — Read stats & Load Output
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[4/4] Finalizing results..."

# Stats parsing helper
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .kl = length(.key$)
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + .kl
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

nEventsStat$    = "?"
nStepsStat$     = "?"
nExecStat$      = "?"
outDurStat$     = "?"
attnHeadsStat$  = "?"
attnEntropyStat$ = "?"
pitchModeStat$  = "?"
normModeStat$   = "?"
rmsInputStat$   = "?"
rmsOutputStat$  = "?"
vaeLossStat$    = "?"
driftStat$      = "?"
mutateStat$     = "?"
returnStat$     = "?"
settleStat$     = "?"

if fileReadable(stats_txt$)
    statsText$ = readFile$(stats_txt$)

    @parseStatLine: statsText$, "n_events="
    nEventsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_plan_steps="
    nStepsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_executed="
    nExecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_heads="
    attnHeadsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_entropy="
    attnEntropyStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "pitch_mode="
    pitchModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_input="
    rmsInputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_output="
    rmsOutputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "vae_loss_final="
    vaeLossStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_drift="
    driftStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_mutate="
    mutateStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_return="
    returnStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_settle="
    settleStat$ = parseStatLine.result$
endif

haveOutput = 0
if load_output and fileReadable(output_wav$)
    outSound = Read from file: output_wav$
    # v1.2: include preset name in output filename.
    compositeName$ = soundName$ + "_sal_" + presetName$
    Rename: compositeName$
    appendInfoLine: "  Loaded output as: " + compositeName$
    haveOutput = 1
else
    compositeName$ = soundName$ + "_sal_" + presetName$
endif

@cleanUpTempFiles

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Phase bar  (full width, signature, color-coded phases)
# Panel B: Original waveform   (left half)
# Panel C: Output waveform     (right half)
# Panel D: Original spectrogram   (left half)
# Panel E: Output spectrogram     (right half)
# Panel F: Light-grey 3-line summary (suite standard)
###############################################################################

if show_visualization
    appendInfoLine: "  Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    # v1.2: subtitle position fixed. v1.1 had axis y=-1.2 with
    # viewport 0,8,0,0.5 -> outer y=1.1 (inside Phase bar). v1.2
    # uses suite-standard axis y=-0.22 with viewport 0-0.65.
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SELF-ATTENTION LATENT NAVIGATION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + presetName$
        ... + "  |  heads=" + attnHeadsStat$
        ... + "  |  steps=" + nStepsStat$
        ... + "  |  z=" + string$(latent_size)

    # ----------------------------------------------------------
    # PANEL A: PHASE BAR  (full width, signature, color-coded phases)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 1.95
    Select inner viewport: 0.55, 7.72, 0.95, 1.85

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.92, 0.92, 0.93}", 0, 1, 0, 1

    # v1.2: parse phase counts with proper if/endif blocks. v1.1 had
    # `nd = number(driftStat$);  if nd = undefined then nd = 0 endif`
    # but `;` is Praat's line-comment marker, so the if was a no-op.
    # When stats are missing, phase counts stayed undefined and broke
    # the phase bar drawing.
    nTotal = number(nStepsStat$)
    if nTotal = undefined
        nTotal = 0
    endif

    # v1.2: `<>` instead of v1.1's `!=` (which is not valid Praat
    # syntax -- Praat uses `<>` for inequality).
    if nTotal > 0
        nd = number(driftStat$)
        if nd = undefined
            nd = 0
        endif
        nm = number(mutateStat$)
        if nm = undefined
            nm = 0
        endif
        nr = number(returnStat$)
        if nr = undefined
            nr = 0
        endif
        ns = number(settleStat$)
        if ns = undefined
            ns = 0
        endif

        xd = nd / nTotal
        xm = xd + nm / nTotal
        xr = xm + nr / nTotal
        xs = xr + ns / nTotal

        Paint rectangle: "{0.30, 0.75, 0.88}",  0,  xd, 0, 1
        Paint rectangle: "{0.92, 0.82, 0.30}", xd, xm, 0, 1
        Paint rectangle: "{0.90, 0.55, 0.20}", xm, xr, 0, 1
        Paint rectangle: "{0.30, 0.72, 0.40}", xr, xs, 0, 1

        Font size: 8
        Colour: "Black"
        if xd > 0.08
            Text: xd / 2, "centre", 0.5, "half", "drift " + driftStat$
        endif
        if (xm - xd) > 0.08
            Text: (xd + xm) / 2, "centre", 0.5, "half", "mutate " + mutateStat$
        endif
        if (xr - xm) > 0.08
            Text: (xm + xr) / 2, "centre", 0.5, "half", "return " + returnStat$
        endif
        if (xs - xr) > 0.08
            Text: (xr + xs) / 2, "centre", 0.5, "half", "settle " + settleStat$
        endif
    else
        Font size: 8
        Colour: "{0.55, 0.55, 0.60}"
        Text: 0.5, "centre", 0.5, "half", "(no phase data available)"
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Navigation plan:  " + nStepsStat$ + " steps  /  " + nExecStat$ + " executed"
    Font size: 6
    Text left: "yes", "Phases"

    # ----------------------------------------------------------
    # PANEL B (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 2.05, 3.10
    Select inner viewport: 0.55, 4.00, 2.20, 3.00

    selectObject: sound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (right): OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.05, 3.10
    Select inner viewport: 4.55, 7.75, 2.20, 3.00

    if haveOutput
        selectObject: outSound
        Colour: "{0.30, 0.60, 0.50}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL D (left): ORIGINAL SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 3.20, 5.40
    Select inner viewport: 0.55, 4.00, 3.35, 5.25

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specOrig, tmpOrig

    # ----------------------------------------------------------
    # PANEL E (right): OUTPUT SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.20, 5.40
    Select inner viewport: 4.55, 7.75, 3.35, 5.25

    if haveOutput
        selectObject: outSound
        outChans = Get number of channels
        if outChans > 1
            Extract one channel: 1
            tmpOut = selected("Sound")
        else
            Copy: "tmpOut"
            tmpOut = selected("Sound")
        endif
        To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
        specOut = selected("Spectrogram")
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Line width: 1
        Draw inner box
        removeObject: specOut, tmpOut
    else
        Colour: "Black"
        Line width: 1
        Draw inner box
    endif
    Font size: 7
    Text top: "no", "Output spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL F: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.50, 6.20
    Select inner viewport: 0.55, 7.72, 5.57, 6.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  Events: " + nEventsStat$
        ... + "  |  Plan: " + nStepsStat$ + " steps / " + nExecStat$ + " executed"
        ... + "  |  Output dur: " + outDurStat$ + " s"
        ... + "  |  Attention heads: " + attnHeadsStat$ + ", entropy: " + attnEntropyStat$ + " nats"

    Text: 0.02, "left", 0.50, "half",
        ... "Pitch: " + pitchModeStat$
        ... + "  |  Normalize: " + normModeStat$
        ... + "  |  VAE loss final: " + vaeLossStat$
        ... + "  |  RMS: " + rmsInputStat$ + " -> " + rmsOutputStat$
        ... + "  |  z=" + string$(latent_size)

    # v1.2: ASCII formula -- v1.1 used `proportional-to` and middle-dot
    # which render unpredictably on some Praat installs.
    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  w_j ~ (1/dist_j^p) * (A[i,j]^q)  (pure NumPy, no external models)"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
else
    appendInfoLine: "  Visualization skipped."
endif

###############################################################################
# Text log
###############################################################################
appendInfoLine: ""
appendInfoLine: "=========================================="
appendInfoLine: "Self-Attention Latent - Run Summary"
appendInfoLine: "=========================================="
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Preset:      ", presetName$
appendInfoLine: "Output:      ", compositeName$, " (Praat object)"
appendInfoLine: "Events:      ", nEventsStat$
appendInfoLine: "Plan:        ", nStepsStat$, " steps  (", nExecStat$, " executed)"
appendInfoLine: "Phases:      drift=", driftStat$, "  mutate=", mutateStat$,
    ... "  return=", returnStat$, "  settle=", settleStat$
appendInfoLine: "Attention:   heads=", attnHeadsStat$, "  entropy=", attnEntropyStat$, " nats"
appendInfoLine: "VAE loss:    ", vaeLossStat$
appendInfoLine: "Output dur:  ", outDurStat$, " s"
appendInfoLine: "Pitch mode:  ", pitchModeStat$
appendInfoLine: "Normalize:   ", normModeStat$, "  RMS: ", rmsInputStat$, " -> ", rmsOutputStat$
appendInfoLine: "=========================================="
appendInfoLine: ""

if play_result and haveOutput
    selectObject: outSound
    Play
endif
