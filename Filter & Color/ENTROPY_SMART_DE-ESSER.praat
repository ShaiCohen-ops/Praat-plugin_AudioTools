# ============================================================
# Praat AudioTools - Entropy Smart De-Esser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Intelligent de-esser using high-frequency energy detection.
#   Detects sibilants (s, sh, ch) by comparing high-frequency
#   energy to full-band energy, then applies smooth gain reduction.
#
# Technical approach:
#   - Extracts high-frequency band (4-8 kHz) where sibilants live
#   - Compares HF intensity to full-band intensity
#   - High ratio = sibilant, low ratio = voiced sound
#   - Applies gain reduction only when ratio exceeds threshold
#   - True stereo processing preserves spatial image
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Audio algorithm UNCHANGED. Same HF/full intensity ratio
#     detection, same attack/release smoothing, same linear
#     soft-knee gain reduction above threshold, same 5 presets
#     with same values, same mono and stereo processing branches,
#     same listen_to_removed sibilant-isolation mode, same
#     dry_wet_mix logic, same Scale peak.
#   - CRITICAL FIX: `elif` -> `elsif` on 4 preset-block lines.
#     v0.3 used `elif` which is not valid Praat syntax (Praat
#     documents `elsif`). Script would fail to parse the moment
#     any non-Custom preset was selected.
#   - CRITICAL FIX: Pre-computed `suffix$` instead of inline
#     `if/then/else fi` ternary in `appendInfoLine`. v0.3's
#     inline ternary works inside Formula contexts but NOT in
#     script-level string concatenation — would fail to parse.
#   - CRITICAL FIX: `framesReduced += 1` -> `framesReduced =
#     framesReduced + 1`. Praat doesn't have compound assignment
#     operators.
#   - CRITICAL FIX: Double-remove of soundMono in the mono +
#     dry_wet_mix < 1 path. v0.3 removed soundMono by string
#     name at line 274, then tried to remove it again at line
#     336. v0.4 tracks removal with a flag and removes once.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle (preset, HF band,
#         threshold, max reduction, % frames reduced)
#       Panel A (left, headline): waveform + gain-reduction
#         curve overlay (preserving v0.3's clever trick)
#       Panel B (right, headline): HF ratio curve with
#         threshold line (preserving v0.3's diagnostic)
#       Panel C: zoom overlay (first 2 s, gray = original,
#         blue = de-essed) — shows the transformation at small
#         scale
#       Panel D: result spectrogram (full file). Default ON,
#         since the spectrogram IS the diagnostic for a de-esser
#         (you want to see HF attenuation). Made into a form
#         toggle for users who don't want the analysis cost.
#       Panel E: light-grey summary stats bar matching the
#         rest of the suite
#   - Dropped the 3 decorative `comment` form lines to keep
#     the form compact (lesson from the rest of the suite).
# Changelog v0.3:
#   - 5 presets, dual-channel processing, listen_to_removed mode
# ============================================================

form Smart De-Esser v0.4
    optionmenu Preset: 1
        option Custom
        option Light De-Essing
        option Medium De-Essing
        option Heavy De-Essing
        option Aggressive
        option Gentle Touch
    positive Hf_low_hz 4000
    positive Hf_high_hz 8000
    real Threshold 0.4
    positive Max_reduction_db 12.0
    positive Attack_ms 5
    positive Release_ms 50
    real Dry_wet_mix 1.0
    positive Scale_peak 0.95
    boolean Show_spectrogram 1
    boolean Listen_to_removed 0
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Light De-Essing"
    threshold = 0.5
    max_reduction_db = 6
    attack_ms = 5
    release_ms = 60
    presetName$ = "Light"
elsif preset$ = "Medium De-Essing"
    threshold = 0.4
    max_reduction_db = 10
    attack_ms = 5
    release_ms = 50
    presetName$ = "Medium"
elsif preset$ = "Heavy De-Essing"
    threshold = 0.3
    max_reduction_db = 15
    attack_ms = 3
    release_ms = 40
    presetName$ = "Heavy"
elsif preset$ = "Aggressive"
    threshold = 0.25
    max_reduction_db = 18
    attack_ms = 2
    release_ms = 30
    presetName$ = "Aggressive"
elsif preset$ = "Gentle Touch"
    threshold = 0.55
    max_reduction_db = 4
    attack_ms = 8
    release_ms = 80
    presetName$ = "GentleTouch"
else
    presetName$ = "Custom"
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Clamp HF band to Nyquist
if hf_high_hz > nyquist * 0.95
    hf_high_hz = nyquist * 0.95
endif
if hf_low_hz > hf_high_hz - 500
    hf_low_hz = hf_high_hz - 500
endif

minGainLinear = 10 ^ (-max_reduction_db / 20)
attackTime = attack_ms / 1000
releaseTime = release_ms / 1000

uniqueID$ = string$(randomInteger(10000, 99999))

# Pre-compute output suffix (avoids inline ternary in appendInfoLine)
if listen_to_removed = 0
    suffix$ = "_deessed"
else
    suffix$ = "_sibilants"
endif

# ============================================================
# Analysis
# ============================================================
writeInfoLine: "Smart De-Esser v0.4"
appendInfoLine: "===================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "[1/4] Analyzing sibilance..."

# Convert to mono for analysis
if numChannels > 1
    selectObject: sound
    soundMono = Convert to mono
else
    selectObject: sound
    soundMono = Copy: "mono_" + uniqueID$
endif

# Track whether soundMono has been removed (fixes v0.3's
# double-remove bug in the mono + dry_wet_mix < 1 path)
soundMonoRemoved = 0

# Get full-band intensity
selectObject: soundMono
fullIntensity = To Intensity: 100, 0, "yes"
Rename: "full_" + uniqueID$

# Get high-frequency band intensity
selectObject: soundMono
hfFiltered = Filter (pass Hann band): hf_low_hz, hf_high_hz, 100
hfIntensity = To Intensity: 100, 0, "yes"
Rename: "hf_" + uniqueID$

removeObject: hfFiltered

# ============================================================
# Compute sibilance ratio and gain curve
# ============================================================
appendInfoLine: "[2/4] Computing gain curve..."

# Sample at regular intervals
timeStep = 0.005
numFrames = floor(duration / timeStep)
if numFrames < 2
    numFrames = 2
endif

# Calculate ratio and gain for each frame
for i from 1 to numFrames
    t = (i - 1) * timeStep
    if t > duration
        t = duration
    endif
    
    timeVal[i] = t
    
    selectObject: fullIntensity
    fullDb = Get value at time: t, "Cubic"
    
    selectObject: hfIntensity
    hfDb = Get value at time: t, "Cubic"
    
    # Handle undefined values
    if fullDb = undefined
        fullDb = -80
    endif
    if hfDb = undefined
        hfDb = -80
    endif
    
    # Convert to linear and compute ratio
    fullLin = 10 ^ (fullDb / 20)
    hfLin = 10 ^ (hfDb / 20)
    
    if fullLin > 0.0001
        ratioVal[i] = hfLin / fullLin
    else
        ratioVal[i] = 0
    endif
    
    # Clamp ratio
    if ratioVal[i] > 1
        ratioVal[i] = 1
    endif
endfor

# ============================================================
# Apply attack/release smoothing
# ============================================================
appendInfoLine: "[3/4] Smoothing..."

attackCoef = 1 - exp(-2.2 / (attackTime / timeStep + 1))
releaseCoef = 1 - exp(-2.2 / (releaseTime / timeStep + 1))

smoothedRatio[1] = ratioVal[1]
for i from 2 to numFrames
    if ratioVal[i] > smoothedRatio[i-1]
        # Attack (rising)
        smoothedRatio[i] = smoothedRatio[i-1] + attackCoef * (ratioVal[i] - smoothedRatio[i-1])
    else
        # Release (falling)
        smoothedRatio[i] = smoothedRatio[i-1] + releaseCoef * (ratioVal[i] - smoothedRatio[i-1])
    endif
endfor

# Calculate gain from smoothed ratio
maxRatio = 0
minRatio = 1
framesReduced = 0

for i from 1 to numFrames
    r = smoothedRatio[i]
    
    if r > maxRatio
        maxRatio = r
    endif
    if r < minRatio
        minRatio = r
    endif
    
    if r < threshold
        gainVal[i] = 1
    else
        # Linear reduction above threshold
        reduction = (r - threshold) / (1 - threshold)
        gainVal[i] = 1 - reduction * (1 - minGainLinear)
        if gainVal[i] < minGainLinear
            gainVal[i] = minGainLinear
        endif
        # v0.4 fix: Praat has no compound assignment (+=); use full form
        framesReduced = framesReduced + 1
    endif
endfor

# ============================================================
# Create gain tier
# ============================================================
Create IntensityTier: "gain_" + uniqueID$, 0, duration
gainTier = selected("IntensityTier")

for i from 1 to numFrames
    Add point: timeVal[i], gainVal[i]
endfor

# ============================================================
# Apply gain
# ============================================================
appendInfoLine: "[4/4] Applying de-essing..."

if numChannels = 1
    selectObject: soundMono
    processed = Copy: "processed_" + uniqueID$
    
    if listen_to_removed = 0
        Formula: "self * IntensityTier_gain_'uniqueID$'(x)"
    else
        Formula: "self * (1 - IntensityTier_gain_'uniqueID$'(x))"
    endif
    
    if dry_wet_mix < 1 and listen_to_removed = 0
        selectObject: soundMono
        Rename: "dry_" + uniqueID$
        selectObject: processed
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dry_'uniqueID$'(x)"
        # v0.4 fix: remove soundMono ONCE, using its ID (not by string name)
        removeObject: soundMono
        soundMonoRemoved = 1
    endif
    
    selectObject: processed
    finalOutput = selected("Sound")
else
    selectObject: sound
    Extract one channel: 1
    left = selected("Sound")
    
    selectObject: sound
    Extract one channel: 2
    right = selected("Sound")
    
    if listen_to_removed = 0
        selectObject: left
        Formula: "self * IntensityTier_gain_'uniqueID$'(x)"
        selectObject: right
        Formula: "self * IntensityTier_gain_'uniqueID$'(x)"
    else
        selectObject: left
        Formula: "self * (1 - IntensityTier_gain_'uniqueID$'(x))"
        selectObject: right
        Formula: "self * (1 - IntensityTier_gain_'uniqueID$'(x))"
    endif
    
    if dry_wet_mix < 1 and listen_to_removed = 0
        selectObject: sound
        Extract one channel: 1
        dryL = selected("Sound")
        Rename: "dryL_" + uniqueID$
        
        selectObject: sound
        Extract one channel: 2
        dryR = selected("Sound")
        Rename: "dryR_" + uniqueID$
        
        selectObject: left
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryL_'uniqueID$'(x)"
        selectObject: right
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryR_'uniqueID$'(x)"
        
        removeObject: dryL, dryR
    endif
    
    selectObject: left, right
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: left, right
endif

selectObject: finalOutput
Scale peak: scale_peak

Rename: originalName$ + suffix$

# Cleanup — only remove soundMono if it wasn't already removed
if soundMonoRemoved = 0
    removeObject: soundMono
endif
removeObject: fullIntensity, hfIntensity, gainTier

# Capture final stats for visualization
selectObject: finalOutput
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

reducedPct = framesReduced / numFrames * 100

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization
    
    Erase all
    Black
    Plain line
    
    # ----------------------------------------------------------
    # Compute spectrogram ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrogram
        selectObject: finalOutput
        if numChannels > 1
            Convert to mono
            specSource = selected("Sound")
        else
            Copy: "spec_src_" + uniqueID$
            specSource = selected("Sound")
        endif
        selectObject: specSource
        To Spectrogram: 0.005, 8000, 0.002, 20, "Gaussian"
        resultSpec = selected("Spectrogram")
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ENTROPY SMART DE-ESSER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  HF " + fixed$(hf_low_hz, 0) + "-" + fixed$(hf_high_hz, 0) + " Hz"
        ... + "  |  thresh " + fixed$(threshold, 2)
        ... + "  |  max -" + fixed$(max_reduction_db, 1) + " dB"
        ... + "  |  reduced " + fixed$(reducedPct, 1) + "% of frames"
    
    # ----------------------------------------------------------
    # PANEL A: WAVEFORM + GAIN REDUCTION  (left, headline)
    # Preserves v0.3's clever overlay: waveform in gray behind,
    # gain reduction (1 - gainVal) curve in red on top.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    # Mono copy of source for waveform display
    selectObject: sound
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "orig_viz_" + uniqueID$
    endif
    
    selectObject: origMono
    src_peak = Get absolute extremum: 0, 0, "None"
    if src_peak < 0.001
        src_peak = 0.001
    endif
    src_amp = src_peak * 1.15
    
    # Waveform axes
    Axes: 0, duration, -src_amp, src_amp
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration, -src_amp, src_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0
    
    # Source waveform (gray)
    selectObject: origMono
    Colour: "{0.60, 0.60, 0.60}"
    Line width: 1
    Draw: 0, duration, -src_amp, src_amp, "no", "Curve"
    
    # Gain-reduction curve overlay (red).
    # Reduction is normalised to fit within the waveform's positive half
    # so it sits ABOVE the source waveform visually.
    Colour: "{0.88, 0.28, 0.28}"
    Line width: 2
    
    redMax = src_amp * 0.9
    for i from 1 to numFrames - 1
        g1_norm = (1 - gainVal[i]) * redMax
        g2_norm = (1 - gainVal[i + 1]) * redMax
        Draw line: timeVal[i], g1_norm, timeVal[i + 1], g2_norm
    endfor
    Line width: 1
    
    removeObject: origMono
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp / Red."
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: HF RATIO + THRESHOLD  (right, headline)
    # Preserves v0.3's diagnostic: smoothed HF/full ratio in
    # blue with horizontal threshold reference line in red.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration, 0, 1
    
    # Light reference grid
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.25, duration, 0.25
    Draw line: 0, 0.50, duration, 0.50
    Draw line: 0, 0.75, duration, 0.75
    Solid line
    
    # Threshold line (red, dashed)
    Colour: "{0.85, 0.25, 0.25}"
    Line width: 1.5
    Dotted line
    Draw line: 0, threshold, duration, threshold
    Solid line
    
    # Ratio curve (blue)
    Colour: "{0.20, 0.50, 0.80}"
    Line width: 1.8
    for i from 1 to numFrames - 1
        Draw line: timeVal[i], smoothedRatio[i], timeVal[i + 1], smoothedRatio[i + 1]
    endfor
    Line width: 1
    
    # Threshold label inline
    Font size: 5
    Colour: "{0.85, 0.25, 0.25}"
    Text: duration * 0.02, "left", threshold + 0.04, "half", "thresh " + fixed$(threshold, 2)
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "HF/full ratio"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Waveform (gray) + Gain reduction (red)"
    Text: 6.10, "centre", 7.30, "half",
        ... "HF/full ratio (blue), threshold " + fixed$(threshold, 2) + " (red)"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 2 s)
    # Gray = original, blue = de-essed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 2.0
    if zoomDur > duration
        zoomDur = duration
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    # Mono copies for the zoom panel
    selectObject: sound
    if numChannels > 1
        zoomOrig = Convert to mono
    else
        zoomOrig = Copy: "zoom_orig_" + uniqueID$
    endif
    
    selectObject: finalOutput
    if numChannels > 1
        zoomOut = Convert to mono
    else
        zoomOut = Copy: "zoom_out_" + uniqueID$
    endif
    
    selectObject: zoomOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: zoomOut
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original behind
    selectObject: zoomOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # De-essed on top
    selectObject: zoomOut
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    removeObject: zoomOrig, zoomOut
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur, 1) + " s  (gray = original, blue = de-essed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: RESULT SPECTROGRAM (the de-esser's diagnostic)
    # OR a placeholder note if Show_spectrogram = OFF.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if show_spectrogram
        selectObject: resultSpec
        Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Result spectrogram (0-8 kHz)"
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        # Placeholder if user opted out of the spectrogram
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        Font size: 8
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.5, "centre", 0.5, "half", "Result spectrogram disabled (Show_spectrogram = OFF)"
        Colour: "Black"
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if listen_to_removed = 0
        modeStr$ = "de-essed"
    else
        modeStr$ = "sibilants-only"
    endif
    
    if show_spectrogram
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$ + suffix$
        ... + "  |  HF " + fixed$(hf_low_hz, 0) + "-" + fixed$(hf_high_hz, 0) + " Hz"
        ... + "  |  Threshold: " + fixed$(threshold, 2)
        ... + "  |  Max red: -" + fixed$(max_reduction_db, 1) + " dB"
        ... + "  |  Atk/Rel: " + fixed$(attack_ms, 0) + "/" + fixed$(release_ms, 0) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Mode: " + modeStr$
        ... + "  |  Reduced " + string$(framesReduced) + "/" + string$(numFrames) + " frames (" + fixed$(reducedPct, 1) + "%)"
        ... + "  |  HF ratio range: " + fixed$(minRatio, 2) + "-" + fixed$(maxRatio, 2)
        ... + "  |  Mix: " + fixed$(dry_wet_mix, 2)
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Spec: " + specStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectrogram if computed
    if show_spectrogram
        removeObject: resultSpec, specSource
    endif
endif

selectObject: finalOutput

if play_after_processing
    Play
endif

appendInfoLine: ""
appendInfoLine: "===================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", originalName$, suffix$
appendInfoLine: "Channels: ", numChannels
appendInfoLine: ""
appendInfoLine: "HF band: ", fixed$(hf_low_hz, 0), " - ", fixed$(hf_high_hz, 0), " Hz"
appendInfoLine: "Threshold: ", fixed$(threshold, 2)
appendInfoLine: "Max reduction: ", max_reduction_db, " dB"
appendInfoLine: "HF ratio range: ", fixed$(minRatio, 2), " - ", fixed$(maxRatio, 2)
appendInfoLine: "Frames reduced: ", framesReduced, " / ", numFrames, " (", fixed$(reducedPct, 1), "%)"
if draw_visualization
    appendInfoLine: "Visualization in Picture window."
endif
