# ============================================================
# Praat AudioTools - Photo_Pitch_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Real phase-continuous synthesis
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonifies an image by mapping brightness to pitch:
#   - Brightness (avg RGB) → Pitch (continuous tone)
#   - Red-Blue balance → Stereo pan
#
#   Uses phase-continuous synthesis to avoid clicks at
#   frequency transitions.
#
# Usage:
#   Select a Photo object in Praat, then run this script.
#
# Changelog v0.2:
#   - Fixed stereo panning (was broken)
#   - Added phase-continuous synthesis (no clicks)
#   - Added image downsampling for large images
#   - Added visualization
#
# Changelog v0.3:
#   - Synthesis now integrates frequency to phase (true phase continuity);
#     the old sin(2*pi*freq*x) drifted sharp as the sound progressed.
#   - Step envelopes built with one lookup Formula each (was per-column).
# ============================================================

form Photo Pitch Sonification (Brightness to Pitch)
    comment === Timing ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    
    comment === Pitch Range ===
    integer Min_pitch_Hz 100
    integer Max_pitch_Hz 1000
    
    comment === Analysis Resolution ===
    integer Analysis_columns 200 (= time slices, 50-500)
    integer Analysis_rows 100 (= vertical samples, 20-200)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check for Photo selection ===
nPhotos = numberOfSelected("Photo")
if nPhotos = 0
    exitScript: "Please select a Photo object first."
endif

photoID = selected("Photo")

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Extract RGB Channels ===
selectObject: photoID
photoName$ = selected$("Photo")

selectObject: photoID
Extract red
redID = selected("Matrix")

selectObject: photoID
Extract green
greenID = selected("Matrix")

selectObject: photoID
Extract blue
blueID = selected("Matrix")

# === Get Image Dimensions ===
selectObject: redID
imgRows = Get number of rows
imgCols = Get number of columns

if imgCols <= 0 or imgRows <= 0
    removeObject: redID, greenID, blueID
    exitScript: "Invalid image dimensions."
endif

# === Clamp analysis resolution ===
if analysis_columns > imgCols
    analysis_columns = imgCols
endif
if analysis_rows > imgRows
    analysis_rows = imgRows
endif

colStep = imgCols / analysis_columns
rowStep = imgRows / analysis_rows

# === Info ===
writeInfoLine: "=== Photo Pitch Sonification ==="
appendInfoLine: "Image: ", photoName$
appendInfoLine: "Original: ", imgCols, " x ", imgRows
appendInfoLine: "Analysis: ", analysis_columns, " x ", analysis_rows
appendInfoLine: "Pitch range: ", min_pitch_Hz, " - ", max_pitch_Hz, " Hz"
appendInfoLine: ""

# === Get Min/Max ===
selectObject: redID
minRed = Get minimum
maxRed = Get maximum

selectObject: greenID
minGreen = Get minimum
maxGreen = Get maximum

selectObject: blueID
minBlue = Get minimum
maxBlue = Get maximum

overallMin = min(minRed, min(minGreen, minBlue))
overallMax = max(maxRed, max(maxGreen, maxBlue))
valueRange = overallMax - overallMin
if valueRange = 0
    valueRange = 1
endif

# === Compute Downsampled Column Statistics ===
appendInfoLine: "Analyzing image columns..."

for aCol to analysis_columns
    imgCol = round((aCol - 0.5) * colStep)
    if imgCol < 1
        imgCol = 1
    endif
    if imgCol > imgCols
        imgCol = imgCols
    endif
    
    rSum = 0
    gSum = 0
    bSum = 0
    
    for aRow to analysis_rows
        imgRow = round((aRow - 0.5) * rowStep)
        if imgRow < 1
            imgRow = 1
        endif
        if imgRow > imgRows
            imgRow = imgRows
        endif
        
        selectObject: redID
        .rVal = Get value in cell: imgRow, imgCol
        rSum = rSum + .rVal
        
        selectObject: greenID
        .gVal = Get value in cell: imgRow, imgCol
        gSum = gSum + .gVal
        
        selectObject: blueID
        .bVal = Get value in cell: imgRow, imgCol
        bSum = bSum + .bVal
    endfor
    
    rAvg = rSum / analysis_rows
    gAvg = gSum / analysis_rows
    bAvg = bSum / analysis_rows
    
    rNorm = (rAvg - overallMin) / valueRange
    gNorm = (gAvg - overallMin) / valueRange
    bNorm = (bAvg - overallMin) / valueRange
    
    brightness[aCol] = (rNorm + gNorm + bNorm) / 3
    brightness[aCol] = max(0, min(1, brightness[aCol]))
    
    pan[aCol] = 0.5 + 0.5 * (rNorm - bNorm)
    pan[aCol] = max(0, min(1, pan[aCol]))
    
    # Calculate frequency for this column
    freq[aCol] = min_pitch_Hz + brightness[aCol] * (max_pitch_Hz - min_pitch_Hz)
    
    if aCol mod 50 = 0
        appendInfoLine: "  Column ", aCol, "/", analysis_columns
    endif
endfor

# === Create Frequency and Pan Envelope Sounds ===
appendInfoLine: ""
appendInfoLine: "Creating control envelopes..."

chunkDuration = duration_s / analysis_columns

# Hold each column's value in a tiny 1-sample-per-column Sound, then build each
# step envelope with a single nearest-column lookup Formula (avoids rebuilding
# the whole envelope buffer once per column).
fVals = Create Sound from formula: "fVals_" + uid$, 1, 0, analysis_columns, 1, "0"
pVals = Create Sound from formula: "pVals_" + uid$, 1, 0, analysis_columns, 1, "0"

for aCol to analysis_columns
    selectObject: fVals
    Set value at sample number: 1, aCol, freq[aCol]
    selectObject: pVals
    Set value at sample number: 1, aCol, pan[aCol]
endfor

fValsName$ = "Sound_fVals_" + uid$
pValsName$ = "Sound_pVals_" + uid$

freqEnv = Create Sound from formula: "freqEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, fValsName$ + "[min(analysis_columns, floor(x / chunkDuration) + 1)]"
panEnv = Create Sound from formula: "panEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, pValsName$ + "[min(analysis_columns, floor(x / chunkDuration) + 1)]"

removeObject: fVals, pVals

# === Smooth the Frequency Envelope (prevents clicks) ===
appendInfoLine: "Smoothing frequency transitions..."

smoothHz = analysis_columns / duration_s * 3
selectObject: freqEnv
Filter (pass Hann band): 0, smoothHz, smoothHz / 2
freqEnvSmooth = selected("Sound")
Rename: "freqSmooth_" + uid$

selectObject: panEnv
Filter (pass Hann band): 0, smoothHz, smoothHz / 2
panEnvSmooth = selected("Sound")
Rename: "panSmooth_" + uid$

# === Phase-Continuous Synthesis ===
# To avoid clicks, we integrate frequency to get phase:
# phase(t) = integral of freq(t) dt
# Then: output = sin(2*pi * phase)
#
# In discrete form: phase[n] = phase[n-1] + freq[n] / sampleRate

appendInfoLine: "Synthesizing phase-continuous tone..."

freqEnvName$ = "Sound_freqSmooth_" + uid$
panEnvName$ = "Sound_panSmooth_" + uid$

# True phase-continuous synthesis: integrate the instantaneous frequency to get
# phase, then take its sine. phase[n] = phase[n-1] + freq[n]/sampleRate (a
# cumulative sum), so d(phase)/dt = freq exactly and the phase never jumps.
#
# The naive sin(2*pi*freq*x) is WRONG for a time-varying freq: its instantaneous
# frequency is freq + x*freq', which drifts progressively sharp over the sound.

phaseSound = Create Sound from formula: "phase_" + uid$, 1, 0, duration_s, sample_rate_Hz, freqEnvName$ + "[] / sample_rate_Hz"
selectObject: phaseSound
Formula: "if col > 1 then self + self[col - 1] else self endif"

phaseName$ = "Sound_phase_" + uid$
monoSound = Create Sound from formula: "mono_" + uid$, 1, 0, duration_s, sample_rate_Hz, "sin(twoPi * " + phaseName$ + "[])"

removeObject: phaseSound

# === Create Stereo with Panning ===
appendInfoLine: "Applying stereo panning..."

monoName$ = "Sound_mono_" + uid$

leftCh = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "sqrt(max(0, 1 - " + panEnvName$ + "[])) * " + monoName$ + "[]"

rightCh = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "sqrt(max(0, " + panEnvName$ + "[])) * " + monoName$ + "[]"

selectObject: leftCh
plusObject: rightCh
outputSound = Combine to stereo
Rename: "pitch_sonification_" + photoName$

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Cleanup ===
removeObject: redID, greenID, blueID
removeObject: freqEnv, panEnv, freqEnvSmooth, panEnvSmooth
removeObject: monoSound, leftCh, rightCh

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Photo Pitch Sonification — " + photoName$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "Brightness -> Pitch (" + string$(min_pitch_Hz) + "-" + string$(max_pitch_Hz) + " Hz)"
    
    # === Brightness & Frequency Profile ===
    Select outer viewport: 0, 7, 0.8, 2.5
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 0.9, 2.4
    Axes: 0, analysis_columns, 0, 1
    
    Line width: 1
    
    # Brightness curve
    Colour: "{0.3, 0.3, 0.3}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, brightness[.c - 1], .c, brightness[.c]
    endfor
    
    # Pan curve
    Colour: "{0.8, 0.3, 0.3}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, pan[.c - 1], .c, pan[.c]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Value"
    Text bottom: "yes", "Column (black=brightness, red=pan)"
    
    # === Frequency Profile ===
    Select outer viewport: 0, 7, 2.6, 3.8
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 2.7, 3.7
    Axes: 0, analysis_columns, min_pitch_Hz - 50, max_pitch_Hz + 50
    
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    for .c from 2 to analysis_columns
        Draw line: .c - 1, freq[.c - 1], .c, freq[.c]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Column"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 4.0, 6.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 4.1, 5.9
    
    selectObject: outputSound
    Extract one channel: 1
    .monoSpec = selected("Sound")
    
    selectObject: .monoSpec
    .maxFreq = max_pitch_Hz * 2
    To Spectrogram: 0.02, .maxFreq, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 4.1, 5.9
    Axes: 0, duration_s, 0, .maxFreq
    
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc