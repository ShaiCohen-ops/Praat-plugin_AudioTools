# ============================================================
# Praat AudioTools - Individual Formant Stretcher v2.0
# Spectral-envelope landmark edition
#
# FormantPath is used only to estimate robust spectral landmarks.
# No LPC inverse filtering. No FormantGrid resynthesis.
# Static envelope remapping uses one complex FFT per channel;
# original spectral phase is preserved.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Individual Formant Stretcher v2.0
    optionmenu Preset: 1
        option Custom
        option Natural (no change)
        option Compress Vowel Space
        option Expand Vowel Space
        option Brighten Spectrum
        option Darken Spectrum
        option Male to Female
        option Female to Male
        option Robot Voice (harmonic)
        option Alien Creature
        option Demon Voice
        option Chipmunk Extreme
        option Giant Extreme
        option Spectral Inversion
        option Harmonic Series
        option Chaos Mode
    comment === Individual landmark control (semitones) ===
    real F1_transpose_semitones 0.0
    real F2_transpose_semitones 0.0
    real F3_transpose_semitones 0.0
    real F4_transpose_semitones 0.0
    real F5_transpose_semitones 0.0
    real Global_transpose_semitones 0.0
    comment === Envelope shape ===
    positive Bandwidth_scale 1.0
    positive strength_db 18
    comment === Analysis ===
    positive Max_formant_hz 5500
    optionmenu Analysis_source: 2
        option Channel 1
        option Loudest channel
        option Mono sum (may cancel anti-phase)
    boolean Require_formant_confidence 1
    comment === Output ===
    real Dry_wet_mix 1.0
    optionmenu Output_level_mode: 1
        option Natural level
        option Safety ceiling
        option Peak normalize
    positive Ceiling_peak 0.95
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ------------------------------------------------------------
# Presets - retain the musical maps from v1.1
# ------------------------------------------------------------
if preset = 2
    f1_transpose_semitones = 0
    f2_transpose_semitones = 0
    f3_transpose_semitones = 0
    f4_transpose_semitones = 0
    f5_transpose_semitones = 0
    global_transpose_semitones = 0
    strength_db = 18
    presetName$ = "Natural"
elsif preset = 3
    f1_transpose_semitones = 3
    f2_transpose_semitones = 2
    f3_transpose_semitones = 0
    f4_transpose_semitones = -2
    f5_transpose_semitones = -3
    strength_db = 14
    presetName$ = "Compress"
elsif preset = 4
    f1_transpose_semitones = -3
    f2_transpose_semitones = -2
    f3_transpose_semitones = 0
    f4_transpose_semitones = 2
    f5_transpose_semitones = 3
    strength_db = 14
    presetName$ = "Expand"
elsif preset = 5
    f1_transpose_semitones = 0
    f2_transpose_semitones = 4
    f3_transpose_semitones = 6
    f4_transpose_semitones = 7
    f5_transpose_semitones = 8
    bandwidth_scale = 0.7
    strength_db = 18
    presetName$ = "Brighten"
elsif preset = 6
    f1_transpose_semitones = 0
    f2_transpose_semitones = -4
    f3_transpose_semitones = -6
    f4_transpose_semitones = -7
    f5_transpose_semitones = -8
    bandwidth_scale = 1.4
    strength_db = 18
    presetName$ = "Darken"
elsif preset = 7
    f1_transpose_semitones = -1
    f2_transpose_semitones = 2
    f3_transpose_semitones = 3
    f4_transpose_semitones = 3
    f5_transpose_semitones = 2
    global_transpose_semitones = 2
    bandwidth_scale = 0.85
    strength_db = 16
    presetName$ = "MaleToFemale"
elsif preset = 8
    f1_transpose_semitones = 1
    f2_transpose_semitones = -2
    f3_transpose_semitones = -3
    f4_transpose_semitones = -3
    f5_transpose_semitones = -2
    global_transpose_semitones = -2
    bandwidth_scale = 1.15
    strength_db = 16
    presetName$ = "FemaleToMale"
elsif preset = 9
    f1_transpose_semitones = 0
    f2_transpose_semitones = 12
    f3_transpose_semitones = 19
    f4_transpose_semitones = 24
    f5_transpose_semitones = 28
    bandwidth_scale = 0.5
    strength_db = 24
    presetName$ = "Robot"
elsif preset = 10
    f1_transpose_semitones = 8
    f2_transpose_semitones = -5
    f3_transpose_semitones = 12
    f4_transpose_semitones = -8
    f5_transpose_semitones = 15
    bandwidth_scale = 1.5
    strength_db = 22
    presetName$ = "Alien"
elsif preset = 11
    f1_transpose_semitones = -7
    f2_transpose_semitones = -12
    f3_transpose_semitones = -8
    f4_transpose_semitones = -15
    f5_transpose_semitones = -10
    global_transpose_semitones = -5
    bandwidth_scale = 2.0
    strength_db = 24
    presetName$ = "Demon"
elsif preset = 12
    f1_transpose_semitones = 5
    f2_transpose_semitones = 8
    f3_transpose_semitones = 10
    f4_transpose_semitones = 12
    f5_transpose_semitones = 12
    global_transpose_semitones = 7
    bandwidth_scale = 0.6
    strength_db = 22
    presetName$ = "ChipmunkExtreme"
elsif preset = 13
    f1_transpose_semitones = -8
    f2_transpose_semitones = -12
    f3_transpose_semitones = -10
    f4_transpose_semitones = -14
    f5_transpose_semitones = -12
    global_transpose_semitones = -8
    bandwidth_scale = 2.5
    strength_db = 24
    presetName$ = "GiantExtreme"
elsif preset = 14
    f1_transpose_semitones = 12
    f2_transpose_semitones = 5
    f3_transpose_semitones = 0
    f4_transpose_semitones = -5
    f5_transpose_semitones = -12
    bandwidth_scale = 1.0
    strength_db = 20
    presetName$ = "Inversion"
elsif preset = 15
    f1_transpose_semitones = 0
    f2_transpose_semitones = 12
    f3_transpose_semitones = 19
    f4_transpose_semitones = 24
    f5_transpose_semitones = 28
    bandwidth_scale = 0.4
    strength_db = 24
    presetName$ = "Harmonic"
elsif preset = 16
    f1_transpose_semitones = 9
    f2_transpose_semitones = -11
    f3_transpose_semitones = 14
    f4_transpose_semitones = -6
    f5_transpose_semitones = 17
    bandwidth_scale = 1.8
    strength_db = 24
    presetName$ = "Chaos"
else
    presetName$ = "Custom"
endif

# ------------------------------------------------------------
# Fixed analysis / envelope settings
# ------------------------------------------------------------
time_step_s = 0.005
window_length_s = 0.030
pre_emphasis = 35
max_formants = 5
region_fraction = 0.24
region_floor_1 = 180
region_floor_2 = 260
region_floor_3 = 360
region_floor_4 = 450
region_floor_5 = 550

# ------------------------------------------------------------
# Input and validation
# ------------------------------------------------------------
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2
inputPeak = Get absolute extremum: 0, 0, "None"
inputRMS = Get root-mean-square: 0, 0

if duration < 0.20
    exitScript: "Sound must be at least 200 ms for stable formant landmark analysis."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1."
endif
if bandwidth_scale <= 0 or bandwidth_scale > 4
    exitScript: "Bandwidth_scale must be greater than 0 and at most 4."
endif
if strength_db <= 0 or strength_db > 36
    exitScript: "Strength_dB must be greater than 0 and at most 36."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1."
endif

max_formant_hz = min(max_formant_hz, (nyquist - 50) / 1.22)
if max_formant_hz < 1000
    exitScript: "Sample rate is too low for useful formant analysis."
endif

# Exact bypass: no transformation at all, or zero wet.
neutral = 1
if abs(global_transpose_semitones) > 0.000001 or abs(f1_transpose_semitones) > 0.000001 or abs(f2_transpose_semitones) > 0.000001 or abs(f3_transpose_semitones) > 0.000001 or abs(f4_transpose_semitones) > 0.000001 or abs(f5_transpose_semitones) > 0.000001
    neutral = 0
endif
if dry_wet_mix = 0 or neutral = 1
    selectObject: sound
    finalOutput = Copy: originalName$ + "_FormantStretch_Bypass"
    selectObject: finalOutput
    if play_after_processing
        Play
    endif
    exitScript: ""
endif

clearinfo
writeInfoLine: "=== Individual Formant Stretcher v2.0 ==="
appendInfoLine: "Method: static spectral-envelope landmark remapping; original complex phase preserved."
appendInfoLine: "No LPC inverse filtering and no FormantGrid resynthesis."
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$, " | ", fixed$(duration, 3), " s | ", numChannels, " ch | ", sampleRate, " Hz"
appendInfoLine: "Bandwidth_scale now controls ENVELOPE REGION WIDTH, not LPC pole bandwidth."

# ------------------------------------------------------------
# Work at zero time
# ------------------------------------------------------------
selectObject: sound
workSound = Copy: "ifs_work"
Shift times to: "start time", 0

# Analysis source only. Audio channels are never folded for processing.
if numChannels = 1
    selectObject: workSound
    analysisSound = Copy: "ifs_analysis"
    analysisSource$ = "single channel"
elsif analysis_source = 1
    selectObject: workSound
    analysisSound = Extract one channel: 1
    analysisSource$ = "channel 1"
elsif analysis_source = 3
    selectObject: workSound
    analysisSound = Convert to mono
    analysisSource$ = "mono sum"
else
    bestRms = -1
    pickCh = 1
    for ch from 1 to numChannels
        selectObject: workSound
        probe = Extract one channel: ch
        r = Get root-mean-square: 0, 0
        removeObject: probe
        if r > bestRms
            bestRms = r
            pickCh = ch
        endif
    endfor
    selectObject: workSound
    analysisSound = Extract one channel: pickCh
    analysisSource$ = "loudest channel " + string$(pickCh)
endif

selectObject: analysisSound
analysisRMS = Get root-mean-square: 0, 0
if analysisRMS = undefined or analysisRMS < 0.0000001
    removeObject: analysisSound, workSound
    exitScript: "The selected analysis source is silent."
endif
appendInfoLine: "Analysis source: ", analysisSource$

# ------------------------------------------------------------
# Robust static landmarks
# ------------------------------------------------------------
selectObject: analysisSound
formantPath = To FormantPath (burg): time_step_s, max_formants, max_formant_hz,
    ... window_length_s, pre_emphasis, 0.05, 4
formantObj = Extract Formant

for fn from 1 to max_formants
    selectObject: formantObj
    formant_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.5
endfor

removeObject: formantPath, formantObj, analysisSound

validFormants = 0
firstLandmark = undefined
lastLandmark = undefined
for fn from 1 to max_formants
    if formant_'fn' <> undefined and formant_'fn' > 0
        validFormants = validFormants + 1
        if firstLandmark = undefined
            firstLandmark = formant_'fn'
        endif
        lastLandmark = formant_'fn'
        appendInfoLine: "  F", fn, " landmark = ", fixed$(formant_'fn', 1), " Hz"
    endif
endfor

confidenceOK = 1
if validFormants < 2
    confidenceOK = 0
elsif lastLandmark - firstLandmark < 600
    # Narrow spectral-line clusters (e.g. a pure sine) are not a
    # plausible multi-region formant envelope. Do not invent a tract.
    confidenceOK = 0
endif

if require_formant_confidence and confidenceOK = 0
    appendInfoLine: "Formant confidence gate: landmarks are not a broad spectral envelope; bypassing."
    removeObject: workSound
    selectObject: sound
    finalOutput = Copy: originalName$ + "_FormantStretch_LowConfidenceBypass"
    selectObject: finalOutput
    if play_after_processing
        Play
    endif
    exitScript: ""
endif
if validFormants < 1
    removeObject: workSound
    exitScript: "No usable formant landmarks were found."
endif

# ------------------------------------------------------------
# Targets
# ------------------------------------------------------------
globalFactor = 2 ^ (global_transpose_semitones / 12)
factor_1 = globalFactor * 2 ^ (f1_transpose_semitones / 12)
factor_2 = globalFactor * 2 ^ (f2_transpose_semitones / 12)
factor_3 = globalFactor * 2 ^ (f3_transpose_semitones / 12)
factor_4 = globalFactor * 2 ^ (f4_transpose_semitones / 12)
factor_5 = globalFactor * 2 ^ (f5_transpose_semitones / 12)

for fn from 1 to max_formants
    old_'fn' = formant_'fn'
    target_'fn' = formant_'fn'
    active_'fn' = 0
    if formant_'fn' <> undefined and formant_'fn' > 0
        target_'fn' = formant_'fn' * factor_'fn'
        if target_'fn' < 80
            target_'fn' = 80
        endif
        if target_'fn' > nyquist - 80
            target_'fn' = nyquist - 80
        endif
        if abs(target_'fn' - old_'fn') > 0.5
            active_'fn' = 1
        endif
    endif
endfor

appendInfoLine: "Targets:"
for fn from 1 to max_formants
    if old_'fn' <> undefined
        appendInfoLine: "  F", fn, ": ", fixed$(old_'fn', 1), " -> ", fixed$(target_'fn', 1), " Hz"
    endif
endfor

# ------------------------------------------------------------
# One static smooth gain curve
# ------------------------------------------------------------
expr$ = ""
terms = 0
for fn from 1 to max_formants
    if active_'fn' = 1
        if fn = 1
            floorW = region_floor_1
        elsif fn = 2
            floorW = region_floor_2
        elsif fn = 3
            floorW = region_floor_3
        elsif fn = 4
            floorW = region_floor_4
        else
            floorW = region_floor_5
        endif
        width = max(floorW, old_'fn' * region_fraction) * bandwidth_scale
        width = max(90, min(1400, width))

        if terms > 0
            expr$ = expr$ + " + "
        endif
        expr$ = expr$ + fixed$(strength_db, 4) + " * (exp(-0.5*((x-" +
            ... fixed$(target_'fn', 3) + ")/" + fixed$(width, 3) + ")^2) - exp(-0.5*((x-" +
            ... fixed$(old_'fn', 3) + ")/" + fixed$(width, 3) + ")^2))"
        terms = terms + 1
    endif
endfor

if terms = 0
    removeObject: workSound
    selectObject: sound
    finalOutput = Copy: originalName$ + "_FormantStretch_Bypass"
    exitScript: ""
endif
shapeLimit$ = fixed$(strength_db, 4)

procedure process_channel: .inputSound
    selectObject: .inputSound
    .dur = Get total duration
    .spec = To Spectrum: "yes"
    selectObject: .spec
    Formula: "self * 10^(min(" + shapeLimit$ + ",max(-" + shapeLimit$ + "," + expr$ + "))/20)"
    .full = To Sound
    removeObject: .spec
    selectObject: .full
    .out = Extract part: 0, .dur, "rectangular", 1, "no"
    removeObject: .full
    selectObject: .out
endproc

# ------------------------------------------------------------
# Process each channel independently with the same envelope map
# ------------------------------------------------------------
for ch from 1 to numChannels
    if numChannels = 1
        selectObject: workSound
        dryCh[ch] = Copy: "ifs_dry"
    else
        selectObject: workSound
        dryCh[ch] = Extract one channel: ch
    endif

    @process_channel: dryCh[ch]
    wetCh[ch] = selected("Sound")

    if dry_wet_mix < 1
        selectObject: wetCh[ch]
        Formula: "self*" + string$(dry_wet_mix) + " + object[" + string$(dryCh[ch]) + ",1,col]*" + string$(1-dry_wet_mix)
    endif
endfor

if numChannels = 1
    selectObject: wetCh[1]
    finalOutput = Copy: "ifs_output"
    removeObject: wetCh[1]
else
    selectObject: wetCh[1]
    outDur = Get total duration
    Create Sound from formula: "ifs_output", numChannels, 0, outDur, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to numChannels
        selectObject: finalOutput
        Formula (part): 0, outDur, ch, ch, "object[" + string$(wetCh[ch]) + ",1,col]"
    endfor
    for ch from 1 to numChannels
        removeObject: wetCh[ch]
    endfor
endif
for ch from 1 to numChannels
    removeObject: dryCh[ch]
endfor

# Output level is explicit; Natural means no hidden scaling.
selectObject: finalOutput
prePeak = Get absolute extremum: 0, 0, "None"
if output_level_mode = 2
    if prePeak > ceiling_peak
        Scale peak: ceiling_peak
    endif
elsif output_level_mode = 3
    if prePeak > 0
        Scale peak: ceiling_peak
    endif
endif
selectObject: finalOutput
outPeak = Get absolute extremum: 0, 0, "None"
outRMS = Get root-mean-square: 0, 0
outChannels = Get number of channels

# ------------------------------------------------------------
# Visualization
# ------------------------------------------------------------
if draw_visualization
    vizMaxSeconds = 8
    vizStart = 0
    vizEnd = duration
    if duration > vizMaxSeconds
        vizStart = (duration - vizMaxSeconds) / 2
        vizEnd = vizStart + vizMaxSeconds
    endif

    selectObject: workSound
    if numChannels > 1
        vizOrigFull = Extract one channel: 1
    else
        vizOrigFull = Copy: "ifs_viz_orig_full"
    endif
    selectObject: finalOutput
    if outChannels > 1
        vizProcFull = Extract one channel: 1
    else
        vizProcFull = Copy: "ifs_viz_proc_full"
    endif

    if duration > vizMaxSeconds
        selectObject: vizOrigFull
        vizOrig = Extract part: vizStart, vizEnd, "rectangular", 1, "no"
        removeObject: vizOrigFull
        selectObject: vizProcFull
        vizProc = Extract part: vizStart, vizEnd, "rectangular", 1, "no"
        removeObject: vizProcFull
    else
        vizOrig = vizOrigFull
        vizProc = vizProcFull
    endif

    selectObject: vizOrig
    p1 = Get absolute extremum: 0, 0, "None"
    selectObject: vizProc
    p2 = Get absolute extremum: 0, 0, "None"
    amp = max(0.001, max(p1,p2) * 1.15)

    drawMax = 3500
    for fn from 1 to max_formants
        if old_'fn' <> undefined
            drawMax = max(drawMax, old_'fn')
            drawMax = max(drawMax, target_'fn')
        endif
    endfor
    drawMax = min(nyquist, drawMax * 1.08)
    specCeil = min(nyquist, max(5000, max_formant_hz))

    Erase all
    Select outer viewport: 0, 8, 0.0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##Individual Formant Stretcher v2.0##"
    Font size: 7
    Colour: "{0.35,0.35,0.5}"
    Text: 0.5, "centre", 0.2, "half", presetName$ + " | spectral-envelope landmarks"

    # Waveforms
    Select outer viewport: 0, 4, 0.65, 1.8
    Select inner viewport: 0.55, 3.75, 0.75, 1.72
    selectObject: vizOrig
    Colour: "{0.55,0.55,0.55}"
    Draw: 0, 0, -amp, amp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original"

    Select outer viewport: 4, 8, 0.65, 1.8
    Select inner viewport: 4.45, 7.7, 0.75, 1.72
    selectObject: vizProc
    Colour: "{0.25,0.65,0.45}"
    Draw: 0, 0, -amp, amp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Processed"

    # Landmark map: old -> target
    Select outer viewport: 0, 8, 1.95, 3.25
    Select inner viewport: 0.65, 7.6, 2.05, 3.15
    Axes: 0, 1, 0, drawMax
    Paint rectangle: "{0.97,0.97,0.97}", 0, 1, 0, drawMax
    for fn from 1 to max_formants
        if old_'fn' <> undefined
            Colour: "{0.55,0.55,0.55}"
            Draw line: 0.15, old_'fn', 0.40, old_'fn'
            Colour: "{0.20,0.55,0.85}"
            Draw line: 0.60, target_'fn', 0.85, target_'fn'
            Colour: "{0.75,0.45,0.20}"
            Draw arrow: 0.40, old_'fn', 0.60, target_'fn'
            Colour: "Black"
            Font size: 6
            Text: 0.10, "right", old_'fn', "half", "F" + string$(fn)
            Text: 0.90, "left", target_'fn', "half", fixed$(target_'fn',0)
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Marks left: 5, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "grey = measured landmark     blue = target"

    # Spectrograms
    Select outer viewport: 0, 4, 3.4, 5.65
    Select inner viewport: 0.55, 3.75, 3.5, 5.55
    selectObject: vizOrig
    s1 = To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, specCeil, 100, "yes", 50, 6, 0, "no"
    removeObject: s1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original spectrogram"
    Text left: "yes", "Hz"

    Select outer viewport: 4, 8, 3.4, 5.65
    Select inner viewport: 4.45, 7.7, 3.5, 5.55
    selectObject: vizProc
    s2 = To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, specCeil, 100, "yes", 50, 6, 0, "no"
    removeObject: s2
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Processed spectrogram"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 5.8, 6.65
    Select inner viewport: 0.6, 7.6, 5.9, 6.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95,0.95,0.95}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.76, "half", "##Summary##"
    Font size: 6
    Colour: "{0.3,0.3,0.3}"
    Text: 0.02, "left", 0.47, "half", "Global " + fixed$(global_transpose_semitones,1) + " st | F1 " + fixed$(f1_transpose_semitones,1) + " | F2 " + fixed$(f2_transpose_semitones,1) + " | F3 " + fixed$(f3_transpose_semitones,1) + " | F4 " + fixed$(f4_transpose_semitones,1) + " | F5 " + fixed$(f5_transpose_semitones,1)
    Text: 0.02, "left", 0.20, "half", "Width x" + fixed$(bandwidth_scale,2) + " | Strength " + fixed$(strength_db,1) + " dB | Mix " + fixed$(dry_wet_mix*100,0) + "% | Peak " + fixed$(inputPeak,3) + " -> " + fixed$(outPeak,3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizOrig, vizProc
endif

# Restore original time domain only after visualization.
selectObject: finalOutput
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_FormantStretch_" + presetName$
finalName$ = selected$("Sound")
removeObject: workSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Peak: ", fixed$(inputPeak,4), " -> ", fixed$(outPeak,4), " | RMS out: ", fixed$(outRMS,5)
appendInfoLine: "Channels preserved: ", numChannels, " -> ", outChannels
if output_level_mode = 1 and outPeak > 1
    appendInfoLine: "WARNING: Natural level peak exceeds 1.0."
endif

selectObject: finalOutput
if play_after_processing
    if outPeak > 1
        playCopy = Copy: "ifs_play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
        selectObject: finalOutput
    else
        Play
    endif
endif

selectObject: finalOutput
