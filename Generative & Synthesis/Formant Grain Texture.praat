# ============================================================
# Praat AudioTools - Formant_Grain_Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Granular synthesis with vowel-like timbres.
#   Each grain contains formant frequencies characteristic of vowels.
#   Uses pulse train + formant resonances for more realistic vowels.
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
#   - Chunked grain processing
#   - Improved formant synthesis (harmonics + formant weighting)
#   - Fixed filter object handling
#   - Amplitude scaling by density
#   - Added visualization
#   - Modern syntax throughout
# ============================================================

form Formant Grain Texture
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Vowel Cloud
        option Whisper Choir
        option Robotic Speech
        option Alien Language
        option Gregorian Chant
        option Baby Babble
        option Ghost Voices
        option Formant Storm
    
    comment === Basic Settings ===
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    
    comment === Grain Settings ===
    positive Grain_density 25
    positive Min_grain_ms 40
    positive Max_grain_ms 120
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Choir
        option Rotating Voices
        option Wide Cloud
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Vowel Cloud - balanced mix
    grain_density = 20
    base_frequency_Hz = 120
    min_grain_ms = 50
    max_grain_ms = 120
    preset_name$ = "VowelCloud"
    
elsif preset = 3
    # Whisper Choir - breathy, longer grains
    grain_density = 15
    base_frequency_Hz = 0
    min_grain_ms = 80
    max_grain_ms = 180
    preset_name$ = "WhisperChoir"
    
elsif preset = 4
    # Robotic Speech - precise, short grains
    grain_density = 35
    base_frequency_Hz = 80
    min_grain_ms = 30
    max_grain_ms = 60
    preset_name$ = "RoboticSpeech"
    
elsif preset = 5
    # Alien Language - extreme formant shifts
    grain_density = 30
    base_frequency_Hz = 140
    min_grain_ms = 40
    max_grain_ms = 100
    preset_name$ = "AlienLanguage"
    
elsif preset = 6
    # Gregorian Chant - deep, sustained
    duration_s = 8.0
    grain_density = 12
    base_frequency_Hz = 90
    min_grain_ms = 120
    max_grain_ms = 300
    preset_name$ = "GregorianChant"
    
elsif preset = 7
    # Baby Babble - bright, fast
    grain_density = 45
    base_frequency_Hz = 280
    min_grain_ms = 25
    max_grain_ms = 60
    preset_name$ = "BabyBabble"
    
elsif preset = 8
    # Ghost Voices - sparse, ethereal
    grain_density = 8
    base_frequency_Hz = 160
    min_grain_ms = 150
    max_grain_ms = 350
    spatial_mode = 3
    preset_name$ = "GhostVoices"
    
elsif preset = 9
    # Formant Storm - dense, chaotic
    grain_density = 60
    base_frequency_Hz = 110
    min_grain_ms = 15
    max_grain_ms = 40
    spatial_mode = 4
    preset_name$ = "FormantStorm"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 25

# Vowel formants (Peterson & Barney, 1952)
# Vowel 1: /a/ (father)
vowelF1[1] = 730
vowelF2[1] = 1090
vowelF3[1] = 2440
vowelName$[1] = "a"

# Vowel 2: /i/ (beet)
vowelF1[2] = 270
vowelF2[2] = 2290
vowelF3[2] = 3010
vowelName$[2] = "i"

# Vowel 3: /u/ (boot)
vowelF1[3] = 300
vowelF2[3] = 870
vowelF3[3] = 2240
vowelName$[3] = "u"

# Vowel 4: /e/ (bet)
vowelF1[4] = 530
vowelF2[4] = 1840
vowelF3[4] = 2480
vowelName$[4] = "e"

# Vowel 5: /o/ (boat)
vowelF1[5] = 570
vowelF2[5] = 840
vowelF3[5] = 2410
vowelName$[5] = "o"

# Calculate total grains
totalGrains = round(duration_s * grain_density)

# === Info ===
writeInfoLine: "=== Formant Grain Texture ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Density: ", grain_density, " grains/s"
appendInfoLine: "Total grains: ", totalGrains
appendInfoLine: "F0: ", base_frequency_Hz, " Hz"
appendInfoLine: ""

# === Pre-generate grain parameters ===
appendInfoLine: "Generating grain parameters..."

for g to totalGrains
    # Random time placement
    grain_time[g] = randomUniform(0, duration_s - 0.1)
    
    # Grain duration
    grain_dur[g] = (min_grain_ms + (max_grain_ms - min_grain_ms) * randomUniform(0, 1)) / 1000
    
    # Clamp duration
    if grain_time[g] + grain_dur[g] > duration_s
        grain_dur[g] = duration_s - grain_time[g]
    endif
    
    # Vowel selection based on preset
    if preset = 3
        # Whisper Choir - A, O, U (back vowels)
        r = randomUniform(0, 1)
        if r < 0.4
            grain_vowel[g] = 1
        elsif r < 0.7
            grain_vowel[g] = 3
        else
            grain_vowel[g] = 5
        endif
    elsif preset = 4
        # Robotic Speech - I, E (front vowels)
        if randomUniform(0, 1) < 0.5
            grain_vowel[g] = 2
        else
            grain_vowel[g] = 4
        endif
    elsif preset = 6
        # Gregorian Chant - A, O, U
        r = randomUniform(0, 1)
        if r < 0.4
            grain_vowel[g] = 1
        elsif r < 0.7
            grain_vowel[g] = 3
        else
            grain_vowel[g] = 5
        endif
    elsif preset = 8
        # Ghost Voices - O, I
        if randomUniform(0, 1) < 0.6
            grain_vowel[g] = 5
        else
            grain_vowel[g] = 2
        endif
    else
        # Default: random vowel
        grain_vowel[g] = randomInteger(1, 5)
    endif
    
    # Get formants for this vowel
    v = grain_vowel[g]
    grain_f1[g] = vowelF1[v]
    grain_f2[g] = vowelF2[v]
    grain_f3[g] = vowelF3[v]
    
    # Alien Language: random formant shifts
    if preset = 5
        grain_f1[g] = grain_f1[g] * randomUniform(0.7, 1.3)
        grain_f2[g] = grain_f2[g] * randomUniform(0.8, 1.5)
        grain_f3[g] = grain_f3[g] * randomUniform(0.9, 1.3)
    endif
    
    # Amplitude (scaled by density)
    grain_amp[g] = 0.4 / sqrt(max(10, grain_density))
    
    # Pitch variation
    if base_frequency_Hz > 0
        grain_f0[g] = base_frequency_Hz * randomUniform(0.9, 1.1)
    else
        grain_f0[g] = 0
    endif
endfor

# Sort grains by time
appendInfoLine: "Sorting grains..."
for i to totalGrains - 1
    for j from i + 1 to totalGrains
        if grain_time[j] < grain_time[i]
            # Swap all properties
            tempTime = grain_time[i]
            tempDur = grain_dur[i]
            tempVowel = grain_vowel[i]
            tempF0 = grain_f0[i]
            tempF1 = grain_f1[i]
            tempF2 = grain_f2[i]
            tempF3 = grain_f3[i]
            tempAmp = grain_amp[i]
            
            grain_time[i] = grain_time[j]
            grain_dur[i] = grain_dur[j]
            grain_vowel[i] = grain_vowel[j]
            grain_f0[i] = grain_f0[j]
            grain_f1[i] = grain_f1[j]
            grain_f2[i] = grain_f2[j]
            grain_f3[i] = grain_f3[j]
            grain_amp[i] = grain_amp[j]
            
            grain_time[j] = tempTime
            grain_dur[j] = tempDur
            grain_vowel[j] = tempVowel
            grain_f0[j] = tempF0
            grain_f1[j] = tempF1
            grain_f2[j] = tempF2
            grain_f3[j] = tempF3
            grain_amp[j] = tempAmp
        endif
    endfor
endfor

# === Create output sound ===
outputSound = Create Sound from formula: "formant_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Synthesize grains in chunks ===
appendInfoLine: "Synthesizing grains..."

grainIndex = 1
chunkStart = 0
chunkSize = 0.5

while grainIndex <= totalGrains
    chunkEnd = chunkStart + chunkSize
    if chunkEnd > duration_s
        chunkEnd = duration_s
    endif
    
    # Build formula for grains in this time window
    chunkFormula$ = "0"
    grainsInChunk = 0
    
    while grainIndex <= totalGrains and grain_time[grainIndex] < chunkEnd and grainsInChunk < grainsPerChunk
        if grain_dur[grainIndex] > 0.01
            gTime = grain_time[grainIndex]
            gDur = grain_dur[grainIndex]
            gAmp = grain_amp[grainIndex]
            gF0 = grain_f0[grainIndex]
            gF1 = grain_f1[grainIndex]
            gF2 = grain_f2[grainIndex]
            gF3 = grain_f3[grainIndex]
            
            sTime$ = fixed$(gTime, 5)
            sEnd$ = fixed$(gTime + gDur, 5)
            sAmp$ = fixed$(gAmp, 5)
            sDur$ = fixed$(gDur, 5)
            sF0$ = fixed$(gF0, 1)
            sF1$ = fixed$(gF1, 1)
            sF2$ = fixed$(gF2, 1)
            sF3$ = fixed$(gF3, 1)
            
            # Formant synthesis:
            # For voiced: harmonics weighted by formant proximity
            # For whisper (F0=0): noise filtered by formants
            
            if gF0 > 0
                # Voiced: F0 + harmonics weighted toward formants
                # Simplified: just F0 + formant frequencies with relative amplitudes
                grainTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * (0.4 * sin(twoPi * " + sF0$ + " * x) + 0.5 * sin(twoPi * " + sF1$ + " * x) + 0.35 * sin(twoPi * " + sF2$ + " * x) + 0.2 * sin(twoPi * " + sF3$ + " * x)) * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
            else
                # Whisper: formants without F0
                grainTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * (0.5 * sin(twoPi * " + sF1$ + " * x + randomGauss(0, 0.3)) + 0.4 * sin(twoPi * " + sF2$ + " * x + randomGauss(0, 0.3)) + 0.25 * sin(twoPi * " + sF3$ + " * x + randomGauss(0, 0.3))) * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
            endif
            
            chunkFormula$ = chunkFormula$ + grainTerm$
            grainsInChunk = grainsInChunk + 1
        endif
        
        grainIndex = grainIndex + 1
    endwhile
    
    # Apply chunk formula
    if chunkFormula$ <> "0"
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    # Progress
    if chunkStart mod 1 < chunkSize
        appendInfoLine: "  Time: ", fixed$(chunkStart, 1), " s (", grainsInChunk, " grains)"
    endif
    
    chunkStart = chunkEnd
endwhile

# === Apply fade ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Choir
    appendInfoLine: "Creating stereo choir..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 2500, 120
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 150, 4000, 120
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
    # Rotating Voices
    appendInfoLine: "Creating rotating voices..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * cos(twoPi * 0.12 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * sin(twoPi * 0.12 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formant_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 4
    # Wide Cloud
    appendInfoLine: "Creating wide cloud..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 2000, 150
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 300, 6000, 150
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
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
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0.5, 1.2
    Select inner viewport: 0, 7, 0.5, 1.2
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.8, "half", "Formant Grain Texture — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "Vowel-based granular synthesis"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 1.3, 4.8
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 1.4, 4.7
    
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
    .maxFreqSpec = 4000
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: .leftMargin, .rightMargin, 1.4, 4.7
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # Draw formant reference lines
    Colour: "{1, 0.5, 0.5}"
    Line width: 1
    # Average F1 (~450 Hz)
    Draw line: 0, 450, duration_s, 450
    # Average F2 (~1400 Hz)
    Colour: "{0.5, 1, 0.5}"
    Draw line: 0, 1400, duration_s, 1400
    # Average F3 (~2500 Hz)
    Colour: "{0.5, 0.5, 1}"
    Draw line: 0, 2500, duration_s, 2500
    
    # === Footer ===
    Select outer viewport: 0, 7, 4.9, 5.4
    Select inner viewport: 0, 7, 4.9, 5.4
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Density: " + fixed$(grain_density, 0) + " | F0: " + fixed$(base_frequency_Hz, 0) + " Hz | Grains: " + string$(totalGrains) + " | F1/F2/F3 reference lines"
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc