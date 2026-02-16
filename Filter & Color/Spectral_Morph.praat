# ============================================================
# Praat AudioTools - Spectral_Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP-like Spectral Morph v3.0 - true STFT spectral morphing
#   between two sounds. Per-frame processing with log-space
#   magnitude interpolation and sample-accurate overlap-add
#   reconstruction.
#
#   Architecture:
#   1. Time-warp shorter sound to match longer (Manipulation)
#   2. Pre-allocate output buffer (zero-filled Sound)
#   3. Frame-by-frame STFT:
#      - Extract frame, apply Hann window
#      - FFT both, morph via vectorized Formula
#      - IFFT, write samples directly into output buffer
#   4. Sample-accurate OLA: no Concatenate calls, no SR drift
#   5. Multi-panel visualization
#
#   Morph modes:
#   - Log magnitude: geometric A^(1-m) * B^m, preserves A phase
#   - Full complex: linear re+im interpolation
#
# Category: Time & Granular
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects."
        ... + newline$ + "Sound 1 = A (source), Sound 2 = B (target)."
endif

soundA = selected("Sound", 1)
soundB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

form Spectral Morph v3
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Tonal Sustained (instruments, pads)
        option Percussive (drums, impacts)
        option Voice Morph (speech, vocals)
        option Texture Blend (ambience, noise)
        option Fast Preview (low quality, quick)
    comment === Morph Region ===
    real Start_morph_s 0
    real End_morph_s 0
    optionmenu Curve_type: 2
        option Linear
        option Cosine (smooth S-curve)
    comment === Analysis ===
    positive Window_ms 60
    positive Max_freq_Hz 8000
    optionmenu Speed_mode: 2
        option Full (native sample rate)
        option 22050 Hz
        option 11025 Hz
    comment === Morph Type ===
    optionmenu Morph_mode: 1
        option Log magnitude (preserve A phase)
        option Full complex (blend phase too)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================================
# Apply Presets
# ============================================================

if preset = 2
    # Tonal Sustained
    window_ms = 60
    max_freq_Hz = 8000
    speed_mode = 2
    morph_mode = 1
    curve_type = 2
    presetName$ = "TonalSustained"
elsif preset = 3
    # Percussive
    window_ms = 30
    max_freq_Hz = 10000
    speed_mode = 2
    morph_mode = 1
    curve_type = 1
    presetName$ = "Percussive"
elsif preset = 4
    # Voice Morph
    window_ms = 50
    max_freq_Hz = 6000
    speed_mode = 2
    morph_mode = 1
    curve_type = 2
    presetName$ = "VoiceMorph"
elsif preset = 5
    # Texture Blend
    window_ms = 80
    max_freq_Hz = 12000
    speed_mode = 1
    morph_mode = 2
    curve_type = 2
    presetName$ = "TextureBlend"
elsif preset = 6
    # Fast Preview
    window_ms = 120
    max_freq_Hz = 5000
    speed_mode = 3
    morph_mode = 1
    curve_type = 1
    presetName$ = "FastPreview"
else
    presetName$ = "Custom"
endif

# ============================================================
# Global Parameters
# ============================================================

window_s = window_ms / 1000
hop_s = window_s / 2

selectObject: soundA
srA = Get sampling frequency
durA = Get total duration
chA = Get number of channels

selectObject: soundB
srB = Get sampling frequency
durB = Get total duration
chB = Get number of channels

# Target sample rate
if speed_mode = 2
    targetSR = 22050
elsif speed_mode = 3
    targetSR = 11025
else
    targetSR = srA
    if srB > targetSR
        targetSR = srB
    endif
endif

# Clamp max_freq to Nyquist
nyquist = targetSR / 2
if max_freq_Hz > nyquist - 100
    max_freq_Hz = nyquist - 100
endif

samplesPerFrame = round(window_s * targetSR)

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  Spectral Morph v3.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Sound A: ", nameA$, " (", fixed$(durA, 2), " s, ", srA, " Hz)"
appendInfoLine: "Sound B: ", nameB$, " (", fixed$(durB, 2), " s, ", srB, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target SR: ", targetSR, " Hz"
appendInfoLine: "Window: ", fixed$(window_ms, 0), " ms (", samplesPerFrame, " samples) | Hop: ", fixed$(hop_s * 1000, 0), " ms"
appendInfoLine: ""

# ============================================================
# STEP 1: Prepare sounds
# ============================================================
appendInfoLine: "[1/4] Preparing sounds..."

# Convert to mono
selectObject: soundA
if chA > 1
    monoA = Convert to mono
else
    monoA = Copy: "monoA"
endif

selectObject: soundB
if chB > 1
    monoB = Convert to mono
else
    monoB = Copy: "monoB"
endif

# Resample
selectObject: monoA
currentSR_A = Get sampling frequency
if currentSR_A <> targetSR
    Resample: targetSR, 50
    temp = selected("Sound")
    removeObject: monoA
    monoA = temp
endif

selectObject: monoB
currentSR_B = Get sampling frequency
if currentSR_B <> targetSR
    Resample: targetSR, 50
    temp = selected("Sound")
    removeObject: monoB
    monoB = temp
endif

# Duration: output = longer of the two, both mapped proportionally
selectObject: monoA
durA_final = Get total duration
selectObject: monoB
durB_final = Get total duration

if durA_final >= durB_final
    commonDuration = durA_final
else
    commonDuration = durB_final
endif
timeRatioA = durA_final / commonDuration
timeRatioB = durB_final / commonDuration

# Normalize both to equal peak
selectObject: monoA
Scale peak: 0.95
selectObject: monoB
Scale peak: 0.95

appendInfoLine: "  A duration: ", fixed$(durA_final, 3), " s"
appendInfoLine: "  B duration: ", fixed$(durB_final, 3), " s"
appendInfoLine: "  Output duration: ", fixed$(commonDuration, 3), " s (longer of the two)"
appendInfoLine: "  A maps: ", fixed$(timeRatioA, 4), " | B maps: ", fixed$(timeRatioB, 4)

# Set morph region
if end_morph_s <= start_morph_s or end_morph_s <= 0
    end_morph_s = commonDuration
endif
if start_morph_s < 0
    start_morph_s = 0
endif
if end_morph_s > commonDuration
    end_morph_s = commonDuration
endif
morphRange = end_morph_s - start_morph_s
if morphRange < 0.01
    morphRange = 0.01
endif

if morph_mode = 1
    modeLabel$ = "Log magnitude (A phase)"
else
    modeLabel$ = "Full complex"
endif
if curve_type = 2
    curveLabel$ = "Cosine"
else
    curveLabel$ = "Linear"
endif

appendInfoLine: "  Morph: ", fixed$(start_morph_s, 2), " - ", fixed$(end_morph_s, 2), " s"
appendInfoLine: "  Mode: ", modeLabel$, " | Curve: ", curveLabel$
appendInfoLine: ""

# ============================================================
# STEP 2: FRAME-BY-FRAME STFT MORPH
# ============================================================
appendInfoLine: "[2/4] STFT morphing..."

# Pre-allocate output buffer
Create Sound from formula: "morph_buffer", 1, 0, commonDuration, targetSR, "0"
outputBuffer = selected("Sound")

# Compute frame count
totalFrames = floor((commonDuration - window_s) / hop_s) + 1
if totalFrames < 1
    totalFrames = 1
endif

appendInfoLine: "  Frames: ", totalFrames
appendInfoLine: "  Window: ", fixed$(window_s * 1000, 1), " ms | Hop: ", fixed$(hop_s * 1000, 1), " ms"
appendInfoLine: "  Processing..."

progressStep = floor(totalFrames / 10)
if progressStep < 1
    progressStep = 1
endif

for f from 1 to totalFrames
    frameStart = (f - 1) * hop_s
    frameEnd = frameStart + window_s
    if frameEnd > commonDuration
        frameEnd = commonDuration
    endif
    if frameEnd - frameStart < 0.005
        frameEnd = frameStart + 0.005
    endif
    if frameEnd > commonDuration
        frameEnd = commonDuration
    endif
    
    # --- Morph factor ---
    frameMid = (frameStart + frameEnd) / 2
    u = (frameMid - start_morph_s) / morphRange
    if u < 0
        u = 0
    endif
    if u > 1
        u = 1
    endif
    if curve_type = 2
        m = 0.5 - 0.5 * cos(pi * u)
    else
        m = u
    endif
    
    # --- Extract frame from A (mapped into output timeline) ---
    frameAmid = frameMid * timeRatioA
    frameAstart = frameAmid - window_s / 2
    frameAend = frameAstart + window_s
    
    if frameAstart < 0
        frameAstart = 0
        frameAend = window_s
    endif
    if frameAend > durA_final
        frameAend = durA_final
        frameAstart = durA_final - window_s
    endif
    if frameAstart < 0
        frameAstart = 0
    endif
    
    selectObject: monoA
    Extract part: frameAstart, frameAend, "rectangular", 1, "no"
    frameA = selected("Sound")
    
    # --- Extract frame from B (mapped into output timeline) ---
    frameBmid = frameMid * timeRatioB
    frameBstart = frameBmid - window_s / 2
    frameBend = frameBstart + window_s
    
    if frameBstart < 0
        frameBstart = 0
        frameBend = window_s
    endif
    if frameBend > durB_final
        frameBend = durB_final
        frameBstart = durB_final - window_s
    endif
    if frameBstart < 0
        frameBstart = 0
    endif
    
    selectObject: monoB
    Extract part: frameBstart, frameBend, "rectangular", 1, "no"
    frameB = selected("Sound")
           
    # --- Apply sqrt-Hann analysis window ---
    selectObject: frameA
    frameDur = Get total duration
    Formula: "self * sin(pi * (x - xmin) / frameDur)"
    
    selectObject: frameB
    Formula: "self * sin(pi * (x - xmin) / frameDur)"
    
    # --- FFT ---
    selectObject: frameA
    specA = To Spectrum: "no"
    
    selectObject: frameB
    specB = To Spectrum: "no"
    
    # --- Morph spectrum ---
    selectObject: specA
    outSpec = Copy: "morph"
    idA = specA
    idB = specB
    
    selectObject: outSpec
    if morph_mode = 1
        Formula: "self * min((max(sqrt(object[idB,1,col]^2 + object[idB,2,col]^2), 1e-4) / max(sqrt(object[idA,1,col]^2 + object[idA,2,col]^2), 1e-4)), 30) ^ m"
    else
        Formula: "(1 - m) * object[idA, row, col] + m * object[idB, row, col]"
    endif
    
    # --- IFFT + sqrt-Hann synthesis window ---
    selectObject: outSpec
    To Sound
    frameOut = selected("Sound")
    Override sampling frequency: targetSR
    
    synthDur = Get total duration
    Formula: "self * sin(pi * (x - xmin) / synthDur)"
    
    Rename: "morphfr"
    
    # Shift to correct time position
    Shift times to: "start time", frameStart
    
    # --- OLA: add to output buffer ---
    selectObject: outputBuffer
    Formula (part): frameStart, frameEnd, 1, 1, "self + Sound_morphfr(x)"
    
    # Cleanup
    removeObject: frameA, frameB, specA, specB, outSpec, frameOut
    
    # Progress
    if f mod progressStep = 0
        pct = round(f / totalFrames * 100)
        appendInfoLine: "    ", pct, "% (frame ", f, "/", totalFrames, ")"
    endif
endfor

appendInfoLine: "  Done."

# ============================================================
# STEP 3: FINALIZE
# ============================================================
appendInfoLine: ""
appendInfoLine: "[3/4] Finalizing..."

selectObject: outputBuffer
Scale peak: 0.99

# Fade in 5 ms
fadeInDur = 0.005
Formula: "if x < fadeInDur then self * (x / fadeInDur) else self fi"

# Fade out 50 ms
fadeOutDur = 0.05
outDurFinal = Get total duration
if fadeOutDur > outDurFinal * 0.1
    fadeOutDur = outDurFinal * 0.1
endif
Formula: "if x > (xmax - fadeOutDur) then self * ((xmax - x) / fadeOutDur) else self fi"

Rename: "Spectral_Morph"
finalOutput = selected("Sound")
outputDuration = Get total duration

appendInfoLine: "  Output: ", fixed$(outputDuration, 2), " s"

# ============================================================
# STEP 4: VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[4/4] Visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Spectral Morph v3.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half", nameA$ + " -> " + nameB$ + " | " + presetName$ + " | " + modeLabel$
    
    # === SOUND A ===
    Select outer viewport: 0, 4, 0.6, 1.4
    Select inner viewport: 0.6, 3.7, 0.7, 1.35
    selectObject: monoA
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "A"
    Text top: "no", nameA$
    
    # === SOUND B ===
    Select outer viewport: 4, 8, 0.6, 1.4
    Select inner viewport: 4.4, 7.7, 0.7, 1.35
    selectObject: monoB
    Colour: "{0.8, 0.4, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "B"
    Text top: "no", nameB$
    
    # === MORPH CURVE ===
    Select outer viewport: 0, 8, 1.5, 2.6
    Select inner viewport: 0.6, 7.7, 1.6, 2.5
    Axes: 0, commonDuration, -0.05, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, commonDuration, -0.05, 1.1
    Paint rectangle: "{0.92, 0.95, 1.0}", start_morph_s, end_morph_s, -0.05, 1.1
    
    Colour: "{0.2, 0.2, 0.7}"
    Line width: 2.5
    vizPoints = 100
    vizStep = commonDuration / vizPoints
    prevT = 0
    prevU = (0 - start_morph_s) / morphRange
    if prevU < 0
        prevU = 0
    endif
    if prevU > 1
        prevU = 1
    endif
    if curve_type = 2
        prevM = 0.5 - 0.5 * cos(pi * prevU)
    else
        prevM = prevU
    endif
    for vp from 1 to vizPoints
        curT = vp * vizStep
        curU = (curT - start_morph_s) / morphRange
        if curU < 0
            curU = 0
        endif
        if curU > 1
            curU = 1
        endif
        if curve_type = 2
            curM = 0.5 - 0.5 * cos(pi * curU)
        else
            curM = curU
        endif
        Draw line: prevT, prevM, curT, curM
        prevT = curT
        prevM = curM
    endfor
    Line width: 1
    
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0, "left", 1.05, "half", "A"
    Colour: "{0.8, 0.4, 0.3}"
    Text: commonDuration, "right", 1.05, "half", "B"
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, commonDuration, 0
    Draw line: 0, 1, commonDuration, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Morph (0-1)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Morph Curve (" + curveLabel$ + ", per-frame)"
    
    # === SPECTROGRAM A ===
    Select outer viewport: 0, 4, 2.7, 3.9
    Select inner viewport: 0.6, 3.7, 2.8, 3.8
    selectObject: monoA
    To Spectrogram: 0.005, max_freq_Hz, 0.002, 20, "Gaussian"
    specgramA = selected("Spectrogram")
    Paint: 0, 0, 0, max_freq_Hz, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "A Spectrogram"
    removeObject: specgramA
    
    # === SPECTROGRAM B ===
    Select outer viewport: 4, 8, 2.7, 3.9
    Select inner viewport: 4.4, 7.7, 2.8, 3.8
    selectObject: monoB
    To Spectrogram: 0.005, max_freq_Hz, 0.002, 20, "Gaussian"
    specgramB = selected("Spectrogram")
    Paint: 0, 0, 0, max_freq_Hz, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "B Spectrogram"
    removeObject: specgramB
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 4.0, 4.8
    Select inner viewport: 0.6, 7.7, 4.1, 4.75
    selectObject: finalOutput
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out"
    Text top: "no", "Spectral Morph v3.0 | " + fixed$(outputDuration, 2) + " s"
    
    # === OUTPUT SPECTROGRAM ===
    Select outer viewport: 0, 8, 4.9, 6.1
    Select inner viewport: 0.6, 7.7, 5.0, 6.0
    selectObject: finalOutput
    To Spectrogram: 0.005, max_freq_Hz, 0.002, 20, "Gaussian"
    specgramOut = selected("Spectrogram")
    Paint: 0, 0, 0, max_freq_Hz, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output Spectrogram"
    removeObject: specgramOut
    
    # === STATS ===
    Select outer viewport: 0, 8, 6.2, 7.0
    Select inner viewport: 0.6, 7.7, 6.3, 6.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##v3.0 Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    Text: 0.02, "left", 0.62, "half", "A: " + nameA$ + " (" + fixed$(durA, 2) + "s) | B: " + nameB$ + " (" + fixed$(durB, 2) + "s) | Out: " + fixed$(outputDuration, 2) + "s"
    Text: 0.02, "left", 0.38, "half", modeLabel$ + " | " + curveLabel$ + " | " + string$(targetSR) + " Hz | " + fixed$(window_ms, 0) + "ms window | " + string$(totalFrames) + " frames"
    Text: 0.02, "left", 0.15, "half", "Morph: " + fixed$(start_morph_s, 2) + "-" + fixed$(end_morph_s, 2) + "s | Preset: " + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 7.05, 7.4
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: 0.05, 0.5, 0.09, 0.5
    Colour: "Black"
    Text: 0.10, "left", 0.5, "half", "Sound A"
    Colour: "{0.8, 0.4, 0.3}"
    Draw line: 0.25, 0.5, 0.29, 0.5
    Colour: "Black"
    Text: 0.30, "left", 0.5, "half", "Sound B"
    Colour: "{0.4, 0.6, 0.4}"
    Draw line: 0.45, 0.5, 0.49, 0.5
    Colour: "Black"
    Text: 0.50, "left", 0.5, "half", "Output"
    Colour: "{0.2, 0.2, 0.7}"
    Line width: 2
    Draw line: 0.65, 0.5, 0.69, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.70, "left", 0.5, "half", "Morph curve"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoA, monoB

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""

if play_output
    Play
endif
