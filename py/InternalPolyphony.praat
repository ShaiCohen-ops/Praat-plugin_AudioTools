# ============================================================
# Praat AudioTools - InternalPolyphony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025)
# License: MIT License
#
# Description:
#   Internal Polyphony
#
#   Discovers hidden simultaneous internal voices (support, body,
#   accent, halo, residue, shimmer) latent inside one sound using
#   NMF-based functional role decomposition and source-derived
#   waveform recomposition.
#
#   This is not a denoiser, not a latent-space gimmick, and not a
#   generic spectral effect. It reveals hidden chamber music already
#   present inside the source.
#
# Python engine: internal_polyphony.py (must be in the same folder)
#
# Example workflow:
#   1. Select one Sound object in Praat
#   2. Run this script
#   3. Adjust parameters in the dialog
#   4. The result appears as <soundname>_polyphony
#
# Dependencies (Python):
#   pip install numpy scipy soundfile
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS ----
# The Python script is expected in the same directory as this Praat script.
# If running from the AudioTools plugin, pluginDir$ is used instead.
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/internal_polyphony.py"

# Fallback: look next to this script using defaultDirectory
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "internal_polyphony.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/internal_polyphony.py"
endif

tempInput$   = pluginDir$ + "temp_intpoly_input.wav"
tempOutput$  = pluginDir$ + "temp_intpoly_output.wav"
tempReport$  = pluginDir$ + "temp_intpoly_report.json"
tempCSV$     = pluginDir$ + "temp_intpoly_roles.csv"
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: internal_polyphony.py" + newline$
        ... + "Expected at: " + pythonScript$ + newline$
        ... + "Please place internal_polyphony.py next to this script" + newline$
        ... + "or inside the plugin_AudioTools/py/ folder."
endif

# ---- FORM ----
form Internal Polyphony v1.0
    optionmenu Preset: 1
        option Custom
        option Reveal (subtle)
        option Counterpoint
        option Canon
        option PedalHalo
        option FracturedChoir
    comment __ Decomposition ________________________________________________
    integer Num_components 10
    integer Fft_window 2048
    integer Hop_size 512
    optionmenu Analysis_mode: 1
        option full
        option hpss
        option transient
    comment __ Output / Staging _____________________________________________
    optionmenu Polyphony_mode: 3
        option reveal
        option counterpoint
        option canon
        option pedalhalo
        option fracturedchoir
    real Voice_density 0.65
    real Min_fragment_sec 0.15
    real Max_overlap 0.75
    real Expansion_factor 1.0
    comment __ Mix / Character _______________________________________________
    real Dry_wet 0.85
    real Accent_prominence 0.7
    real Halo_amount 0.6
    real Stereo_width 1.2
    comment __ Options _______________________________________________________
    integer Random_seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- APPLY PRESETS ----
if preset = 2
    # Reveal: gentle emergence of inner voices
    polyphony_mode = 1
    voice_density  = 0.45
    dry_wet        = 0.65
    accent_prominence = 0.4
    halo_amount    = 0.5
    stereo_width   = 0.9
    presetName$    = "Reveal"
elsif preset = 3
    # Counterpoint: stronger independence
    polyphony_mode = 2
    voice_density  = 0.7
    dry_wet        = 0.9
    accent_prominence = 0.8
    halo_amount    = 0.55
    stereo_width   = 1.3
    presetName$    = "Counterpoint"
elsif preset = 4
    # Canon: staggered role entries
    polyphony_mode = 3
    voice_density  = 0.6
    dry_wet        = 0.85
    accent_prominence = 0.6
    halo_amount    = 0.65
    stereo_width   = 1.4
    presetName$    = "Canon"
elsif preset = 5
    # PedalHalo: sustain + halo
    polyphony_mode = 4
    voice_density  = 0.55
    dry_wet        = 0.80
    accent_prominence = 0.3
    halo_amount    = 0.9
    stereo_width   = 1.5
    presetName$    = "PedalHalo"
elsif preset = 6
    # FracturedChoir: dense overlapping fragments
    polyphony_mode = 5
    voice_density  = 0.9
    dry_wet        = 0.95
    accent_prominence = 0.75
    halo_amount    = 0.5
    stereo_width   = 1.6
    presetName$    = "FracturedChoir"
else
    presetName$ = "Custom"
endif

# ---- MAP OPTION MENUS TO STRINGS ----

# analysis_mode: 1=full 2=hpss 3=transient
if analysis_mode = 1
    analysisModeStr$ = "full"
elsif analysis_mode = 2
    analysisModeStr$ = "hpss"
else
    analysisModeStr$ = "transient"
endif

# polyphony_mode: 1=reveal 2=counterpoint 3=canon 4=pedalhalo 5=fracturedchoir
if polyphony_mode = 1
    polyModeStr$ = "reveal"
elsif polyphony_mode = 2
    polyModeStr$ = "counterpoint"
elsif polyphony_mode = 3
    polyModeStr$ = "canon"
elsif polyphony_mode = 4
    polyModeStr$ = "pedalhalo"
else
    polyModeStr$ = "fracturedchoir"
endif

# ---- CLAMP VALUES ----
if num_components < 3
    num_components = 3
endif
if num_components > 24
    num_components = 24
endif
if fft_window < 256
    fft_window = 256
endif
if hop_size < 64
    hop_size = 64
endif
if hop_size > fft_window
    hop_size = fft_window / 2
endif
if voice_density < 0.05
    voice_density = 0.05
endif
if voice_density > 1
    voice_density = 1
endif
if min_fragment_sec < 0.05
    min_fragment_sec = 0.05
endif
if max_overlap < 0
    max_overlap = 0
endif
if max_overlap > 1
    max_overlap = 1
endif
if expansion_factor < 0.5
    expansion_factor = 0.5
endif
if expansion_factor > 4
    expansion_factor = 4
endif
if dry_wet < 0
    dry_wet = 0
endif
if dry_wet > 1
    dry_wet = 1
endif
if accent_prominence < 0
    accent_prominence = 0
endif
if accent_prominence > 2
    accent_prominence = 2
endif
if halo_amount < 0
    halo_amount = 0
endif
if halo_amount > 2
    halo_amount = 2
endif
if stereo_width < 0
    stereo_width = 0
endif
if stereo_width > 3
    stereo_width = 3
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Internal Polyphony v1.0 ==="
appendInfoLine: "Input:    ", soundName$
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: ""
appendInfoLine: "Components:  ", num_components
appendInfoLine: "FFT window:  ", fft_window, "  hop: ", hop_size
appendInfoLine: "Analysis:    ", analysisModeStr$
appendInfoLine: "Mode:        ", polyModeStr$
appendInfoLine: "Density:     ", fixed$(voice_density, 2)
appendInfoLine: "Dry/wet:     ", fixed$(dry_wet, 2)
appendInfoLine: "Expansion:   ", fixed$(expansion_factor, 2)
appendInfoLine: "Seed:        ", random_seed
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Ch: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Export Source Audio
# ===========================================================================

appendInfoLine: "[1/4] Exporting source audio..."

selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 2 — Detect Python
# ===========================================================================

appendInfoLine: "[2/4] Detecting Python..."

probeMarker$ = pluginDir$ + "temp_intpoly_pyprobe.ok"

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

    probeCode$ = "import numpy,scipy,soundfile; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    deleteFile: tempInput$
    exitScript: "Cannot find Python with required packages." + newline$
        ... + "  pip install numpy scipy soundfile"
endif

# ===========================================================================
# Stage 3 — Call Python Engine
# ===========================================================================

appendInfoLine: "[3/4] Running Python engine..."
appendInfoLine: "  Components: ", num_components, " | Mode: ", polyModeStr$
appendInfoLine: "  Analysis: ", analysisModeStr$, " | Density: ", fixed$(voice_density, 2)

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " --input """    + tempInput$  + """"
    ... + " --output """   + tempOutput$ + """"
    ... + " --report """   + tempReport$ + """"
    ... + " --csv """      + tempCSV$    + """"
    ... + " --components " + string$(num_components)
    ... + " --fft "        + string$(fft_window)
    ... + " --hop "        + string$(hop_size)
    ... + " --analysis "   + analysisModeStr$
    ... + " --mode "       + polyModeStr$
    ... + " --density "    + fixed$(voice_density, 4)
    ... + " --minfrag "    + fixed$(min_fragment_sec, 4)
    ... + " --maxoverlap " + fixed$(max_overlap, 4)
    ... + " --expand "     + fixed$(expansion_factor, 4)
    ... + " --drywet "     + fixed$(dry_wet, 4)
    ... + " --accent "     + fixed$(accent_prominence, 4)
    ... + " --halo "       + fixed$(halo_amount, 4)
    ... + " --width "      + fixed$(stereo_width, 4)
    ... + " --seed "       + string$(random_seed)

appendInfoLine: "  CMD: " + pythonCall$
runSystem: pythonCall$

if not fileReadable(tempOutput$)
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    exitScript: "Python engine failed — output file not found." + newline$
        ... + "Run in terminal to see error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """"
endif

# ===========================================================================
# Stage 4 — Import Result + Parse Report
# ===========================================================================

appendInfoLine: "[4/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_polyphony"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration
selectObject: sound
rms_in  = Get root-mean-square: 0, 0

# ---- Parse JSON report ----
# We extract key-value pairs from the JSON text manually (no JSON parser in Praat)

nComponents$    = "?"
effectiveComp$  = "?"
decompError$    = "?"
outputRMS$      = "?"
outputPeak$     = "?"
noveltyRatio$   = "?"
overlapDensity$ = "?"
stereoSpread$   = "?"
modeReport$     = "?"
warningReport$  = ""

# Role stats (up to 6 roles) — names assigned explicitly (no word$() needed)
nRoles = 6
roleName_1$ = "support"
roleName_2$ = "body"
roleName_3$ = "accent"
roleName_4$ = "halo"
roleName_5$ = "residue"
roleName_6$ = "shimmer"

for iR from 1 to nRoles
    role_dur_'iR'$    = "?"
    role_frags_'iR'$  = "?"
    role_avgdur_'iR'$ = "?"
    role_rms_'iR'$    = "?"
endfor

# Role timeline data (for visualization bars)
# We read activity values per role as percentages of total duration
for iR from 1 to nRoles
    roleAct_'iR' = 0
endfor

if fileReadable(tempReport$)
    reportText$ = readFile$(tempReport$)

    @parseJsonField: reportText$, "n_components"
    nComponents$ = parseJsonField.result$

    @parseJsonField: reportText$, "effective_components"
    effectiveComp$ = parseJsonField.result$

    @parseJsonField: reportText$, "decomp_error"
    decompError$ = parseJsonField.result$

    @parseJsonField: reportText$, "output_rms"
    outputRMS$ = parseJsonField.result$

    @parseJsonField: reportText$, "output_peak"
    outputPeak$ = parseJsonField.result$

    @parseJsonField: reportText$, "novelty_ratio"
    noveltyRatio$ = parseJsonField.result$

    @parseJsonField: reportText$, "overlap_density"
    overlapDensity$ = parseJsonField.result$

    @parseJsonField: reportText$, "stereo_spread"
    stereoSpread$ = parseJsonField.result$

    @parseJsonField: reportText$, "mode"
    modeReport$ = parseJsonField.result$

    @parseJsonField: reportText$, "warning"
    warningReport$ = parseJsonField.result$
    if warningReport$ = "?"
        warningReport$ = ""
    endif

    # Role-level stats (from JSON)
    for iR from 1 to nRoles
        rn$ = roleName_'iR'$
        @parseJsonField: reportText$, rn$ + "_duration"
        role_dur_'iR'$ = parseJsonField.result$

        @parseJsonField: reportText$, rn$ + "_fragments"
        role_frags_'iR'$ = parseJsonField.result$

        @parseJsonField: reportText$, rn$ + "_avg_frag_dur"
        role_avgdur_'iR'$ = parseJsonField.result$

        @parseJsonField: reportText$, rn$ + "_rms"
        role_rms_'iR'$ = parseJsonField.result$

        # Parse activity ratio for visualization bar
        @parseJsonField: reportText$, rn$ + "_activity"
        actStr$ = parseJsonField.result$
        if actStr$ <> "?" and actStr$ <> ""
            roleAct_'iR' = number(actStr$)
        endif
    endfor
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Internal Polyphony##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.45}"
    subtitleStr$ = soundName$ + " | " + presetName$
        ... + " | " + polyModeStr$
        ... + " | components=" + nComponents$
    Text: 0.5, "centre", -1.2, "half", subtitleStr$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.55, 1.40
    Select inner viewport: 0.6, 7.7, 0.60, 1.35
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Input: " + fixed$(dur, 2) + " s | SR: " + string$(sr) + " Hz | RMS: " + fixed$(rms_in, 4)

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.40, 2.25
    Select inner viewport: 0.6, 7.7, 1.45, 2.20
    selectObject: resultSound
    Colour: "{0.25, 0.50, 0.78}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Polyphony"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output: " + fixed$(durOut, 2) + " s | RMS: " + fixed$(rms_out, 4) + " | Novelty: " + noveltyRatio$

    # === Input Spectrogram ===
    Select outer viewport: 0, 8, 2.30, 3.40
    Select inner viewport: 0.6, 7.7, 2.35, 3.35
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigSpec = selected("Sound")
    else
        Copy: "tmpOrigSpec"
        tmpOrigSpec = selected("Sound")
    endif
    To Spectrogram: 0.025, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Input spectrogram"
    removeObject: specOrig, tmpOrigSpec

    # === Output Spectrogram ===
    Select outer viewport: 0, 8, 3.40, 4.50
    Select inner viewport: 0.6, 7.7, 3.45, 4.45
    selectObject: resultSound
    Extract one channel: 1
    tmpOutSpec = selected("Sound")
    To Spectrogram: 0.025, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram (L channel)"
    removeObject: specOut, tmpOutSpec

    # === Role Activity Bars ===
    Select outer viewport: 0, 8, 4.60, 6.10
    Select inner viewport: 0.6, 7.7, 4.65, 6.05

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.97}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.97, "half", "##Role Activity##"

    # Role colors: support, body, accent, halo, residue, shimmer
    rCol_1$ = "{0.25, 0.45, 0.75}"
    rCol_2$ = "{0.30, 0.65, 0.40}"
    rCol_3$ = "{0.80, 0.35, 0.25}"
    rCol_4$ = "{0.65, 0.35, 0.75}"
    rCol_5$ = "{0.55, 0.55, 0.55}"
    rCol_6$ = "{0.80, 0.70, 0.20}"

    barH = 0.10
    barTopY = 0.88
    barGap = 0.135

    for iR from 1 to nRoles
        barY = barTopY - (iR - 1) * barGap
        actVal = roleAct_'iR'
        # Clamp to [0, 1]
        if actVal < 0
            actVal = 0
        endif
        if actVal > 1
            actVal = 1
        endif

        thisCol$ = rCol_'iR'$
        # Background track
        Paint rectangle: "{0.88, 0.88, 0.92}", 0.14, 0.95, barY - barH, barY
        # Active fill
        if actVal > 0
            fillRight = 0.14 + actVal * 0.81
            Paint rectangle: thisCol$, 0.14, fillRight, barY - barH, barY
        endif

        # Label
        Font size: 6
        Colour: "Black"
        rn$ = roleName_'iR'$
        Text: 0.01, "left", barY - barH / 2, "half", rn$

        # Stats on right
        Font size: 5
        Colour: "{0.3, 0.3, 0.3}"
        rdur$ = role_dur_'iR'$
        rfrags$ = role_frags_'iR'$
        ravgd$ = role_avgdur_'iR'$
        if rdur$ = "?"
            rdur$ = "--"
        endif
        if rfrags$ = "?"
            rfrags$ = "--"
        endif
        if ravgd$ = "?"
            ravgd$ = "--"
        endif
        Text: 0.96, "right", barY - barH / 2, "half",
            ... rdur$ + "s | " + rfrags$ + "f | " + ravgd$ + "s"
    endfor

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.20, 8.00
    Select inner viewport: 0.6, 7.7, 6.25, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.94, "half", "##Summary##"

    Font size: 6
    Colour: "{0.25, 0.35, 0.60}"
    Text: 0.02, "left", 0.80, "half",
        ... "Components: " + nComponents$ + " (effective: " + effectiveComp$ + ")"
        ... + "  |  Decomp error: " + decompError$
        ... + "  |  Mode: " + modeReport$

    Colour: "{0.20, 0.55, 0.35}"
    Text: 0.02, "left", 0.65, "half",
        ... "RMS: " + fixed$(rms_in, 4) + " → " + fixed$(rms_out, 4)
        ... + "  |  Peak: " + outputPeak$
        ... + "  |  Novelty: " + noveltyRatio$

    Colour: "{0.55, 0.30, 0.65}"
    Text: 0.02, "left", 0.50, "half",
        ... "Overlap density: " + overlapDensity$
        ... + "  |  Stereo spread: " + stereoSpread$
        ... + "  |  Seed: " + string$(random_seed)

    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.02, "left", 0.35, "half",
        ... "FFT: " + string$(fft_window)
        ... + "  hop: " + string$(hop_size)
        ... + "  |  Analysis: " + analysisModeStr$
        ... + "  |  Density: " + fixed$(voice_density, 2)
        ... + "  |  Expand: " + fixed$(expansion_factor, 2)

    Colour: "{0.45, 0.35, 0.25}"
    Text: 0.02, "left", 0.20, "half",
        ... "Accent prom: " + fixed$(accent_prominence, 2)
        ... + "  |  Halo: " + fixed$(halo_amount, 2)
        ... + "  |  Width: " + fixed$(stereo_width, 2)
        ... + "  |  Dry/wet: " + fixed$(dry_wet, 2)

    if warningReport$ <> "?" and warningReport$ <> ""
        Colour: "{0.80, 0.20, 0.20}"
        Text: 0.02, "left", 0.06, "half", "WARN: " + warningReport$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup
# ===========================================================================

deleteFile: tempInput$
deleteFile: tempOutput$
if fileReadable(tempReport$)
    deleteFile: tempReport$
endif
if fileReadable(tempCSV$)
    deleteFile: tempCSV$
endif
if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

# ===========================================================================
# Summary in Info Window
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_polyphony (stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Components:       ", nComponents$, " (effective: ", effectiveComp$, ")"
appendInfoLine: "Decomp error:     ", decompError$
appendInfoLine: "Mode:             ", modeReport$
appendInfoLine: "Duration:         ", fixed$(dur, 2), " s -> ", fixed$(durOut, 2), " s"
appendInfoLine: "RMS:              ", fixed$(rms_in, 4), " -> ", fixed$(rms_out, 4)
appendInfoLine: "Output peak:      ", outputPeak$
appendInfoLine: "Novelty ratio:    ", noveltyRatio$
appendInfoLine: "Overlap density:  ", overlapDensity$
appendInfoLine: "Stereo spread:    ", stereoSpread$
appendInfoLine: ""
appendInfoLine: "Role breakdown:"
for iR from 1 to nRoles
    rn$ = roleName_'iR'$
    rdur$ = role_dur_'iR'$
    rfrags$ = role_frags_'iR'$
    ravgd$ = role_avgdur_'iR'$
    rrms$ = role_rms_'iR'$
    if rdur$ = "?"
        rdur$ = "--"
    endif
    if rfrags$ = "?"
        rfrags$ = "--"
    endif
    if ravgd$ = "?"
        ravgd$ = "--"
    endif
    if rrms$ = "?"
        rrms$ = "--"
    endif
    appendInfoLine: "  ", rn$, ":"
    appendInfoLine: "    duration=", rdur$, "s  fragments=", rfrags$, "  avgfrag=", ravgd$, "s  rms=", rrms$
endfor

if warningReport$ <> "?" and warningReport$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningReport$
endif

selectObject: resultSound

if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================

# Parse a "key": value pair from JSON text (handles strings and numbers).
# Strategy: locate the key, find the colon, then grab text up to the
# next newline or comma - avoids multi-line boolean expressions.
procedure parseJsonField: .text$, .key$
    .result$ = "?"
    .searchKey$ = """" + .key$ + """"
    .pos = index(.text$, .searchKey$)
    if .pos > 0
        .afterKey = .pos + length(.searchKey$)
        .rest$ = mid$(.text$, .afterKey, length(.text$) - .afterKey + 1)
        .colPos = index(.rest$, ":")
        if .colPos > 0
            .valStart = .colPos + 1
            .valRest$ = mid$(.rest$, .valStart, length(.rest$) - .valStart + 1)
            # Trim leading spaces
            while left$(.valRest$, 1) = " "
                .valRest$ = mid$(.valRest$, 2, length(.valRest$) - 1)
            endwhile
            # String value: starts with a quote
            if left$(.valRest$, 1) = """"
                # Strip the opening quote then find the closing one
                .inner$ = mid$(.valRest$, 2, length(.valRest$) - 1)
                .endQ = index(.inner$, """")
                if .endQ > 0
                    .result$ = left$(.inner$, .endQ - 1)
                endif
            # Numeric value: grab up to next newline, comma, or brace
            else
                .endNum = length(.valRest$)
                .nlPos = index(.valRest$, newline$)
                if .nlPos > 0
                    if .nlPos - 1 < .endNum
                        .endNum = .nlPos - 1
                    endif
                endif
                .commaPos = index(.valRest$, ",")
                if .commaPos > 0
                    if .commaPos - 1 < .endNum
                        .endNum = .commaPos - 1
                    endif
                endif
                .bracePos = index(.valRest$, "}")
                if .bracePos > 0
                    if .bracePos - 1 < .endNum
                        .endNum = .bracePos - 1
                    endif
                endif
                if .endNum < 0
                    .endNum = 0
                endif
                .result$ = left$(.valRest$, .endNum)
                # Trim trailing spaces
                while right$(.result$, 1) = " "
                    .result$ = left$(.result$, length(.result$) - 1)
                endwhile
            endif
        endif
    endif
endproc
