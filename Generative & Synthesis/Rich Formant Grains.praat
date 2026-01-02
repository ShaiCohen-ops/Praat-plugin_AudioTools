# ============================================================
# Praat AudioTools - Rich_Formant_Grains.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Granular synthesis using vowel formant frequencies (F1, F2, F3).
#   Creates speech-like textures by scattering vowel "phonemes" in time.
#   Uses standard acoustic phonetics formant values for realistic
#   vowel-like timbres.
#
#   Each grain contains a fundamental + 3 formant frequencies,
#   creating rich, voice-like spectral content.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.2:
#   - Chunked synthesis (prevents formula explosion)
#   - Fixed Filter object tracking
#   - Added visualization
#   - Modern syntax
# ============================================================

form Rich Formant Grains
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Vowel Cloud
        option Whisper Choir
        option Robotic Speech
        option Alien Language
        option Gregorian Chant
        option Baby Babble
        option Synthetic Singing
        option Ghost Voices
    
    comment === Timing ===
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Grain_density 35.0
    
    comment === Pitch ===
    positive Base_frequency_Hz 120
    
    comment === Spatialization ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Choir
        option Rotating Voices
        option Binaural Whisper
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    grain_density = 25
    base_frequency_Hz = 110
    preset_name$ = "VowelCloud"
elsif preset = 3
    grain_density = 15
    base_frequency_Hz = 180
    preset_name$ = "WhisperChoir"
elsif preset = 4
    grain_density = 40
    base_frequency_Hz = 80
    preset_name$ = "RoboticSpeech"
elsif preset = 5
    grain_density = 30
    base_frequency_Hz = 140
    preset_name$ = "AlienLanguage"
elsif preset = 6
    grain_density = 20
    base_frequency_Hz = 90
    preset_name$ = "GregorianChant"
elsif preset = 7
    grain_density = 45
    base_frequency_Hz = 250
    preset_name$ = "BabyBabble"
elsif preset = 8
    grain_density = 28
    base_frequency_Hz = 130
    preset_name$ = "SyntheticSinging"
elsif preset = 9
    grain_density = 12
    base_frequency_Hz = 160
    preset_name$ = "GhostVoices"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 15

# === Define Vowel Formants (Standard Acoustic Phonetics) ===
# /a/ as in "father"
vowelF1[1] = 730
vowelF2[1] = 1090
vowelF3[1] = 2440
vowelName$[1] = "a"

# /i/ as in "beat"
vowelF1[2] = 270
vowelF2[2] = 2290
vowelF3[2] = 3010
vowelName$[2] = "i"

# /u/ as in "boot"
vowelF1[3] = 300
vowelF2[3] = 870
vowelF3[3] = 2240
vowelName$[3] = "u"

# /ɛ/ as in "bet"
vowelF1[4] = 530
vowelF2[4] = 1840
vowelF3[4] = 2480
vowelName$[4] = "e"

# /o/ as in "boat"
vowelF1[5] = 570
vowelF2[5] = 840
vowelF3[5] = 2410
vowelName$[5] = "o"

nVowels = 5

# Spatial mode name
if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "StereoChoir"
elsif spatial_mode = 3
    spatial_name$ = "Rotating"
else
    spatial_name$ = "Binaural"
endif

# === Info ===
writeInfoLine: "=== Rich Formant Grains ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Grain density: ", grain_density, " grains/s"
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Spatial: ", spatial_name$
appendInfoLine: ""

# === Generate Grain Parameters ===
appendInfoLine: "Generating grain parameters..."

totalGrains = round(duration_s * grain_density)

for g to totalGrains
    grainTime[g] = randomUniform(0, duration_s - 0.15)
    
    # Select vowel based on preset
    if preset = 2
        # Vowel Cloud - all vowels
        vowelIdx = randomInteger(1, 5)
    elsif preset = 3
        # Whisper Choir - a, u, o (back vowels)
        r = randomUniform(0, 1)
        if r < 0.33
            vowelIdx = 1
        elsif r < 0.66
            vowelIdx = 3
        else
            vowelIdx = 5
        endif
    elsif preset = 4
        # Robotic Speech - all vowels, rapid
        vowelIdx = randomInteger(1, 5)
    elsif preset = 5
        # Alien Language - modified formants (handled below)
        vowelIdx = randomInteger(1, 5)
    elsif preset = 6
        # Gregorian Chant - a, u, o (open vowels)
        r = randomUniform(0, 1)
        if r < 0.4
            vowelIdx = 1
        elsif r < 0.7
            vowelIdx = 3
        else
            vowelIdx = 5
        endif
    elsif preset = 7
        # Baby Babble - all vowels, varied
        vowelIdx = randomInteger(1, 5)
    elsif preset = 8
        # Synthetic Singing - all vowels
        vowelIdx = randomInteger(1, 5)
    elsif preset = 9
        # Ghost Voices - i, u (close vowels)
        if randomUniform(0, 1) < 0.5
            vowelIdx = 2
        else
            vowelIdx = 3
        endif
    else
        # Custom - all vowels
        vowelIdx = randomInteger(1, 5)
    endif
    
    grainVowel[g] = vowelIdx
    
    # Get formants (with optional modification for Alien preset)
    if preset = 5
        # Alien - shift formants randomly
        grainF1[g] = vowelF1[vowelIdx] * (0.5 + randomUniform(0, 1))
        grainF2[g] = vowelF2[vowelIdx] * (0.7 + randomUniform(0, 0.6))
        grainF3[g] = vowelF3[vowelIdx] * (0.8 + randomUniform(0, 0.4))
    else
        grainF1[g] = vowelF1[vowelIdx]
        grainF2[g] = vowelF2[vowelIdx]
        grainF3[g] = vowelF3[vowelIdx]
    endif
    
    # Duration based on preset
    if preset = 3
        # Whisper - longer
        grainDur[g] = 0.08 + 0.15 * randomUniform(0, 1)
    elsif preset = 4
        # Robotic - short
        grainDur[g] = 0.03 + 0.05 * randomUniform(0, 1)
    elsif preset = 6
        # Gregorian - long, sustained
        grainDur[g] = 0.10 + 0.20 * randomUniform(0, 1)
    elsif preset = 7
        # Baby - short
        grainDur[g] = 0.02 + 0.04 * randomUniform(0, 1)
    elsif preset = 9
        # Ghost - very long
        grainDur[g] = 0.12 + 0.25 * randomUniform(0, 1)
    else
        grainDur[g] = 0.04 + 0.08 * randomUniform(0, 1)
    endif
    
    # Amplitude
    if preset = 3
        grainAmp[g] = 0.4 + 0.2 * randomUniform(0, 1)
    elsif preset = 4
        grainAmp[g] = 0.8 + 0.1 * randomUniform(0, 1)
    elsif preset = 9
        grainAmp[g] = 0.3 + 0.2 * randomUniform(0, 1)
    else
        grainAmp[g] = 0.6 + 0.3 * randomUniform(0, 1)
    endif
    
    # Pitch variation
    grainPitch[g] = base_frequency_Hz * (0.9 + 0.2 * randomUniform(0, 1))
    
    # Clamp duration
    if grainTime[g] + grainDur[g] > duration_s
        grainDur[g] = duration_s - grainTime[g]
    endif
endfor

appendInfoLine: "Generated ", totalGrains, " grains"

# === Synthesize with Chunked Approach ===
appendInfoLine: "Synthesizing formant grains..."

monoSound = Create Sound from formula: "mono_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

nChunks = ceiling(totalGrains / grainsPerChunk)

for chunk to nChunks
    startGrain = (chunk - 1) * grainsPerChunk + 1
    endGrain = min(chunk * grainsPerChunk, totalGrains)
    
    chunkFormula$ = ""
    
    for g from startGrain to endGrain
        if grainDur[g] > 0.001
            t$ = fixed$(grainTime[g], 6)
            d$ = fixed$(grainDur[g], 6)
            a$ = fixed$(grainAmp[g], 3)
            f0$ = fixed$(grainPitch[g], 2)
            f1$ = fixed$(grainF1[g], 1)
            f2$ = fixed$(grainF2[g], 1)
            f3$ = fixed$(grainF3[g], 1)
            
            # Grain: fundamental + 3 formants, half-sine envelope
            # Formula: amp * (0.3*sin(f0) + 0.5*sin(F1) + 0.4*sin(F2) + 0.3*sin(F3)) * envelope
            term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * (0.3 * sin(twoPi * " + f0$ + " * x) + 0.5 * sin(twoPi * " + f1$ + " * x) + 0.4 * sin(twoPi * " + f2$ + " * x) + 0.3 * sin(twoPi * " + f3$ + " * x)) * sin(pi * (x - " + t$ + ") / " + d$ + ") else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = term$
            else
                chunkFormula$ = chunkFormula$ + " + " + term$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: monoSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Chunk ", chunk, "/", nChunks
    endif
endfor

# === Apply Spatial Mode ===
appendInfoLine: ""
appendInfoLine: "Applying spatial mode: ", spatial_name$

if spatial_mode = 1
    # Mono
    selectObject: monoSound
    outputSound = monoSound
    Rename: "formant_" + preset_name$

elsif spatial_mode = 2
    # Stereo Choir (different EQ per channel)
    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.9"
    Filter (pass Hann band): 0, 2500, 120
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.9"
    Filter (pass Hann band): 150, 4000, 120
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "formant_" + preset_name$ + "_choir"
    
    removeObject: leftSound, rightSound, monoSound

elsif spatial_mode = 3
    # Rotating Voices
    rotationRate = 0.12
    rotRate$ = fixed$(rotationRate, 3)
    
    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * cos(twoPi * " + rotRate$ + " * x))"
    
    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * sin(twoPi * " + rotRate$ + " * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "formant_" + preset_name$ + "_rotating"
    
    removeObject: leftSound, rightSound, monoSound

else
    # Binaural Whisper
    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 100, 3000, 80
    leftFiltered = selected("Sound")
    Formula: "self * (0.8 + 0.1 * sin(twoPi * 0.2 * x))"
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 80, 3500, 80
    rightFiltered = selected("Sound")
    Formula: "self * (0.7 + 0.2 * cos(twoPi * 0.25 * x))"
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "formant_" + preset_name$ + "_binaural"
    
    removeObject: leftSound, rightSound, monoSound
endif

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.03 then self * (x / 0.03) else self fi"
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
    Text: 0.5, "centre", 0.7, "half", "Rich Formant Grains — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", string$(totalGrains) + " grains | " + spatial_name$
    
    # === Grain Timeline (colored by vowel) ===
    Select outer viewport: 0, 7, 0.9, 2.5
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 1.0, 2.4
    Axes: 0, duration_s, 0, 4000
    
    # Draw grains as rectangles (height = F2 range)
    for .g to totalGrains
        .t = grainTime[.g]
        .d = grainDur[.g]
        .f1 = grainF1[.g]
        .f2 = grainF2[.g]
        .v = grainVowel[.g]
        
        # Color by vowel
        if .v = 1
            .col$ = "{0.9, 0.3, 0.3}"
        elsif .v = 2
            .col$ = "{0.3, 0.9, 0.3}"
        elsif .v = 3
            .col$ = "{0.3, 0.3, 0.9}"
        elsif .v = 4
            .col$ = "{0.9, 0.6, 0.2}"
        else
            .col$ = "{0.6, 0.3, 0.9}"
        endif
        
        Paint rectangle: .col$, .t, .t + .d, .f1, .f2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "F1-F2 (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # === Vowel Legend ===
    Select outer viewport: 0, 7, 2.6, 3.0
    Select inner viewport: 0.5, 6.5, 2.65, 2.95
    Axes: 0, 5, 0, 1
    
    Paint rectangle: "{0.9, 0.3, 0.3}", 0, 0.8, 0.2, 0.8
    Paint rectangle: "{0.3, 0.9, 0.3}", 1, 1.8, 0.2, 0.8
    Paint rectangle: "{0.3, 0.3, 0.9}", 2, 2.8, 0.2, 0.8
    Paint rectangle: "{0.9, 0.6, 0.2}", 3, 3.8, 0.2, 0.8
    Paint rectangle: "{0.6, 0.3, 0.9}", 4, 4.8, 0.2, 0.8
    
    Font size: 8
    Colour: "Black"
    Text: 0.4, "centre", 0.5, "half", "/a/"
    Text: 1.4, "centre", 0.5, "half", "/i/"
    Text: 2.4, "centre", 0.5, "half", "/u/"
    Text: 3.4, "centre", 0.5, "half", "/e/"
    Text: 4.4, "centre", 0.5, "half", "/o/"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 3.2, 5.5
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 3.3, 5.4
    
    selectObject: outputSound
    .nCh = Get number of channels
    if .nCh > 1
        Extract one channel: 1
        .tempSpec = selected("Sound")
    else
        Copy: "temp_spec"
        .tempSpec = selected("Sound")
    endif
    
    selectObject: .tempSpec
    To Spectrogram: 0.02, 4000, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .tempSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 3.3, 5.4
    Axes: 0, duration_s, 0, 4000
    
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 5.6, 6.0
    Select inner viewport: 0, 7, 5.6, 6.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Formant synthesis: F0 + F1 + F2 + F3 with half-sine envelope"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc