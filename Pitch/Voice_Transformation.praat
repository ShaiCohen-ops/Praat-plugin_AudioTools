# ============================================================
# Praat AudioTools - Voice_Transformation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Voice Transformation - combines pitch shifting, duration
#   stretching, formant shifting, and bandpass filtering.
#   Includes presets for common voice effects like chipmunk,
#   robot, telephone, and radio voice.
#
# Changelog v0.2:
#   - Renamed from "globally change pitch and duration"
#   - Modern syntax throughout
#   - Added visualization
#   - Fixed object cleanup
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
dur = Get total duration
fs = Get sampling frequency

# === Form ===
form Voice Transformation
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Vocal Harmonics
        option Reduce Breathiness
        option Deeper Voice
        option Higher Voice
        option Chipmunk Effect
        option Robot Voice
        option Telephone Effect
        option Radio Voice
    
    comment === Pitch Analysis ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Time_step 0.01
    
    comment === Frequency Range ===
    positive Freq_cutoff_low 120
    positive Freq_cutoff_high 3500
    
    comment === Transformations ===
    real Pitch_shift_semitones 0
    real Formant_shift_ratio 1.0
    real Duration_factor 1.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Vocal harmonics
    pitch_floor = 75
    pitch_ceiling = 500
    freq_cutoff_low = 100
    freq_cutoff_high = 4000
    pitch_shift_semitones = 0
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Vocal"
elsif preset = 3
    # Reduce breathiness
    pitch_floor = 75
    pitch_ceiling = 500
    freq_cutoff_low = 200
    freq_cutoff_high = 3000
    pitch_shift_semitones = 0
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Clean"
elsif preset = 4
    # Deeper voice
    pitch_floor = 50
    pitch_ceiling = 400
    freq_cutoff_low = 80
    freq_cutoff_high = 4000
    pitch_shift_semitones = -4
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Deeper"
elsif preset = 5
    # Higher voice
    pitch_floor = 100
    pitch_ceiling = 800
    freq_cutoff_low = 150
    freq_cutoff_high = 5000
    pitch_shift_semitones = 5
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Higher"
elsif preset = 6
    # Chipmunk effect
    pitch_floor = 150
    pitch_ceiling = 1000
    freq_cutoff_low = 200
    freq_cutoff_high = 8000
    pitch_shift_semitones = 7
    formant_shift_ratio = 1.4
    duration_factor = 0.85
    presetName$ = "Chipmunk"
elsif preset = 7
    # Robot voice
    pitch_floor = 50
    pitch_ceiling = 300
    freq_cutoff_low = 100
    freq_cutoff_high = 2500
    pitch_shift_semitones = -6
    formant_shift_ratio = 0.9
    duration_factor = 1.05
    presetName$ = "Robot"
elsif preset = 8
    # Telephone effect
    pitch_floor = 75
    pitch_ceiling = 500
    freq_cutoff_low = 300
    freq_cutoff_high = 3400
    pitch_shift_semitones = 0
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Telephone"
elsif preset = 9
    # Radio voice
    pitch_floor = 60
    pitch_ceiling = 400
    freq_cutoff_low = 80
    freq_cutoff_high = 8000
    pitch_shift_semitones = -2
    formant_shift_ratio = 0.95
    duration_factor = 0.98
    presetName$ = "Radio"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Voice Transformation ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Pitch shift: ", pitch_shift_semitones, " semitones"
appendInfoLine: "Formant shift: ", formant_shift_ratio, "x"
appendInfoLine: "Duration: ", duration_factor, "x"
appendInfoLine: "Band: ", freq_cutoff_low, "-", freq_cutoff_high, " Hz"
appendInfoLine: ""

# === Create Manipulation Object ===
appendInfoLine: "Creating manipulation object..."

selectObject: original
manipulation = To Manipulation: time_step, pitch_floor, pitch_ceiling

# === Modify Pitch ===
if pitch_shift_semitones <> 0
    appendInfoLine: "Applying pitch shift (", pitch_shift_semitones, " st)..."
    
    selectObject: manipulation
    pitchTier = Extract pitch tier
    
    pitchRatio = 2 ^ (pitch_shift_semitones / 12)
    Formula: ~ self * pitchRatio
    
    selectObject: manipulation, pitchTier
    Replace pitch tier
    
    removeObject: pitchTier
endif

# === Modify Duration ===
if duration_factor <> 1.0
    appendInfoLine: "Applying duration change (", duration_factor, "x)..."
    
    selectObject: manipulation
    durTier = Extract duration tier
    
    selectObject: durTier
    Add point: 0, duration_factor
    
    selectObject: manipulation, durTier
    Replace duration tier
    
    removeObject: durTier
endif

# === Resynthesize ===
appendInfoLine: "Resynthesizing..."

selectObject: manipulation
resynthSound = Get resynthesis (overlap-add)

# === Apply Formant Shift ===
if formant_shift_ratio <> 1.0
    appendInfoLine: "Applying formant shift (", formant_shift_ratio, "x)..."
    
    selectObject: resynthSound
    formantShifted = Change gender: pitch_floor, pitch_ceiling, formant_shift_ratio, 0, 0, 1.0
    
    removeObject: resynthSound
    resynthSound = formantShifted
endif

# === Apply Frequency Filtering ===
appendInfoLine: "Applying bandpass filter..."

selectObject: resynthSound
filtered = Filter (pass Hann band): freq_cutoff_low, freq_cutoff_high, 100

removeObject: resynthSound
result = filtered

# === Finalize ===
selectObject: result
Rename: origName$ + "_" + presetName$
Scale intensity: 70
Scale peak: 0.95

newDur = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Voice Transformation: " + origName$ + " → " + presetName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Transformed"
    Text bottom: "yes", "Time (s)"
    
    # Spectrogram comparison
    Select outer viewport: 0, 4, 3.3, 4.8
    Select inner viewport: 0.6, 3.8, 3.5, 4.7
    selectObject: original
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    # Draw filter band
    Colour: "{0.8, 0.4, 0.4}"
    Dotted line
    Draw line: 0, freq_cutoff_low, dur, freq_cutoff_low
    Draw line: 0, freq_cutoff_high, dur, freq_cutoff_high
    Solid line
    
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"
    Text left: "yes", "Hz"
    
    Select outer viewport: 4, 8, 3.3, 4.8
    Select inner viewport: 4.4, 7.6, 3.5, 4.7
    selectObject: result
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Transformed"
    
    # Transformation summary
    Select outer viewport: 0, 8, 5.0, 5.8
    Select inner viewport: 0.6, 7.6, 5.1, 5.7
    
    Axes: 0, 4, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 1
    
    # Pitch shift bar
    if pitch_shift_semitones <> 0
        if pitch_shift_semitones > 0
            Paint rectangle: "{0.5, 0.7, 0.5}", 0.1, 0.9, 0.1, 0.9
        else
            Paint rectangle: "{0.7, 0.5, 0.5}", 0.1, 0.9, 0.1, 0.9
        endif
    else
        Paint rectangle: "{0.7, 0.7, 0.7}", 0.1, 0.9, 0.1, 0.9
    endif
    
    # Formant bar
    if formant_shift_ratio <> 1.0
        if formant_shift_ratio > 1.0
            Paint rectangle: "{0.5, 0.5, 0.7}", 1.1, 1.9, 0.1, 0.9
        else
            Paint rectangle: "{0.7, 0.5, 0.7}", 1.1, 1.9, 0.1, 0.9
        endif
    else
        Paint rectangle: "{0.7, 0.7, 0.7}", 1.1, 1.9, 0.1, 0.9
    endif
    
    # Duration bar
    if duration_factor <> 1.0
        if duration_factor > 1.0
            Paint rectangle: "{0.7, 0.6, 0.5}", 2.1, 2.9, 0.1, 0.9
        else
            Paint rectangle: "{0.5, 0.6, 0.7}", 2.1, 2.9, 0.1, 0.9
        endif
    else
        Paint rectangle: "{0.7, 0.7, 0.7}", 2.1, 2.9, 0.1, 0.9
    endif
    
    # Filter bar
    Paint rectangle: "{0.6, 0.6, 0.5}", 3.1, 3.9, 0.1, 0.9
    
    # Labels
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 0.5, "half", string$(pitch_shift_semitones) + "st"
    Text: 1.5, "centre", 0.5, "half", fixed$(formant_shift_ratio, 2) + "x"
    Text: 2.5, "centre", 0.5, "half", fixed$(duration_factor, 2) + "x"
    Text: 3.5, "centre", 0.5, "half", string$(freq_cutoff_low) + "-" + string$(freq_cutoff_high)
    
    Text: 0.5, "centre", -0.3, "half", "Pitch"
    Text: 1.5, "centre", -0.3, "half", "Formant"
    Text: 2.5, "centre", -0.3, "half", "Duration"
    Text: 3.5, "centre", -0.3, "half", "Band"
    
    Colour: "Black"
    Draw inner box
    
    # Stats
    Select outer viewport: 0, 8, 5.9, 6.2
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Duration: " + fixed$(dur, 2) + "s → " + fixed$(newDur, 2) + "s | Preset: " + presetName$
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: manipulation

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(dur, 2), "s → ", fixed$(newDur, 2), "s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result