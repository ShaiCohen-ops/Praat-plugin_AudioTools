# ============================================================
# Praat AudioTools - Stretch_Tremolo_Ambience.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stretch-Tremolo Ambience - creates ambient pad/drone textures
#   from any audio. Time-stretches the source to create a smooth
#   "cloud" layer, applies tremolo modulation for breathing/pulsing
#   effect, then mixes with the original dry signal.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax
#   - Fixed object references (use IDs)
#   - Removed rename hack
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
sr = Get sampling frequency

# === Form ===
form Stretch-Tremolo Ambience
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Ethereal Pad (Smooth)
        option Ghostly Trail (Slow pulse)
        option Dark Drone (Deep stretch)
        option Shimmering Tail (Fast wobble)
    
    comment === Stretch Parameters ===
    positive Stretch_factor 3.0
    comment (Higher = smoother, longer texture)
    
    comment === Cloud Modulation ===
    positive Cloud_Rate_Hz 2.0
    positive Cloud_Depth 0.5
    comment (0 = no tremolo, 1 = full tremolo)
    
    comment === Mix ===
    positive Dry_Mix 1.0
    positive Wet_Cloud_Mix 0.6
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Ethereal Pad
    stretch_factor = 4.0
    cloud_Rate_Hz = 0.5
    cloud_Depth = 0.3
    wet_Cloud_Mix = 0.5
    presetName$ = "Ethereal"
elsif preset = 3
    # Ghostly Trail
    stretch_factor = 2.5
    cloud_Rate_Hz = 4.0
    cloud_Depth = 0.6
    wet_Cloud_Mix = 0.4
    presetName$ = "Ghostly"
elsif preset = 4
    # Dark Drone
    stretch_factor = 8.0
    cloud_Rate_Hz = 0.2
    cloud_Depth = 0.2
    wet_Cloud_Mix = 0.7
    presetName$ = "Drone"
elsif preset = 5
    # Shimmering Tail
    stretch_factor = 3.0
    cloud_Rate_Hz = 6.0
    cloud_Depth = 0.5
    wet_Cloud_Mix = 0.4
    presetName$ = "Shimmer"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Stretch-Tremolo Ambience ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Stretch factor: ", stretch_factor, "x"
appendInfoLine: "Cloud rate: ", cloud_Rate_Hz, " Hz"
appendInfoLine: "Cloud depth: ", cloud_Depth
appendInfoLine: "Dry mix: ", dry_Mix
appendInfoLine: "Wet mix: ", wet_Cloud_Mix
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

# 1. Create the Cloud Layer (time-stretch)
appendInfoLine: "Creating cloud layer (", stretch_factor, "x stretch)..."

selectObject: original
Convert to mono
monoTemp = selected("Sound")

Lengthen (overlap-add): 75, 600, stretch_factor
stretchedCloud = selected("Sound")

removeObject: monoTemp

# 2. Apply Tremolo Modulation to Cloud
appendInfoLine: "Applying tremolo modulation..."

selectObject: stretchedCloud
Formula: ~ self * (1 - cloud_Depth * (1 + sin(2 * pi * cloud_Rate_Hz * x)) / 2)

# 3. Crop Cloud to original duration
selectObject: stretchedCloud
Extract part: 0, duration, "rectangular", 1, "no"
cloudFinal = selected("Sound")

removeObject: stretchedCloud

# 4. Mix Original + Cloud
appendInfoLine: "Mixing dry + wet..."

selectObject: original
Copy: original_name$ + "_ambient_" + presetName$
result = selected("Sound")

# Apply mix formula using object ID reference
Formula: ~ self * dry_Mix + object[cloudFinal, col] * wet_Cloud_Mix

# Scale output
selectObject: result
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stretch-Tremolo Ambience: " + original_name$ + " (" + presetName$ + ")"
    
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
    
    # Cloud layer
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: cloudFinal
    Colour: "{0.5, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Cloud"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.6, 3.5
    Select inner viewport: 0.6, 7.6, 2.7, 3.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Mixed"
    Text bottom: "yes", "Time (s)"
    
    # Tremolo LFO visualization
    Select outer viewport: 0, 8, 3.7, 4.7
    Select inner viewport: 0.6, 7.6, 3.8, 4.6
    
    modDisplayDur = min(2, duration)
    
    Axes: 0, modDisplayDur, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, 0, 1.2
    
    # Draw tremolo envelope
    Colour: "{0.5, 0.6, 0.8}"
    Line width: 1.5
    nPoints = 200
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * modDisplayDur
        t2 = (p - 1) / nPoints * modDisplayDur
        amp1 = 1 - cloud_Depth * (1 + sin(2 * pi * cloud_Rate_Hz * t1)) / 2
        amp2 = 1 - cloud_Depth * (1 + sin(2 * pi * cloud_Rate_Hz * t2)) / 2
        Draw line: t1, amp1, t2, amp2
    endfor
    Line width: 1
    
    # Unity line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 1, modDisplayDur, 1
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Tremolo"
    Text bottom: "yes", "Time (s)"
    
    # Signal flow diagram
    Select outer viewport: 0, 8, 4.9, 5.6
    Select inner viewport: 0.6, 7.6, 5.0, 5.5
    
    Axes: 0, 10, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 2
    
    Font size: 5
    
    # Original box
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.2, 1.2, 0.6, 1.4
    Colour: "Black"
    Text: 0.7, "centre", 1, "half", "Input"
    
    # Split arrow
    Draw arrow: 1.2, 1, 1.8, 1.5
    Draw arrow: 1.2, 1, 1.8, 0.5
    
    # Dry path
    Colour: "{0.6, 0.6, 0.6}"
    Text: 2.5, "centre", 1.5, "half", "Dry"
    Draw arrow: 3, 1.5, 6.8, 1.2
    
    # Wet path
    Paint rectangle: "{0.6, 0.7, 0.8}", 2, 3.2, 0.2, 0.8
    Colour: "Black"
    Text: 2.6, "centre", 0.5, "half", "Stretch"
    
    Draw arrow: 3.2, 0.5, 3.8, 0.5
    
    Paint rectangle: "{0.5, 0.6, 0.8}", 3.8, 5, 0.2, 0.8
    Text: 4.4, "centre", 0.5, "half", "Tremolo"
    
    Draw arrow: 5, 0.5, 5.6, 0.5
    
    Paint rectangle: "{0.6, 0.6, 0.8}", 5.6, 6.6, 0.2, 0.8
    Text: 6.1, "centre", 0.5, "half", "Crop"
    
    Draw arrow: 6.6, 0.5, 6.8, 0.8
    
    # Mix box
    Paint rectangle: "{0.6, 0.5, 0.7}", 7, 8, 0.6, 1.4
    Text: 7.5, "centre", 1, "half", "Mix"
    
    # Output
    Draw arrow: 8, 1, 8.6, 1
    Paint rectangle: "{0.5, 0.7, 0.6}", 8.6, 9.6, 0.6, 1.4
    Text: 9.1, "centre", 1, "half", "Output"
    
    Colour: "Black"
    Draw inner box
    
    # Stats
    Select outer viewport: 0, 8, 5.7, 6.0
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Stretch: " + fixed$(stretch_factor, 1) + "x | Rate: " + fixed$(cloud_Rate_Hz, 1) + " Hz | Depth: " + fixed$(cloud_Depth * 100, 0) + "% | Dry: " + fixed$(dry_Mix, 1) + " | Wet: " + fixed$(wet_Cloud_Mix, 1)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: cloudFinal

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