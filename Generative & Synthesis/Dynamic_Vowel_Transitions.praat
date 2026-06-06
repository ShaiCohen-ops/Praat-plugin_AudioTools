# ============================================================
# Praat AudioTools - Dynamic Vowel Transitions.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant synthesis with smooth vowel morphing.
#   Uses phase-continuous frequency modulation for artifact-free
#   formant transitions.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit 
#   for Experimental Composition.
#
# Changelog v0.2:
#   - Fixed phase-continuous formant synthesis, filters, added visualization
#
# Changelog v0.3:
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black
#     marks). Kept the F1/F2/F3 formant-trajectory overlay on the spectrogram.
#   - Replaced non-ASCII characters (em-dash in the plot title, en-dash).
# ============================================================

form Dynamic Vowel Transitions
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option A to I
        option I to U
        option U to A
        option A to E to I
        option Vowel Cycle
        option Formant Glissando
        option Whisper Morph
        option Singing Vowels
        option Robot Speech
        option Alien Vowels
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    positive Fundamental_Hz 120
    
    comment === Start Vowel Formants (Hz) ===
    positive Start_F1 730
    positive Start_F2 1090
    positive Start_F3 2440
    
    comment === End Vowel Formants (Hz) ===
    positive End_F1 270
    positive End_F2 2290
    positive End_F3 3010
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Voice
        option Rotating Formants
        option Wide Transition
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Standard Vowel Formants (Hz) ===
# Based on Peterson & Barney (1952) male averages
# /a/ (father): F1=730, F2=1090, F3=2440
# /i/ (beet):   F1=270, F2=2290, F3=3010
# /u/ (boot):   F1=300, F2=870,  F3=2240
# /e/ (bet):    F1=530, F2=1840, F3=2480
# /o/ (boat):   F1=570, F2=840,  F3=2410

# === Apply Presets ===
preset_name$ = "Custom"
multiVowel = 0

if preset = 2
    # A to I
    start_F1 = 730
    start_F2 = 1090
    start_F3 = 2440
    end_F1 = 270
    end_F2 = 2290
    end_F3 = 3010
    preset_name$ = "A_to_I"
    
elsif preset = 3
    # I to U
    start_F1 = 270
    start_F2 = 2290
    start_F3 = 3010
    end_F1 = 300
    end_F2 = 870
    end_F3 = 2240
    preset_name$ = "I_to_U"
    
elsif preset = 4
    # U to A
    start_F1 = 300
    start_F2 = 870
    start_F3 = 2240
    end_F1 = 730
    end_F2 = 1090
    end_F3 = 2440
    preset_name$ = "U_to_A"
    
elsif preset = 5
    # A to E to I (multi-vowel)
    multiVowel = 1
    numVowels = 3
    vowelF1[1] = 730
    vowelF2[1] = 1090
    vowelF3[1] = 2440
    vowelF1[2] = 530
    vowelF2[2] = 1840
    vowelF3[2] = 2480
    vowelF1[3] = 270
    vowelF2[3] = 2290
    vowelF3[3] = 3010
    preset_name$ = "A_E_I"
    
elsif preset = 6
    # Vowel Cycle (A-I-U-A)
    multiVowel = 1
    numVowels = 4
    vowelF1[1] = 730
    vowelF2[1] = 1090
    vowelF3[1] = 2440
    vowelF1[2] = 270
    vowelF2[2] = 2290
    vowelF3[2] = 3010
    vowelF1[3] = 300
    vowelF2[3] = 870
    vowelF3[3] = 2240
    vowelF1[4] = 730
    vowelF2[4] = 1090
    vowelF3[4] = 2440
    preset_name$ = "VowelCycle"
    
elsif preset = 7
    # Formant Glissando (extreme)
    start_F1 = 200
    start_F2 = 600
    start_F3 = 1800
    end_F1 = 900
    end_F2 = 2800
    end_F3 = 4000
    preset_name$ = "FormantGlissando"
    
elsif preset = 8
    # Whisper Morph
    start_F1 = 600
    start_F2 = 1200
    start_F3 = 2400
    end_F1 = 400
    end_F2 = 1800
    end_F3 = 2800
    fundamental_Hz = 0
    preset_name$ = "WhisperMorph"
    
elsif preset = 9
    # Singing Vowels
    duration_s = 5.0
    fundamental_Hz = 220
    start_F1 = 550
    start_F2 = 1100
    start_F3 = 2350
    end_F1 = 350
    end_F2 = 2000
    end_F3 = 3000
    preset_name$ = "SingingVowels"
    
elsif preset = 10
    # Robot Speech
    start_F1 = 400
    start_F2 = 1200
    start_F3 = 2400
    end_F1 = 500
    end_F2 = 1500
    end_F3 = 2600
    preset_name$ = "RobotSpeech"
    
elsif preset = 11
    # Alien Vowels
    start_F1 = 150
    start_F2 = 3000
    start_F3 = 4500
    end_F1 = 800
    end_F2 = 1200
    end_F3 = 3500
    preset_name$ = "AlienVowels"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
controlRate = 1000

# === Info ===
writeInfoLine: "=== Dynamic Vowel Transitions ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Fundamental: ", fundamental_Hz, " Hz"
if multiVowel = 0
    appendInfoLine: "Start: F1=", start_F1, " F2=", start_F2, " F3=", start_F3
    appendInfoLine: "End:   F1=", end_F1, " F2=", end_F2, " F3=", end_F3
else
    appendInfoLine: "Multi-vowel sequence (", numVowels, " vowels)"
endif
appendInfoLine: ""

# === Create formant trajectory at control rate ===
appendInfoLine: "Computing formant trajectories..."

f1Ctrl = Create Sound from formula: "f1_" + uid$, 1, 0, duration_s, controlRate, "0"
f2Ctrl = Create Sound from formula: "f2_" + uid$, 1, 0, duration_s, controlRate, "0"
f3Ctrl = Create Sound from formula: "f3_" + uid$, 1, 0, duration_s, controlRate, "0"

nCtrl = round(duration_s * controlRate)

for cp to nCtrl
    t = (cp - 1) / controlRate
    normalizedTime = t / duration_s
    
    if multiVowel = 1
        # Interpolate between multiple vowels
        segmentDur = 1 / (numVowels - 1)
        segment = floor(normalizedTime / segmentDur) + 1
        if segment >= numVowels
            segment = numVowels - 1
        endif
        localT = (normalizedTime - (segment - 1) * segmentDur) / segmentDur
        
        # Smooth interpolation (cosine)
        smoothT = 0.5 * (1 - cos(pi * localT))
        
        f1 = vowelF1[segment] + (vowelF1[segment + 1] - vowelF1[segment]) * smoothT
        f2 = vowelF2[segment] + (vowelF2[segment + 1] - vowelF2[segment]) * smoothT
        f3 = vowelF3[segment] + (vowelF3[segment + 1] - vowelF3[segment]) * smoothT
    else
        # Linear interpolation between start and end
        # With smooth onset/offset (raised cosine)
        smoothT = 0.5 * (1 - cos(pi * normalizedTime))
        
        f1 = start_F1 + (end_F1 - start_F1) * smoothT
        f2 = start_F2 + (end_F2 - start_F2) * smoothT
        f3 = start_F3 + (end_F3 - start_F3) * smoothT
    endif
    
    selectObject: f1Ctrl
    Set value at sample number: 1, cp, f1
    selectObject: f2Ctrl
    Set value at sample number: 1, cp, f2
    selectObject: f3Ctrl
    Set value at sample number: 1, cp, f3
endfor

# === Compute phase trajectories (integral of frequency) ===
appendInfoLine: "Computing phase trajectories..."

phase1Ctrl = Create Sound from formula: "phase1_" + uid$, 1, 0, duration_s, controlRate, "0"
phase2Ctrl = Create Sound from formula: "phase2_" + uid$, 1, 0, duration_s, controlRate, "0"
phase3Ctrl = Create Sound from formula: "phase3_" + uid$, 1, 0, duration_s, controlRate, "0"
phase0Ctrl = Create Sound from formula: "phase0_" + uid$, 1, 0, duration_s, controlRate, "0"

timeStep = 1 / controlRate
phase0 = 0
phase1 = 0
phase2 = 0
phase3 = 0

for cp to nCtrl
    selectObject: f1Ctrl
    f1 = Get value at sample number: 1, cp
    selectObject: f2Ctrl
    f2 = Get value at sample number: 1, cp
    selectObject: f3Ctrl
    f3 = Get value at sample number: 1, cp
    
    # Accumulate phase (integral of frequency)
    phase0 = phase0 + twoPi * fundamental_Hz * timeStep
    phase1 = phase1 + twoPi * f1 * timeStep
    phase2 = phase2 + twoPi * f2 * timeStep
    phase3 = phase3 + twoPi * f3 * timeStep
    
    selectObject: phase0Ctrl
    Set value at sample number: 1, cp, phase0
    selectObject: phase1Ctrl
    Set value at sample number: 1, cp, phase1
    selectObject: phase2Ctrl
    Set value at sample number: 1, cp, phase2
    selectObject: phase3Ctrl
    Set value at sample number: 1, cp, phase3
endfor

# === Resample to audio rate ===
appendInfoLine: "Resampling to audio rate..."

selectObject: phase0Ctrl
phase0Audio = Resample: sample_rate_Hz, 50
phase0Name$ = "phase0_audio_" + uid$
Rename: phase0Name$

selectObject: phase1Ctrl
phase1Audio = Resample: sample_rate_Hz, 50
phase1Name$ = "phase1_audio_" + uid$
Rename: phase1Name$

selectObject: phase2Ctrl
phase2Audio = Resample: sample_rate_Hz, 50
phase2Name$ = "phase2_audio_" + uid$
Rename: phase2Name$

selectObject: phase3Ctrl
phase3Audio = Resample: sample_rate_Hz, 50
phase3Name$ = "phase3_audio_" + uid$
Rename: phase3Name$

# Cleanup control-rate objects
removeObject: f1Ctrl, f2Ctrl, f3Ctrl
removeObject: phase0Ctrl, phase1Ctrl, phase2Ctrl, phase3Ctrl

# === Synthesize formant sound ===
appendInfoLine: "Synthesizing vowel transitions..."

if fundamental_Hz > 0
    # Voiced: pulse train excitation filtered by formants
    # Simplified: additive synthesis with formants
    outputSound = Create Sound from formula: "vowel_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.4 * sin(Sound_'phase0Name$'[]) + 0.6 * sin(Sound_'phase1Name$'[]) * 0.5 + 0.5 * sin(Sound_'phase2Name$'[]) * 0.3 + 0.3 * sin(Sound_'phase3Name$'[]) * 0.2"
else
    # Whispered: noise filtered by formants
    noiseSound = Create Sound from formula: "noise_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "randomGauss(0, 0.3)"
    
    outputSound = Create Sound from formula: "vowel_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "Sound_noise_'uid$'[] * (0.4 + 0.3 * sin(Sound_'phase1Name$'[]) + 0.2 * sin(Sound_'phase2Name$'[]) + 0.1 * sin(Sound_'phase3Name$'[]))"
    
    removeObject: noiseSound
endif

# Cleanup phase audio
removeObject: phase0Audio, phase1Audio, phase2Audio, phase3Audio

# === Apply envelope ===
selectObject: outputSound
Formula: "self * (0.8 + 0.2 * sin(twoPi * 0.3 * x))"

# Fade in/out
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Voice - formants spread L/R
    appendInfoLine: "Creating stereo voice..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 2000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 150, 4000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "vowel_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating Formants
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * 0.15 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * 0.15 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "vowel_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 4
    # Wide Transition
    appendInfoLine: "Creating wide stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 1500, 120
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 200, 5000, 120
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "vowel_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "vowel_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

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

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dynamic Vowel Transitions: " + preset_name$

    # --- Mono display copy ---
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
    endif

    # --- Panel 1: Waveform ---
    Select outer viewport: 0, 8, 0.9, 2.2
    Select inner viewport: 0.75, 7.6, 1.05, 2.1
    selectObject: .disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text left: "yes", "Output"

    # --- Panel 2: Spectrogram with formant-trajectory overlay ---
    Select outer viewport: 0, 8, 2.4, 4.8
    Select inner viewport: 0.75, 7.6, 2.55, 4.7
    selectObject: .disp
    .maxFreqSpec = 5000
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec
    removeObject: .disp

    Select inner viewport: 0.75, 7.6, 2.55, 4.7
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # Formant trajectory lines (single-vowel morph)
    if multiVowel = 0
        Line width: 2
        Colour: "{1.00, 0.30, 0.30}"
        Draw line: 0, start_F1, duration_s, end_F1
        Colour: "{0.30, 1.00, 0.30}"
        Draw line: 0, start_F2, duration_s, end_F2
        Colour: "{0.30, 0.30, 1.00}"
        Draw line: 0, start_F3, duration_s, end_F3
        Line width: 1
        Colour: "Black"
    endif

    # --- Summary panel (grey) ---
    if spatial_mode = 2
        .spatial$ = "Stereo Voice"
    elsif spatial_mode = 3
        .spatial$ = "Rotating Formants"
    elsif spatial_mode = 4
        .spatial$ = "Wide Transition"
    else
        .spatial$ = "Mono"
    endif
    if multiVowel = 0
        .info$ = "Start: " + fixed$(start_F1, 0) + "/" + fixed$(start_F2, 0) + "/" + fixed$(start_F3, 0) + " -> End: " + fixed$(end_F1, 0) + "/" + fixed$(end_F2, 0) + "/" + fixed$(end_F3, 0)
    else
        .info$ = "Multi-vowel sequence (" + string$(numVowels) + " vowels)"
    endif
    Select outer viewport: 0, 8, 4.9, 5.3
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "F0: " + fixed$(fundamental_Hz, 0) + " Hz | " + .info$ + " | " + .spatial$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
