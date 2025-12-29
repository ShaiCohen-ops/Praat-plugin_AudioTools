# ============================================================
# Praat AudioTools - Formant_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Enhanced
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Klatt formant synthesis for realistic vowel sounds.
#   Uses Praat's KlattGrid for proper source-filter synthesis.
#
# Vowel Formants (Peterson & Barney, 1952):
#   /a/ (father): F1=730, F2=1090, F3=2440
#   /i/ (beet):   F1=270, F2=2290, F3=3010
#   /u/ (boot):   F1=300, F2=870,  F3=2240
#   /e/ (bet):    F1=530, F2=1840, F3=2480
#   /o/ (boat):   F1=570, F2=840,  F3=2410
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit 
#   for Experimental Composition.
#
# Changelog v0.2:
#   - Added spatial modes
#   - Added visualization
#   - Added morphing vowel option
# ============================================================

form Formant Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Vowel A (ah)
        option Vowel E (eh)
        option Vowel I (ee)
        option Vowel O (oh)
        option Vowel U (oo)
        option Soprano A
        option Bass O
        option Child E
        option Robot Voice
        option Whisper
        option Singing
        option Alien Voice
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    positive Pitch_Hz 120
    integer Sample_rate_Hz 44100
    
    comment === Formant Frequencies (Hz) ===
    positive F1 500
    positive F2 1500
    positive F3 2500
    positive F4 3500
    
    comment === Formant Bandwidths (Hz) ===
    positive BW1 50
    positive BW2 70
    positive BW3 110
    positive BW4 150
    
    comment === Voice Quality ===
    positive Voicing_amplitude 60
    boolean Enable_vibrato 1
    positive Vibrato_rate_Hz 6
    positive Vibrato_depth_Hz 10
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo (formant spread)
        option Chorus (detuned copies)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Vowel A (ah)
    f1 = 730
    f2 = 1090
    f3 = 2440
    f4 = 3500
    bW1 = 40
    bW2 = 60
    bW3 = 100
    bW4 = 120
    preset_name$ = "Vowel_A"
    
elsif preset = 3
    # Vowel E (eh)
    f1 = 530
    f2 = 1840
    f3 = 2480
    f4 = 3500
    bW1 = 45
    bW2 = 65
    bW3 = 105
    bW4 = 125
    preset_name$ = "Vowel_E"
    
elsif preset = 4
    # Vowel I (ee)
    f1 = 270
    f2 = 2290
    f3 = 3010
    f4 = 3500
    bW1 = 35
    bW2 = 70
    bW3 = 110
    bW4 = 130
    preset_name$ = "Vowel_I"
    
elsif preset = 5
    # Vowel O (oh)
    f1 = 570
    f2 = 840
    f3 = 2410
    f4 = 3500
    bW1 = 50
    bW2 = 60
    bW3 = 100
    bW4 = 120
    preset_name$ = "Vowel_O"
    
elsif preset = 6
    # Vowel U (oo)
    f1 = 300
    f2 = 870
    f3 = 2240
    f4 = 3500
    bW1 = 40
    bW2 = 55
    bW3 = 95
    bW4 = 115
    preset_name$ = "Vowel_U"
    
elsif preset = 7
    # Soprano A
    f1 = 800
    f2 = 1150
    f3 = 2900
    f4 = 3900
    pitch_Hz = 260
    bW1 = 35
    bW2 = 50
    bW3 = 90
    bW4 = 110
    preset_name$ = "Soprano_A"
    
elsif preset = 8
    # Bass O
    f1 = 450
    f2 = 800
    f3 = 2830
    f4 = 3500
    pitch_Hz = 80
    bW1 = 60
    bW2 = 70
    bW3 = 120
    bW4 = 140
    preset_name$ = "Bass_O"
    
elsif preset = 9
    # Child E
    f1 = 600
    f2 = 2000
    f3 = 2600
    f4 = 3800
    pitch_Hz = 300
    bW1 = 30
    bW2 = 55
    bW3 = 95
    bW4 = 115
    preset_name$ = "Child_E"
    
elsif preset = 10
    # Robot Voice
    f1 = 400
    f2 = 1200
    f3 = 2400
    f4 = 3200
    bW1 = 20
    bW2 = 30
    bW3 = 40
    bW4 = 50
    enable_vibrato = 0
    preset_name$ = "Robot"
    
elsif preset = 11
    # Whisper
    f1 = 500
    f2 = 1500
    f3 = 2500
    f4 = 3500
    voicing_amplitude = 20
    enable_vibrato = 0
    bW1 = 80
    bW2 = 100
    bW3 = 150
    bW4 = 200
    preset_name$ = "Whisper"
    
elsif preset = 12
    # Singing
    f1 = 600
    f2 = 1200
    f3 = 2400
    f4 = 3600
    pitch_Hz = 220
    vibrato_depth_Hz = 15
    bW1 = 35
    bW2 = 55
    bW3 = 95
    bW4 = 115
    preset_name$ = "Singing"
    
elsif preset = 13
    # Alien Voice
    f1 = 200
    f2 = 3000
    f3 = 4000
    f4 = 5000
    pitch_Hz = 180
    bW1 = 15
    bW2 = 25
    bW3 = 35
    bW4 = 45
    enable_vibrato = 0
    preset_name$ = "Alien"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Info ===
writeInfoLine: "=== Formant Synthesis (KlattGrid) ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Pitch: ", pitch_Hz, " Hz"
appendInfoLine: "Formants: F1=", f1, " F2=", f2, " F3=", f3, " F4=", f4
appendInfoLine: "Bandwidths: ", bW1, " ", bW2, " ", bW3, " ", bW4
appendInfoLine: ""

# === Create KlattGrid ===
appendInfoLine: "Creating KlattGrid..."

klattGrid = Create KlattGrid: "synth_" + uid$, 0, duration_s, 6, 1, 1, 6, 1, 1, 1

# === Set pitch contour ===
selectObject: klattGrid

if enable_vibrato
    # Add vibrato with multiple points per cycle
    vibratoPoints = round(duration_s * vibrato_rate_Hz * 4)
    if vibratoPoints < 8
        vibratoPoints = 8
    endif
    
    for point to vibratoPoints
        time = (point - 1) * duration_s / (vibratoPoints - 1)
        vibratoOffset = vibrato_depth_Hz * sin(twoPi * vibrato_rate_Hz * time)
        currentPitch = pitch_Hz + vibratoOffset
        Add pitch point: time, currentPitch
    endfor
else
    Add pitch point: 0, pitch_Hz
    Add pitch point: duration_s, pitch_Hz
endif

# === Set oral formant frequencies ===
selectObject: klattGrid
Add oral formant frequency point: 1, duration_s / 2, f1
Add oral formant frequency point: 2, duration_s / 2, f2
Add oral formant frequency point: 3, duration_s / 2, f3
Add oral formant frequency point: 4, duration_s / 2, f4

# === Set oral formant bandwidths ===
selectObject: klattGrid
Add oral formant bandwidth point: 1, duration_s / 2, bW1
Add oral formant bandwidth point: 2, duration_s / 2, bW2
Add oral formant bandwidth point: 3, duration_s / 2, bW3
Add oral formant bandwidth point: 4, duration_s / 2, bW4

# === Set voicing amplitude ===
selectObject: klattGrid
Add voicing amplitude point: duration_s / 2, voicing_amplitude

# === Synthesize ===
appendInfoLine: "Synthesizing..."

selectObject: klattGrid
To Sound
synthesized = selected("Sound")

# Resample to target sample rate
selectObject: synthesized
outputSound = Resample: sample_rate_Hz, 50
Rename: "formant_" + uid$

# Clean up intermediate
removeObject: klattGrid, synthesized

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo (formant spread)
    appendInfoLine: "Creating stereo spread..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, (f2 + f3) / 2, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): f1, f4, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formant_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Chorus (detuned copies)
    appendInfoLine: "Creating chorus effect..."
    
    # Create slightly detuned left
    klattLeft = Create KlattGrid: "left_" + uid$, 0, duration_s, 6, 1, 1, 6, 1, 1, 1
    Add pitch point: 0, pitch_Hz * 0.995
    Add pitch point: duration_s, pitch_Hz * 0.995
    Add oral formant frequency point: 1, duration_s / 2, f1
    Add oral formant frequency point: 2, duration_s / 2, f2
    Add oral formant frequency point: 3, duration_s / 2, f3
    Add oral formant frequency point: 4, duration_s / 2, f4
    Add oral formant bandwidth point: 1, duration_s / 2, bW1
    Add oral formant bandwidth point: 2, duration_s / 2, bW2
    Add oral formant bandwidth point: 3, duration_s / 2, bW3
    Add oral formant bandwidth point: 4, duration_s / 2, bW4
    Add voicing amplitude point: duration_s / 2, voicing_amplitude
    To Sound
    leftSynth = selected("Sound")
    leftSound = Resample: sample_rate_Hz, 50
    removeObject: klattLeft, leftSynth
    
    # Create slightly detuned right
    klattRight = Create KlattGrid: "right_" + uid$, 0, duration_s, 6, 1, 1, 6, 1, 1, 1
    Add pitch point: 0, pitch_Hz * 1.005
    Add pitch point: duration_s, pitch_Hz * 1.005
    Add oral formant frequency point: 1, duration_s / 2, f1
    Add oral formant frequency point: 2, duration_s / 2, f2
    Add oral formant frequency point: 3, duration_s / 2, f3
    Add oral formant frequency point: 4, duration_s / 2, f4
    Add oral formant bandwidth point: 1, duration_s / 2, bW1
    Add oral formant bandwidth point: 2, duration_s / 2, bW2
    Add oral formant bandwidth point: 3, duration_s / 2, bW3
    Add oral formant bandwidth point: 4, duration_s / 2, bW4
    Add voicing amplitude point: duration_s / 2, voicing_amplitude
    To Sound
    rightSynth = selected("Sound")
    rightSound = Resample: sample_rate_Hz, 50
    removeObject: klattRight, rightSynth
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formant_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "formant_" + preset_name$
endif

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

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
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0.3, 0.9
    Select inner viewport: 0, 7, 0.3, 0.9
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Formant Synthesis (KlattGrid) — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "Pitch: " + fixed$(pitch_Hz, 0) + " Hz | Voicing: " + fixed$(voicing_amplitude, 0) + " dB"
    
    # === Vowel Diagram (F1 vs F2) ===
    Select outer viewport: 0, 3.5, 1.0, 4.0
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.4, 3.3, 1.1, 3.9
    
    # Axes: F2 (horizontal, reversed: high=front=left), F1 (vertical, reversed: low=close=top)
    # F2 range: 500-2500 Hz, F1 range: 200-900 Hz
    .f2Min = 500
    .f2Max = 2500
    .f1Min = 200
    .f1Max = 900
    
    Axes: .f2Max, .f2Min, .f1Max, .f1Min
    
    # Draw vowel quadrilateral outline
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    # /i/ to /e/
    Draw line: 2290, 270, 1840, 530
    # /e/ to /a/
    Draw line: 1840, 530, 1090, 730
    # /a/ to /o/
    Draw line: 1090, 730, 840, 570
    # /o/ to /u/
    Draw line: 840, 570, 870, 300
    # /u/ to /i/ (top)
    Draw line: 870, 300, 2290, 270
    
    # Draw reference vowels
    Font size: 12
    
    # /i/ - front close
    Colour: "{0.5, 0.5, 0.8}"
    Paint circle: "{0.5, 0.5, 0.8}", 2290, 270, 40
    Colour: "Black"
    Text: 2290, "centre", 270, "top", "i"
    
    # /e/ - front mid
    Colour: "{0.5, 0.5, 0.8}"
    Paint circle: "{0.5, 0.5, 0.8}", 1840, 530, 40
    Colour: "Black"
    Text: 1840, "centre", 530, "top", "e"
    
    # /a/ - open
    Colour: "{0.5, 0.5, 0.8}"
    Paint circle: "{0.5, 0.5, 0.8}", 1090, 730, 40
    Colour: "Black"
    Text: 1090, "centre", 730, "top", "a"
    
    # /o/ - back mid
    Colour: "{0.5, 0.5, 0.8}"
    Paint circle: "{0.5, 0.5, 0.8}", 840, 570, 40
    Colour: "Black"
    Text: 840, "centre", 570, "top", "o"
    
    # /u/ - back close
    Colour: "{0.5, 0.5, 0.8}"
    Paint circle: "{0.5, 0.5, 0.8}", 870, 300, 40
    Colour: "Black"
    Text: 870, "centre", 300, "top", "u"
    
    # Draw CURRENT vowel position (large, red)
    Colour: "{0.9, 0.2, 0.2}"
    Paint circle: "{0.9, 0.2, 0.2}", f2, f1, 60
    Colour: "White"
    Font size: 10
    Text: f2, "centre", f1, "half", "●"
    
    # Axes labels
    Colour: "Black"
    Font size: 9
    Select inner viewport: 0.4, 3.3, 1.1, 3.9
    Axes: .f2Max, .f2Min, .f1Max, .f1Min
    Marks top: 4, "yes", "yes", "no"
    Marks right: 4, "yes", "yes", "no"
    
    # Labels
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Select outer viewport: 0, 3.5, 1.0, 4.0
    Select inner viewport: 0, 3.5, 1.0, 4.0
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.02, "bottom", "F2 (Hz) ← Front — Back →"
    Text: 0.97, "left", 0.5, "half", "F1"
    
    # Corner labels
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.1, "centre", 0.92, "half", "Close"
    Text: 0.1, "centre", 0.12, "half", "Open"
    Text: 0.15, "centre", 0.97, "half", "Front"
    Text: 0.85, "centre", 0.97, "half", "Back"
    
    # === Spectrogram ===
    Select outer viewport: 3.5, 7, 1.0, 4.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 3.7, 6.8, 1.1, 3.9
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    
    selectObject: .monoSpec
    .maxFreqSpec = max(4000, f4 * 1.2)
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 3.7, 6.8, 1.1, 3.9
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # Draw formant lines on spectrogram
    Line width: 2
    Colour: "{1, 0.4, 0.4}"
    Draw line: 0, f1, duration_s, f1
    Colour: "{0.4, 1, 0.4}"
    Draw line: 0, f2, duration_s, f2
    Colour: "{0.4, 0.4, 1}"
    Draw line: 0, f3, duration_s, f3
    Colour: "{1, 1, 0.4}"
    Draw line: 0, f4, duration_s, f4
    Line width: 1
    
    # === Footer ===
    Select outer viewport: 0, 7, 4.1, 4.5
    Select inner viewport: 0, 7, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "F1=" + fixed$(f1, 0) + " F2=" + fixed$(f2, 0) + " F3=" + fixed$(f3, 0) + " F4=" + fixed$(f4, 0) + " Hz | BW: " + fixed$(bW1, 0) + "/" + fixed$(bW2, 0) + "/" + fixed$(bW3, 0) + "/" + fixed$(bW4, 0) + " Hz"
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
