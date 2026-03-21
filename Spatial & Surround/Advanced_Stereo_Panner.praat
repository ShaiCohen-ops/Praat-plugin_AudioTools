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

# Build cue summary string for visualization
filterCues$ = "ILD"
if use_ITD
    filterCues$ = filterCues$ + " + ITD"
endif
if use_spectral_cues
    filterCues$ = filterCues$ + " + Shadow"
endif
if use_distance
    filterCues$ = filterCues$ + " + Dist"
endif

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.80
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Advanced Stereo Panner##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.10, "half",
        ... name$ + "  |  " + presetName$
        ... + "  |  pan=" + fixed$(pan_position, 2)

    # ----------------------------------------------------------
    # Spatial diagram (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.55, 3.55
    Select inner viewport: 0.55, 3.95, 0.70, 3.40

    Axes: -1.6, 1.6, -0.5, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -0.5, 1.2

    # Speakers
    Paint circle (mm): "{0.40, 0.40, 0.40}", -1.2, 0.85, 3.5
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Text: -1.2, "centre", 1.05, "half", "L"

    Paint circle (mm): "{0.40, 0.40, 0.40}", 1.2, 0.85, 3.5
    Text: 1.2, "centre", 1.05, "half", "R"

    # Head (centre)
    Paint circle (mm): "{0.88, 0.80, 0.70}", 0, 0, 5
    Font size: 5
    Colour: "{0.55, 0.45, 0.35}"
    Text: 0, "centre", -0.20, "half", "head"

    # Ears
    Paint circle (mm): "{0.78, 0.68, 0.58}", -0.28, 0.02, 1.8
    Paint circle (mm): "{0.78, 0.68, 0.58}", 0.28, 0.02, 1.8

    # Sound source
    srcX = pan_position * 1.1
    srcY = 0.70
    if pan_position < 0
        srcColor$ = "{0.25, 0.50, 0.82}"
    elsif pan_position > 0
        srcColor$ = "{0.82, 0.45, 0.25}"
    else
        srcColor$ = "{0.45, 0.70, 0.45}"
    endif
    Paint circle (mm): srcColor$, srcX, srcY, 4.5
    Font size: 6
    Colour: "Black"
    Text: srcX, "centre", srcY - 0.18, "half", "SRC"

    # Lines to ears
    Line width: 1
    Colour: "{0.30, 0.50, 0.80}"
    Dotted line
    Draw line: srcX, srcY, -0.28, 0.02
    Colour: "{0.80, 0.50, 0.30}"
    Draw line: srcX, srcY, 0.28, 0.02
    Solid line

    # Centre reference
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, -0.35, 0, 1.10
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Spatial position"

    # ----------------------------------------------------------
    # Parameter bars (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.55, 3.55
    Select inner viewport: 4.50, 7.70, 0.70, 3.40

    Axes: 0, 1, 0, 6.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 6.5

    Font size: 7
    Colour: "Black"
    barL = 0.28
    barR = 0.85

    # --- Pan position bar ---
    Text: 0.03, "left", 6.0, "half", "Pan"
    Paint rectangle: "{0.82, 0.82, 0.82}", barL, barR, 5.75, 6.25
    panBarX = barL + (pan_position + 1.0) / 2.0 * (barR - barL)
    Paint circle (mm): srcColor$, panBarX, 6.0, 2.5
    # Centre tick
    Colour: "{0.65, 0.65, 0.65}"
    Draw line: (barL + barR) / 2, 5.75, (barL + barR) / 2, 6.25
    Colour: "Black"
    Font size: 6
    Text: 0.88, "left", 6.0, "half", fixed$(pan_position, 2)

    # --- ILD bar ---
    Font size: 7
    Text: 0.03, "left", 5.0, "half", "ILD"
    ildFrac = absPan
    Paint rectangle: "{0.50, 0.72, 0.50}", barL, barL + ildFrac * (barR - barL), 4.75, 5.25
    Font size: 6
    Text: 0.88, "left", 5.0, "half", fixed$(absPan * iLD_max_dB, 1) + " dB"

    # --- ITD bar ---
    Font size: 7
    Text: 0.03, "left", 4.0, "half", "ITD"
    if use_ITD
        itdFrac = itd / (max_ITD_ms / 1000)
        Paint rectangle: "{0.72, 0.50, 0.50}", barL, barL + itdFrac * (barR - barL), 3.75, 4.25
        Font size: 6
        Text: 0.88, "left", 4.0, "half", fixed$(itd * 1000, 2) + " ms"
    else
        Colour: "{0.65, 0.65, 0.65}"
        Font size: 6
        Text: 0.55, "centre", 4.0, "half", "OFF"
        Colour: "Black"
    endif

    # --- Spectral cues bar ---
    Font size: 7
    Text: 0.03, "left", 3.0, "half", "Shadow"
    if use_spectral_cues
        shadowFrac = absPan * 0.5
        Paint rectangle: "{0.50, 0.50, 0.72}", barL, barL + shadowFrac * (barR - barL), 2.75, 3.25
        Font size: 6
        Text: 0.88, "left", 3.0, "half", "ON"
    else
        Colour: "{0.65, 0.65, 0.65}"
        Font size: 6
        Text: 0.55, "centre", 3.0, "half", "OFF"
        Colour: "Black"
    endif

    # --- Distance bar ---
    Font size: 7
    Text: 0.03, "left", 2.0, "half", "Dist"
    if use_distance
        Paint rectangle: "{0.62, 0.62, 0.50}", barL, barL + distFactor * (barR - barL), 1.75, 2.25
        Font size: 6
        Text: 0.88, "left", 2.0, "half", fixed$(distance_meters, 1) + " m"
    else
        Colour: "{0.65, 0.65, 0.65}"
        Font size: 6
        Text: 0.55, "centre", 2.0, "half", "OFF"
        Colour: "Black"
    endif

    # --- Gain display ---
    Font size: 7
    Colour: "Black"
    Text: 0.03, "left", 1.0, "half", "Gain"
    Font size: 6
    Colour: "{0.25, 0.50, 0.82}"
    Text: barL, "left", 1.0, "half", "L=" + fixed$(gain[1], 3)
    Colour: "{0.82, 0.45, 0.25}"
    Text: 0.58, "left", 1.0, "half", "R=" + fixed$(gain[2], 3)

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Parameters"

    # ----------------------------------------------------------
    # Output waveform (L and R separately)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.65, 4.75
    Select inner viewport: 0.55, 7.70, 3.72, 4.68

    selectObject: stereo
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    ampMax = resPeak * 1.15
    Axes: 0, duration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, duration, 0

    # L channel (blue)
    selectObject: stereo
    Extract one channel: 1
    vizL = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

    # R channel (orange, overlay)
    selectObject: stereo
    Extract one channel: 2
    vizR = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizL, vizR

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Stereo output  (blue=L  orange=R)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Summary bar
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.85, 5.55
    Select inner viewport: 0.55, 7.70, 4.90, 5.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetName$ + "##  "
        ... + filterCues$
    Text: 0.02, "left", 0.28, "half",
        ... "Pan=" + fixed$(pan_position, 2)
        ... + "  ILD=±" + fixed$(absPan * iLD_max_dB, 1) + "dB"
        ... + "  ITD=" + fixed$(itd * 1000, 2) + "ms"
        ... + "  Dist=" + fixed$(distance_meters, 1) + "m"
        ... + "  GainL=" + fixed$(gain[1], 3)
        ... + "  GainR=" + fixed$(gain[2], 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
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