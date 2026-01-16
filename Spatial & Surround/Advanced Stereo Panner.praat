# ============================================================
# Praat AudioTools - Advanced_Stereo_Panner.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced stereo panning with four psychoacoustic cues:
#   - ILD (Interaural Level Difference)
#   - ITD (Interaural Time Difference)
#   - Spectral Cues (head shadow simulation)
#   - Distance Effects (amplitude & air absorption)
#   Inspired by Goodhertz Panpot
#
# Changelog v1.1:
#   - Added input validation
#   - Added visualization
#   - Added play toggle
# ============================================================

form Advanced Stereo Panner
    comment === PRESET ===
    optionmenu Preset: 1
        option: "Center"
        option: "Hard Left"
        option: "Hard Right"
        option: "Medium Left"
        option: "Medium Right"
        option: "Subtle Left"
        option: "Subtle Right"
        option: "Wide Left"
        option: "Wide Right"
        option: "Custom"
    
    comment === PAN POSITION (-1 = Left, 0 = Center, +1 = Right) ===
    real Pan_position 0.0
    
    comment === ILD (Interaural Level Difference) ===
    positive ILD_max_dB 12
    
    comment === ITD (Interaural Time Difference) ===
    boolean Use_ITD 1
    positive Max_ITD_ms 0.65
    
    comment === Spectral Cues (Head Shadow) ===
    boolean Use_spectral_cues 1
    positive High_freq_rolloff_Hz 8000
    
    comment === Distance Effects ===
    boolean Use_distance 1
    positive Distance_meters 1.0
    positive Max_distance_meters 30.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply presets ===
if preset = 1
    pan_position = 0.0
    presetName$ = "Center"
elsif preset = 2
    pan_position = -1.0
    presetName$ = "HardLeft"
elsif preset = 3
    pan_position = 1.0
    presetName$ = "HardRight"
elsif preset = 4
    pan_position = -0.5
    presetName$ = "MediumLeft"
elsif preset = 5
    pan_position = 0.5
    presetName$ = "MediumRight"
elsif preset = 6
    pan_position = -0.25
    presetName$ = "SubtleLeft"
elsif preset = 7
    pan_position = 0.25
    presetName$ = "SubtleRight"
elsif preset = 8
    pan_position = -0.75
    presetName$ = "WideLeft"
elsif preset = 9
    pan_position = 0.75
    presetName$ = "WideRight"
else
    presetName$ = "Custom"
endif

# === Validate ===
if pan_position < -1 or pan_position > 1
    exitScript: "Pan position must be between -1 and 1"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels

# === Info ===
writeInfoLine: "=== Advanced Stereo Panner ==="
appendInfoLine: "Source: ", name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Pan position: ", pan_position
appendInfoLine: ""

# === Convert to mono ===
if numChannels > 1
    mono = Convert to mono
else
    mono = Copy: name$ + "_mono"
endif

# === Calculate constant power panning ===
panNorm = (pan_position + 1) / 2
gain[1] = sqrt(1 - panNorm)
gain[2] = sqrt(panNorm)

# === Apply ILD ===
absPan = abs(pan_position)
if pan_position < 0
    gain[1] = gain[1] * 10^(absPan * iLD_max_dB / 20)
    gain[2] = gain[2] * 10^(-absPan * iLD_max_dB / 20)
else
    gain[1] = gain[1] * 10^(-pan_position * iLD_max_dB / 20)
    gain[2] = gain[2] * 10^(pan_position * iLD_max_dB / 20)
endif

appendInfoLine: "ILD applied: ±", fixed$(absPan * iLD_max_dB, 1), " dB"

# === Distance attenuation (inverse square law) ===
distFactor = distance_meters / max_distance_meters
distGain = 1 / (1 + distFactor * 2)
if use_distance
    gain[1] = gain[1] * distGain
    gain[2] = gain[2] * distGain
    appendInfoLine: "Distance: ", distance_meters, "m (gain: ", fixed$(distGain, 3), ")"
endif

# === ITD calculation ===
itd = 0
if use_ITD
    itd = absPan * max_ITD_ms / 1000
    appendInfoLine: "ITD: ", fixed$(itd * 1000, 2), " ms"
endif

# ============================================================
# LEFT CHANNEL
# ============================================================
selectObject: mono
chL = Copy: "L"

# Apply spectral cue (shadow when panned RIGHT)
if use_spectral_cues
    if pan_position > 0
        selectObject: chL
        cutoff = high_freq_rolloff_Hz * (1 - pan_position * 0.5)
        Filter (pass Hann band): 0, cutoff, 100
        temp = selected("Sound")
        removeObject: chL
        chL = temp
        appendInfoLine: "Left HF cutoff: ", fixed$(cutoff, 0), " Hz (head shadow)"
    endif
endif

# Apply distance air absorption
if use_distance
    if distance_meters > 1
        selectObject: chL
        airCutoff = 12000 / (1 + distFactor * 3)
        Filter (pass Hann band): 0, airCutoff, 200
        temp = selected("Sound")
        removeObject: chL
        chL = temp
    endif
endif

# Apply ITD (delay left when panned RIGHT)
if use_ITD
    if pan_position > 0 and itd > 0
        selectObject: chL
        silence = Create Sound from formula: "s", 1, 0, itd, sampleRate, "0"
        plusObject: chL
        concat = Concatenate
        selectObject: concat
        Extract part: 0, duration, "rectangular", 1, "no"
        temp = selected("Sound")
        removeObject: silence, concat, chL
        chL = temp
    endif
endif

selectObject: chL
Formula: "self * " + string$(gain[1])

# ============================================================
# RIGHT CHANNEL
# ============================================================
selectObject: mono
chR = Copy: "R"

# Apply spectral cue (shadow when panned LEFT)
if use_spectral_cues
    if pan_position < 0
        selectObject: chR
        cutoff = high_freq_rolloff_Hz * (1 - absPan * 0.5)
        Filter (pass Hann band): 0, cutoff, 100
        temp = selected("Sound")
        removeObject: chR
        chR = temp
        appendInfoLine: "Right HF cutoff: ", fixed$(cutoff, 0), " Hz (head shadow)"
    endif
endif

# Apply distance air absorption
if use_distance
    if distance_meters > 1
        selectObject: chR
        airCutoff = 12000 / (1 + distFactor * 3)
        Filter (pass Hann band): 0, airCutoff, 200
        temp = selected("Sound")
        removeObject: chR
        chR = temp
    endif
endif

# Apply ITD (delay right when panned LEFT)
if use_ITD
    if pan_position < 0 and itd > 0
        selectObject: chR
        silence = Create Sound from formula: "s", 1, 0, itd, sampleRate, "0"
        plusObject: chR
        concat = Concatenate
        selectObject: concat
        Extract part: 0, duration, "rectangular", 1, "no"
        temp = selected("Sound")
        removeObject: silence, concat, chR
        chR = temp
    endif
endif

selectObject: chR
Formula: "self * " + string$(gain[2])

# ============================================================
# COMBINE
# ============================================================
selectObject: chL
plusObject: chR
stereo = Combine to stereo
Scale peak: 0.95
Rename: name$ + "_pan_" + presetName$

removeObject: chL, chR, mono

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Advanced Stereo Panner: " + presetName$ + " | " + name$
    
    # Stereo field diagram
    Select outer viewport: 0.5, 5.0, 0.8, 4.0
    Select inner viewport: 0.8, 4.7, 1.1, 3.7
    
    Axes: -1.5, 1.5, -1, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1, 1
    
    # Speakers
    Paint circle (mm): "{0.4, 0.4, 0.4}", -1.2, 0.7, 4
    Font size: 7
    Colour: "Black"
    Text: -1.2, "centre", 0.5, "half", "L"
    
    Paint circle (mm): "{0.4, 0.4, 0.4}", 1.2, 0.7, 4
    Text: 1.2, "centre", 0.5, "half", "R"
    
    # Head
    Paint circle (mm): "{0.9, 0.8, 0.7}", 0, 0, 6
    
    # Ears
    Paint circle (mm): "{0.8, 0.7, 0.6}", -0.25, 0, 2
    Paint circle (mm): "{0.8, 0.7, 0.6}", 0.25, 0, 2
    
    # Sound source position
    srcX = pan_position * 1.0
    srcY = 0.6
    
    # Color based on position
    if pan_position < 0
        srcColor$ = "{0.3, 0.5, 0.8}"
    elsif pan_position > 0
        srcColor$ = "{0.8, 0.5, 0.3}"
    else
        srcColor$ = "{0.5, 0.7, 0.5}"
    endif
    
    Paint circle (mm): srcColor$, srcX, srcY, 5
    Font size: 6
    Colour: "Black"
    Text: srcX, "centre", srcY + 0.2, "half", "SRC"
    
    # Draw lines to ears
    Line width: 1
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: srcX, srcY, -0.25, 0
    Colour: "{0.8, 0.5, 0.3}"
    Draw line: srcX, srcY, 0.25, 0
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Spatial Position"
    
    # Parameter display
    Select outer viewport: 5.2, 9.5, 0.8, 4.0
    Select inner viewport: 5.5, 9.2, 1.1, 3.7
    
    Axes: 0, 1, 0, 6
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 6
    
    Font size: 8
    Colour: "Black"
    
    # Pan position bar
    Text: 0.05, "left", 5.5, "half", "Pan:"
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.25, 0.95, 5.3, 5.7
    panBarX = 0.25 + (pan_position + 1) / 2 * 0.7
    Paint circle (mm): "{0.3, 0.6, 0.8}", panBarX, 5.5, 3
    
    # ILD
    Text: 0.05, "left", 4.5, "half", "ILD:"
    ildWidth = absPan * 0.7
    Paint rectangle: "{0.5, 0.7, 0.5}", 0.25, 0.25 + ildWidth, 4.3, 4.7
    Text: 0.97, "right", 4.5, "half", fixed$(absPan * iLD_max_dB, 1) + " dB"
    
    # ITD
    Text: 0.05, "left", 3.5, "half", "ITD:"
    if use_ITD
        itdWidth = (itd / (max_ITD_ms / 1000)) * 0.7
        Paint rectangle: "{0.7, 0.5, 0.5}", 0.25, 0.25 + itdWidth, 3.3, 3.7
        Text: 0.97, "right", 3.5, "half", fixed$(itd * 1000, 2) + " ms"
    else
        Colour: "{0.6, 0.6, 0.6}"
        Text: 0.6, "centre", 3.5, "half", "OFF"
        Colour: "Black"
    endif
    
    # Spectral
    Text: 0.05, "left", 2.5, "half", "Shadow:"
    if use_spectral_cues
        shadowWidth = absPan * 0.5 * 0.7
        Paint rectangle: "{0.5, 0.5, 0.7}", 0.25, 0.25 + shadowWidth, 2.3, 2.7
        Text: 0.97, "right", 2.5, "half", "ON"
    else
        Colour: "{0.6, 0.6, 0.6}"
        Text: 0.6, "centre", 2.5, "half", "OFF"
        Colour: "Black"
    endif
    
    # Distance
    Text: 0.05, "left", 1.5, "half", "Dist:"
    if use_distance
        distWidth = distFactor * 0.7
        Paint rectangle: "{0.6, 0.6, 0.5}", 0.25, 0.25 + distWidth, 1.3, 1.7
        Text: 0.97, "right", 1.5, "half", fixed$(distance_meters, 1) + " m"
    else
        Colour: "{0.6, 0.6, 0.6}"
        Text: 0.6, "centre", 1.5, "half", "OFF"
        Colour: "Black"
    endif
    
    # Gains
    Text: 0.05, "left", 0.5, "half", "Gain:"
    Font size: 7
    Text: 0.35, "left", 0.5, "half", "L:" + fixed$(gain[1], 2)
    Text: 0.65, "left", 0.5, "half", "R:" + fixed$(gain[2], 2)
    
    Draw inner box
    Font size: 8
    Text top: "no", "Parameters"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 4.2, 6.0
    Select inner viewport: 1.0, 9.0, 4.4, 5.8
    selectObject: stereo
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "L gain: ", fixed$(gain[1], 3)
appendInfoLine: "R gain: ", fixed$(gain[2], 3)

if play_result
    selectObject: stereo
    Play
endif

selectObject: stereo