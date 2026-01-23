# ============================================================
# Praat AudioTools - Harmonic_Resonance_Boost.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.4 (2025) - Fixed syntax, added visualization
# License: MIT License
#
# Description:
#   Boosts frequencies at harmonic intervals of a fundamental
#   while attenuating non-harmonic content. Creates resonant,
#   tuned comb-filter effects with stereo width.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Harmonic Resonance Boost v0.4
    optionmenu Preset: 1
        option Custom
        option Sub Drone (50 Hz)
        option Industrial Hum (60 Hz)
        option Laser Comb (200 Hz)
        option Alien Voice (333 Hz)
        option Metallic Ring (666 Hz)
        option Glass Bells (1200 Hz)
        option Celestial Pad (528 Hz)
        option Swarm (77 Hz)
    comment === Harmonic Parameters ===
    positive Fundamental_frequency 440
    positive Harmonic_bandwidth 50
    positive Harmonic_boost 1.5
    comment === Non-Harmonic Attenuation ===
    positive Mid_freq_cutoff 6000
    positive Low_mid_attenuation 0.6
    positive High_freq_attenuation 0.4
    comment === Stereo ===
    boolean Create_stereo 1
    positive Stereo_bandwidth_offset 15
    comment === Output ===
    positive Scale_peak 0.90
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Sub Drone
    fundamental_frequency = 50
    harmonic_bandwidth = 20
    harmonic_boost = 4.0
    mid_freq_cutoff = 3000
    low_mid_attenuation = 0.15
    high_freq_attenuation = 0.05
    stereo_bandwidth_offset = 8
    presetName$ = "SubDrone"
elsif preset = 3
    # Industrial Hum
    fundamental_frequency = 60
    harmonic_bandwidth = 15
    harmonic_boost = 5.0
    mid_freq_cutoff = 4000
    low_mid_attenuation = 0.1
    high_freq_attenuation = 0.02
    stereo_bandwidth_offset = 5
    presetName$ = "Industrial"
elsif preset = 4
    # Laser Comb
    fundamental_frequency = 200
    harmonic_bandwidth = 8
    harmonic_boost = 6.0
    mid_freq_cutoff = 8000
    low_mid_attenuation = 0.05
    high_freq_attenuation = 0.02
    stereo_bandwidth_offset = 3
    presetName$ = "Laser"
elsif preset = 5
    # Alien Voice
    fundamental_frequency = 333
    harmonic_bandwidth = 40
    harmonic_boost = 3.5
    mid_freq_cutoff = 5000
    low_mid_attenuation = 0.08
    high_freq_attenuation = 0.03
    stereo_bandwidth_offset = 20
    presetName$ = "Alien"
elsif preset = 6
    # Metallic Ring
    fundamental_frequency = 666
    harmonic_bandwidth = 25
    harmonic_boost = 5.5
    mid_freq_cutoff = 6000
    low_mid_attenuation = 0.06
    high_freq_attenuation = 0.04
    stereo_bandwidth_offset = 12
    presetName$ = "Metallic"
elsif preset = 7
    # Glass Bells
    fundamental_frequency = 1200
    harmonic_bandwidth = 35
    harmonic_boost = 3.0
    mid_freq_cutoff = 4000
    low_mid_attenuation = 0.2
    high_freq_attenuation = 0.15
    stereo_bandwidth_offset = 25
    presetName$ = "Glass"
elsif preset = 8
    # Celestial Pad
    fundamental_frequency = 528
    harmonic_bandwidth = 80
    harmonic_boost = 2.0
    mid_freq_cutoff = 7000
    low_mid_attenuation = 0.25
    high_freq_attenuation = 0.15
    stereo_bandwidth_offset = 40
    presetName$ = "Celestial"
elsif preset = 9
    # Swarm
    fundamental_frequency = 77
    harmonic_bandwidth = 12
    harmonic_boost = 4.5
    mid_freq_cutoff = 5000
    low_mid_attenuation = 0.12
    high_freq_attenuation = 0.06
    stereo_bandwidth_offset = 6
    presetName$ = "Swarm"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
numChannels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Harmonic Resonance Boost v0.4 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Fundamental: ", fundamental_frequency, " Hz"
appendInfoLine: "Bandwidth: ", harmonic_bandwidth, " Hz"
appendInfoLine: "Boost: ", harmonic_boost, "x"
appendInfoLine: "Attenuation: ", low_mid_attenuation, " / ", high_freq_attenuation
if create_stereo
    appendInfoLine: "Stereo offset: ", stereo_bandwidth_offset, " Hz"
endif
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if numChannels > 1
    monoID = Convert to mono
else
    monoID = Copy: "mono_temp"
endif

# Build formula strings
fundStr$ = fixed$(fundamental_frequency, 2)
boostStr$ = fixed$(harmonic_boost, 4)
lowAttStr$ = fixed$(low_mid_attenuation, 4)
highAttStr$ = fixed$(high_freq_attenuation, 4)
midCutStr$ = fixed$(mid_freq_cutoff, 2)

# ============================================================
# PROCESS LEFT CHANNEL
# ============================================================

appendInfo: "Processing left channel..."

bwL$ = fixed$(harmonic_bandwidth, 2)

selectObject: monoID
spectrumL_ID = To Spectrum: "yes"

selectObject: spectrumL_ID
matrixL_ID = To Matrix
Rename: "matL"

# Harmonic detection formula:
# Distance to nearest harmonic = abs(x - round(x/f)*f)
# If distance < bandwidth: boost, else: attenuate
selectObject: matrixL_ID
Formula: "if abs(x - round(x / " + fundStr$ + ") * " + fundStr$ + ") < " + bwL$ + " then self * " + boostStr$ + " else (if x < " + midCutStr$ + " then self * " + lowAttStr$ + " else self * " + highAttStr$ + " endif) endif"

selectObject: matrixL_ID
spectrumL_mod_ID = To Spectrum
Rename: "specL"

selectObject: spectrumL_mod_ID
resultL_ID = To Sound

# Trim to original duration
selectObject: resultL_ID
durL = Get total duration
if durL > duration
    trimL_ID = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: resultL_ID
    resultL_ID = trimL_ID
endif

appendInfoLine: " done"

# ============================================================
# PROCESS RIGHT CHANNEL (if stereo)
# ============================================================

if create_stereo
    appendInfo: "Processing right channel..."
    
    bwR$ = fixed$(harmonic_bandwidth + stereo_bandwidth_offset, 2)
    
    selectObject: monoID
    spectrumR_ID = To Spectrum: "yes"
    
    selectObject: spectrumR_ID
    matrixR_ID = To Matrix
    Rename: "matR"
    
    selectObject: matrixR_ID
    Formula: "if abs(x - round(x / " + fundStr$ + ") * " + fundStr$ + ") < " + bwR$ + " then self * " + boostStr$ + " else (if x < " + midCutStr$ + " then self * " + lowAttStr$ + " else self * " + highAttStr$ + " endif) endif"
    
    selectObject: matrixR_ID
    spectrumR_mod_ID = To Spectrum
    Rename: "specR"
    
    selectObject: spectrumR_mod_ID
    resultR_ID = To Sound
    
    # Trim to original duration
    selectObject: resultR_ID
    durR = Get total duration
    if durR > duration
        trimR_ID = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: resultR_ID
        resultR_ID = trimR_ID
    endif
    
    appendInfoLine: " done"
    
    # Combine to stereo
    selectObject: resultL_ID
    plusObject: resultR_ID
    resultID = Combine to stereo
    
    removeObject: spectrumR_ID, matrixR_ID, spectrumR_mod_ID, resultL_ID, resultR_ID
else
    resultID = resultL_ID
endif

# Finalize
selectObject: resultID
if create_stereo
    Rename: originalName$ + "_harmonic_" + presetName$
else
    Rename: originalName$ + "_harmonic_" + presetName$ + "_mono"
endif
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Harmonic Resonance: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Harmonic Boosted"
    
    # Original spectrum
    Select outer viewport: 0, 4, 2.0, 3.6
    Select inner viewport: 0.5, 3.7, 2.2, 3.4
    selectObject: spectrumL_ID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 5000, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original Spectrum"
    Text left: "yes", "dB"
    
    # Modified spectrum
    Select outer viewport: 4, 8, 2.0, 3.6
    Select inner viewport: 4.5, 7.7, 2.2, 3.4
    selectObject: spectrumL_mod_ID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 5000, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Harmonic Boosted Spectrum"
    Text left: "yes", "dB"
    
    # Harmonic filter response
    Select outer viewport: 0, 8, 3.8, 5.2
    Select inner viewport: 0.6, 7.6, 4.0, 5.0
    
    maxFreq = min(5000, fundamental_frequency * 10)
    Axes: 0, maxFreq, 0, harmonic_boost + 0.5
    
    # Draw harmonic peaks
    Colour: "{0.2, 0.7, 0.4}"
    Line width: 2
    
    harmNum = 1
    harmFreq = fundamental_frequency
    while harmFreq < maxFreq
        # Draw peak (triangle approximation)
        leftEdge = harmFreq - harmonic_bandwidth
        rightEdge = harmFreq + harmonic_bandwidth
        if leftEdge < 0
            leftEdge = 0
        endif
        
        # Draw attenuation level on left
        if harmNum = 1
            Draw line: 0, low_mid_attenuation, leftEdge, low_mid_attenuation
        else
            prevRight = (harmNum - 1) * fundamental_frequency + harmonic_bandwidth
            if prevRight < leftEdge
                Draw line: prevRight, low_mid_attenuation, leftEdge, low_mid_attenuation
            endif
        endif
        
        # Draw peak
        Colour: "{0.9, 0.4, 0.2}"
        Draw line: leftEdge, low_mid_attenuation, harmFreq, harmonic_boost
        Draw line: harmFreq, harmonic_boost, rightEdge, low_mid_attenuation
        Colour: "{0.2, 0.7, 0.4}"
        
        harmNum = harmNum + 1
        harmFreq = harmNum * fundamental_frequency
    endwhile
    
    # Draw remaining attenuation
    lastRight = (harmNum - 1) * fundamental_frequency + harmonic_bandwidth
    if lastRight < maxFreq
        Draw line: lastRight, low_mid_attenuation, maxFreq, low_mid_attenuation
    endif
    
    # Mark mid cutoff
    if mid_freq_cutoff < maxFreq
        Colour: "{0.5, 0.5, 0.5}"
        Dotted line
        Draw line: mid_freq_cutoff, 0, mid_freq_cutoff, harmonic_boost + 0.3
        Solid line
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text top: "no", "Harmonic Filter Response (f0=" + string$(fundamental_frequency) + " Hz)"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Info panel
    Select outer viewport: 0, 8, 5.3, 5.9
    Select inner viewport: 0.5, 7.7, 5.35, 5.85
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "f0: " + string$(fundamental_frequency) + " Hz"
    Text: 0.18, "left", 0.5, "half", "BW: " + fixed$(harmonic_bandwidth, 0) + " Hz"
    Text: 0.35, "left", 0.5, "half", "Boost: " + fixed$(harmonic_boost, 1) + "x"
    Text: 0.52, "left", 0.5, "half", "Atten: " + fixed$(low_mid_attenuation, 2)
    if create_stereo
        Text: 0.72, "left", 0.5, "half", "Stereo: ±" + fixed$(stereo_bandwidth_offset, 0) + " Hz"
    else
        Text: 0.72, "left", 0.5, "half", "Mono output"
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoID, spectrumL_ID, matrixL_ID, spectrumL_mod_ID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Harmonics: ", fundStr$, ", ", fixed$(fundamental_frequency * 2, 0), ", ", fixed$(fundamental_frequency * 3, 0), ", ", fixed$(fundamental_frequency * 4, 0), "... Hz"
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_harmonic_", presetName$

if play_result
    selectObject: resultID
    Play
endif
