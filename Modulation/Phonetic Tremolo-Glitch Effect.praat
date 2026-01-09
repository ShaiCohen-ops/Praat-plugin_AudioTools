# ============================================================
# Praat AudioTools - Phonetic_Tremolo_Glitch_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phonetic Tremolo/Glitch Effect - classifies audio frames
#   by phonetic type (vowel, fricative, silence) using acoustic
#   features and applies different effects to each class.
#   Vowels get tremolo, fricatives get time-shift glitch,
#   silence gets gated.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed Formula (part) variable interpolation
#   - Fixed time-shift syntax
#   - Removed unnecessary rename
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling_rate = Get sampling frequency

# === Form ===
form Phonetic Tremolo/Glitch Effect
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Vocal Texture
        option Hard Robot Glitch
        option Broken Radio (High Speed)
        option Fricative Smear (Long Shift)
        option Stutter Vowels
        option Clean Gated (Silence Removal)
    
    comment === Effect Parameters ===
    positive Tremolo_rate_hz 8.0
    positive Tremolo_depth 0.7
    positive Shift_amount_seconds 0.015
    
    comment === Feature Extraction ===
    positive Frame_step_seconds 0.01
    positive Max_formant_hz 5500
    
    comment === Classification Thresholds ===
    positive Vowel_hnr_threshold 5.0
    positive Vowel_f1_min_hz 300
    positive Fricative_hnr_max 3.0
    positive Silence_intensity_threshold 45
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Vocal Texture
    tremolo_rate_hz = 4.0
    tremolo_depth = 0.3
    shift_amount_seconds = 0.005
    silence_intensity_threshold = 40
    presetName$ = "Subtle"
elsif preset = 3
    # Hard Robot Glitch
    tremolo_rate_hz = 12.0
    tremolo_depth = 0.9
    shift_amount_seconds = 0.03
    silence_intensity_threshold = 50
    presetName$ = "Robot"
elsif preset = 4
    # Broken Radio
    tremolo_rate_hz = 25.0
    tremolo_depth = 0.8
    shift_amount_seconds = 0.01
    silence_intensity_threshold = 45
    presetName$ = "Radio"
elsif preset = 5
    # Fricative Smear
    tremolo_rate_hz = 6.0
    tremolo_depth = 0.2
    shift_amount_seconds = 0.08
    fricative_hnr_max = 5.0
    presetName$ = "Smear"
elsif preset = 6
    # Stutter Vowels
    tremolo_rate_hz = 15.0
    tremolo_depth = 1.0
    shift_amount_seconds = 0.0
    presetName$ = "Stutter"
elsif preset = 7
    # Clean Gated
    tremolo_rate_hz = 0.0
    tremolo_depth = 0.0
    shift_amount_seconds = 0.0
    silence_intensity_threshold = 60
    presetName$ = "Gated"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Phonetic Tremolo/Glitch Effect ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Tremolo rate: ", tremolo_rate_hz, " Hz"
appendInfoLine: "Tremolo depth: ", tremolo_depth
appendInfoLine: "Shift amount: ", shift_amount_seconds * 1000, " ms"
appendInfoLine: ""
appendInfoLine: "Thresholds:"
appendInfoLine: "  Vowel HNR > ", vowel_hnr_threshold
appendInfoLine: "  Vowel F1 > ", vowel_f1_min_hz, " Hz"
appendInfoLine: "  Fricative HNR < ", fricative_hnr_max
appendInfoLine: "  Silence intensity < ", silence_intensity_threshold, " dB"
appendInfoLine: ""

# ============================================================
# ANALYSIS PHASE
# ============================================================

appendInfoLine: "Analyzing..."

# 1. Pitch Analysis
selectObject: original
To Pitch: 0, 75, 600
pitch_id = selected("Pitch")

# 2. Intensity Analysis
selectObject: original
To Intensity: 75, 0, "yes"
intensity_id = selected("Intensity")

# 3. Formant Analysis
selectObject: original
To Formant (burg): 0, 5, max_formant_hz, 0.025, 50
formant_id = selected("Formant")

# 4. Harmonicity (HNR) Analysis
selectObject: original
To Harmonicity (cc): 0.01, 75, 0.1, 1.0
hnr_id = selected("Harmonicity")

# Prepare Output Object
selectObject: original
Copy: original_name$ + "_glitch"
output_id = selected("Sound")

# Store classification for visualization
numFrames = floor(duration / frame_step_seconds)
maxVizFrames = min(numFrames, 500)
vizClass# = zero#(maxVizFrames)
vizTimes# = zero#(maxVizFrames)

# Counters
vowelCount = 0
fricativeCount = 0
silenceCount = 0
otherCount = 0

# ============================================================
# PROCESSING LOOP
# ============================================================

appendInfoLine: "Processing ", numFrames, " frames..."

for i from 1 to numFrames
    t_start = (i - 1) * frame_step_seconds
    t_end = i * frame_step_seconds
    t_mid = t_start + frame_step_seconds / 2
    
    # Ensure we don't go past end
    if t_end > duration
        t_end = duration
    endif
    
    # Get features at current time
    selectObject: pitch_id
    f0_val = Get value at time: t_mid, "Hertz", "Linear"
    if f0_val = undefined
        f0_val = 0
    endif
    
    selectObject: intensity_id
    int_val = Get value at time: t_mid, "cubic"
    if int_val = undefined
        int_val = 0
    endif
    
    selectObject: formant_id
    f1_val = Get value at time: 1, t_mid, "Hertz", "Linear"
    if f1_val = undefined
        f1_val = 0
    endif
    
    selectObject: hnr_id
    hnr_val = Get value at time: t_mid, "cubic"
    if hnr_val = undefined
        hnr_val = -100
    endif

    # Classify and apply effect
    selectObject: output_id
    
    # --- CLASS 1: VOWEL (Voiced, High HNR) ---
    if int_val > silence_intensity_threshold and hnr_val > vowel_hnr_threshold and f0_val > 0 and f1_val > vowel_f1_min_hz
        # Apply Tremolo
        trem_phase = (t_mid * tremolo_rate_hz) * 2 * pi
        tremFactor = 1.0 - tremolo_depth * (0.5 * (1.0 + sin(trem_phase)))
        Formula (part): t_start, t_end, 1, 1, ~ self * tremFactor
        classNum = 1
        vowelCount = vowelCount + 1
        
    # --- CLASS 2: FRICATIVE (Unvoiced, Low HNR) ---
    elsif int_val > silence_intensity_threshold and hnr_val < fricative_hnr_max and f0_val = 0
        # Apply Glitch / Time Shift
        Formula (part): t_start, t_end, 1, 1, ~ self(x + shift_amount_seconds) * 1.5
        classNum = 2
        fricativeCount = fricativeCount + 1
        
    # --- CLASS 3: SILENCE ---
    elsif int_val < silence_intensity_threshold
        # Gate / Attenuate
        Formula (part): t_start, t_end, 1, 1, ~ self * 0.05
        classNum = 3
        silenceCount = silenceCount + 1
        
    # --- CLASS 4: OTHER ---
    else
        # Slight boost
        Formula (part): t_start, t_end, 1, 1, ~ self * 1.1
        classNum = 4
        otherCount = otherCount + 1
    endif
    
    # Store for visualization
    vizIdx = floor((i - 1) / numFrames * maxVizFrames) + 1
    if vizIdx >= 1 and vizIdx <= maxVizFrames
        vizClass#[vizIdx] = classNum
        vizTimes#[vizIdx] = t_mid
    endif
endfor

# ============================================================
# CLEANUP ANALYSIS OBJECTS
# ============================================================

removeObject: pitch_id, intensity_id, formant_id, hnr_id

# Scale output
selectObject: output_id
Scale peak: scale_peak
Rename: original_name$ + "_phonetic_" + presetName$
result = selected("Sound")

# === Stats ===
appendInfoLine: ""
appendInfoLine: "Classification results:"
appendInfoLine: "  Vowels: ", vowelCount, " frames (", fixed$(vowelCount / numFrames * 100, 1), "%)"
appendInfoLine: "  Fricatives: ", fricativeCount, " frames (", fixed$(fricativeCount / numFrames * 100, 1), "%)"
appendInfoLine: "  Silence: ", silenceCount, " frames (", fixed$(silenceCount / numFrames * 100, 1), "%)"
appendInfoLine: "  Other: ", otherCount, " frames (", fixed$(otherCount / numFrames * 100, 1), "%)"

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phonetic Tremolo/Glitch: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Processed"
    Text bottom: "yes", "Time (s)"
    
    # Classification timeline
    Select outer viewport: 0, 8, 2.7, 3.7
    Select inner viewport: 0.6, 7.6, 2.8, 3.6
    
    Axes: 0, duration, 0, 5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 5
    
    # Draw class regions
    for v from 1 to maxVizFrames
        if vizTimes#[v] > 0
            classVal = vizClass#[v]
            tPos = vizTimes#[v]
            frameWidth = duration / maxVizFrames
            
            if classVal = 1
                # Vowel - red
                Paint rectangle: "{0.8, 0.5, 0.5}", tPos - frameWidth/2, tPos + frameWidth/2, 0, 4
            elsif classVal = 2
                # Fricative - blue
                Paint rectangle: "{0.5, 0.5, 0.8}", tPos - frameWidth/2, tPos + frameWidth/2, 0, 4
            elsif classVal = 3
                # Silence - gray
                Paint rectangle: "{0.7, 0.7, 0.7}", tPos - frameWidth/2, tPos + frameWidth/2, 0, 4
            else
                # Other - green
                Paint rectangle: "{0.5, 0.8, 0.5}", tPos - frameWidth/2, tPos + frameWidth/2, 0, 4
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Class"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 3.9, 4.5
    Select inner viewport: 0.6, 7.6, 4.0, 4.4
    
    Axes: 0, 8, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 8, 0, 1
    
    # Vowel
    Paint rectangle: "{0.8, 0.5, 0.5}", 0.2, 0.6, 0.3, 0.7
    Font size: 6
    Colour: "Black"
    Text: 0.8, "left", 0.5, "half", "Vowel (tremolo)"
    
    # Fricative
    Paint rectangle: "{0.5, 0.5, 0.8}", 2.2, 2.6, 0.3, 0.7
    Text: 2.8, "left", 0.5, "half", "Fricative (glitch)"
    
    # Silence
    Paint rectangle: "{0.7, 0.7, 0.7}", 4.2, 4.6, 0.3, 0.7
    Text: 4.8, "left", 0.5, "half", "Silence (gate)"
    
    # Other
    Paint rectangle: "{0.5, 0.8, 0.5}", 6.2, 6.6, 0.3, 0.7
    Text: 6.8, "left", 0.5, "half", "Other"
    
    Colour: "Black"
    Draw inner box
    
    # Stats pie chart approximation (bar chart)
    Select outer viewport: 0, 8, 4.7, 5.5
    Select inner viewport: 0.6, 7.6, 4.8, 5.4
    
    Axes: 0, 4, 0, 100
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 100
    
    vowelPct = vowelCount / numFrames * 100
    fricPct = fricativeCount / numFrames * 100
    silPct = silenceCount / numFrames * 100
    otherPct = otherCount / numFrames * 100
    
    Paint rectangle: "{0.8, 0.5, 0.5}", 0.2, 0.8, 0, vowelPct
    Paint rectangle: "{0.5, 0.5, 0.8}", 1.2, 1.8, 0, fricPct
    Paint rectangle: "{0.7, 0.7, 0.7}", 2.2, 2.8, 0, silPct
    Paint rectangle: "{0.5, 0.8, 0.5}", 3.2, 3.8, 0, otherPct
    
    Font size: 5
    Text: 0.5, "centre", vowelPct + 5, "half", fixed$(vowelPct, 0) + "%"
    Text: 1.5, "centre", fricPct + 5, "half", fixed$(fricPct, 0) + "%"
    Text: 2.5, "centre", silPct + 5, "half", fixed$(silPct, 0) + "%"
    Text: 3.5, "centre", otherPct + 5, "half", fixed$(otherPct, 0) + "%"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "% Frames"
    
    # Parameters
    Select outer viewport: 0, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Tremolo: " + fixed$(tremolo_rate_hz, 1) + " Hz @ " + fixed$(tremolo_depth * 100, 0) + "% | Shift: " + fixed$(shift_amount_seconds * 1000, 1) + " ms | Silence < " + fixed$(silence_intensity_threshold, 0) + " dB"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result