# ============================================================
# Praat AudioTools - Exponential_Glide_Up.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Exponential Pitch Glide - creates smooth pitch rises or
#   falls using exponential curves. Steepness controls how
#   quickly the pitch change occurs.
#
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Preserves the original pitch contour: the exponential curve is now a
#     time-varying transposition of the detected source F0, not a replacement
#     contour built around one median pitch.
#   - Preserves the original channel count. Pitch is analysed once from a
#     mono reference, then the same target PitchTier is resynthesized
#     independently on every source channel and rebuilt in channel order.
#   - Uses a fixed 100-Hz glide control rate independent of file duration.
#   - Curve_steepness can be 0 for a truly linear glide.
#   - Adds validation for analysis range and negative steepness.
#   - Stops clearly when no usable pitch is detected instead of inventing
#     a 200-Hz fallback.
#   - Target pitch is limited only by a sampling-safe 20 Hz..0.45*SR range;
#     the number of limited points is reported.
#   - Visualization decimation now always includes the exact endpoint.
#   - Final peak handling is attenuation-only; quiet outputs are not boosted.
# Changelog v0.2:
#   - Modern syntax
#   - Added glide direction (up/down)
#   - Added visualization
#   - Fixed input check
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
fs = Get sampling frequency
nChannels = Get number of channels

# === Form ===
form Exponential Pitch Glide v0.4.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Glide Up
        option Moderate Rise
        option Dramatic Sweep Up
        option Extreme Rocket
        option Slow Build
        option Quick Jump
        option Cinematic Rise
        option Gentle Glide Down
        option Dramatic Fall
        option Dive Bomb
    
    comment === Glide Parameters ===
    optionmenu Direction 1
        option Up
        option Down
    positive Semitones_change 7
    real Curve_steepness 3
    comment (higher = faster initial change)
    
    comment === Pitch Analysis ===
    positive Time_step 0.005
    positive Minimum_pitch 50
    positive Maximum_pitch 900
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Glide Up
    direction = 1
    semitones_change = 5
    curve_steepness = 2
elsif preset = 3
    # Moderate Rise
    direction = 1
    semitones_change = 8
    curve_steepness = 3
elsif preset = 4
    # Dramatic Sweep Up
    direction = 1
    semitones_change = 12
    curve_steepness = 4
elsif preset = 5
    # Extreme Rocket
    direction = 1
    semitones_change = 24
    curve_steepness = 6
elsif preset = 6
    # Slow Build
    direction = 1
    semitones_change = 6
    curve_steepness = 1
elsif preset = 7
    # Quick Jump
    direction = 1
    semitones_change = 4
    curve_steepness = 8
elsif preset = 8
    # Cinematic Rise
    direction = 1
    semitones_change = 18
    curve_steepness = 2.5
elsif preset = 9
    # Gentle Glide Down
    direction = 2
    semitones_change = 5
    curve_steepness = 2
elsif preset = 10
    # Dramatic Fall
    direction = 2
    semitones_change = 12
    curve_steepness = 4
elsif preset = 11
    # Dive Bomb
    direction = 2
    semitones_change = 24
    curve_steepness = 6
endif

# === Validate Parameters ===
if curve_steepness < 0
    exitScript: "Curve_steepness must be zero or greater."
endif
if minimum_pitch >= maximum_pitch
    exitScript: "Minimum_pitch must be lower than Maximum_pitch."
endif
if maximum_pitch >= fs / 2
    exitScript: "Maximum_pitch must be below the Nyquist frequency (" + fixed$(fs / 2, 1) + " Hz)."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "Gentle Up"
elsif preset = 3
    presetName$ = "Moderate Rise"
elsif preset = 4
    presetName$ = "Dramatic Sweep"
elsif preset = 5
    presetName$ = "Extreme Rocket"
elsif preset = 6
    presetName$ = "Slow Build"
elsif preset = 7
    presetName$ = "Quick Jump"
elsif preset = 8
    presetName$ = "Cinematic Rise"
elsif preset = 9
    presetName$ = "Gentle Down"
elsif preset = 10
    presetName$ = "Dramatic Fall"
else
    presetName$ = "Dive Bomb"
endif

if direction = 1
    dirName$ = "Up"
    signMultiplier = 1
else
    dirName$ = "Down"
    signMultiplier = -1
endif

# === Info ===
writeInfoLine: "=== Exponential Pitch Glide ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Direction: ", dirName$
appendInfoLine: "Semitones: ", semitones_change
appendInfoLine: "Steepness: ", curve_steepness
appendInfoLine: "Channels preserved: ", nChannels
appendInfoLine: ""

# === Fixed Glide Control Grid ===
control_step = 0.01
npoints = ceiling(dur / control_step) + 1
if npoints < 2
    npoints = 2
endif

# === Create Mono Pitch-Analysis Reference ===
selectObject: original
if nChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: originalName$ + "_glide_analysis"
endif

selectObject: analysisMono
analysisPitch = To Pitch: time_step, minimum_pitch, maximum_pitch

selectObject: analysisPitch
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"
if median_f0 = undefined
    removeObject: analysisPitch, analysisMono
    exitScript: "No usable pitch was detected in the selected Sound." + newline$
        ... + "Exponential Pitch Glide requires voiced / periodic material."
endif

appendInfoLine: "Median detected pitch: ", fixed$(median_f0, 1), " Hz"

# === Create Pitch Tier ===
appendInfoLine: ""
appendInfoLine: "Building glide curve..."

Create PitchTier: "glide_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)

# === Build Exponential Glide Curve ===
voiced_points = 0
limited_points = 0
targetMinHz = 20
targetMaxHz = 0.45 * fs

for i from 0 to npoints - 1
    # Fixed 10-ms control grid, exact endpoint on the final iteration.
    if i = npoints - 1
        t = xmax
        u = 1
    else
        t = min(xmax, xmin + i * control_step)
        u = (t - xmin) / dur
    endif

    # Exponential curve normalized exactly 0..1.
    if curve_steepness > 0.001
        expFactor = (1 - exp(-curve_steepness * u)) / (1 - exp(-curve_steepness))
    else
        expFactor = u
    endif

    semitones_shift = signMultiplier * semitones_change * expFactor

    # Deterministic visualization decimation; both first and last samples
    # map exactly to the first/last visualization slots.
    if maxVizPoints = 1
        vizIdx = 1
    else
        vizIdx = floor(i * (maxVizPoints - 1) / (npoints - 1)) + 1
    endif
    if vizIdx < 1
        vizIdx = 1
    elsif vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif

    if vizFilled#[vizIdx] = 0 or i = npoints - 1
        vizTimes#[vizIdx] = t
        vizShifts#[vizIdx] = semitones_shift
        vizFilled#[vizIdx] = 1
    endif

    # Apply the glide as a transposition of the ORIGINAL detected F0.
    selectObject: analysisPitch
    source_f0 = Get value at time: t, "Hertz", "Linear"

    if source_f0 <> undefined and source_f0 > 0
        new_f0 = source_f0 * (2 ^ (semitones_shift / 12))

        if new_f0 < targetMinHz
            new_f0 = targetMinHz
            limited_points += 1
        elsif new_f0 > targetMaxHz
            new_f0 = targetMaxHz
            limited_points += 1
        endif

        selectObject: pitchTier
        Add point: t, new_f0
        voiced_points += 1
    endif
endfor

if voiced_points = 0
    removeObject: pitchTier, analysisPitch, analysisMono
    exitScript: "Pitch analysis produced no usable glide control points."
endif

appendInfoLine: "Pitch control points: ", voiced_points
if limited_points > 0
    appendInfoLine: "Sampling-safe target limits applied: ", limited_points, " point(s)"
endif

# === Resynthesize Every Source Channel with the Same Target PitchTier ===
appendInfoLine: "Resynthesizing ", nChannels, " channel(s)..."

# Build the final N-channel container in the source time domain and sample rate.
result = Create Sound from formula: originalName$ + "_glide" + dirName$, nChannels, xmin, xmax, fs, "0"

for ch from 1 to nChannels
    selectObject: original
    if nChannels = 1
        channelWork = Copy: originalName$ + "_glide_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: originalName$ + "_glide_ch" + string$(ch)
    endif

    selectObject: channelWork
    channelManip = To Manipulation: time_step, minimum_pitch, maximum_pitch

    selectObject: pitchTier
    plusObject: channelManip
    Replace pitch tier

    selectObject: channelManip
    channelRes = Get resynthesis (overlap-add)

    # Copy the mono resynthesis into its matching output channel.
    selectObject: result
    Formula (part): xmin, xmax, ch, ch, "object['channelRes:0', 1, col]"

    removeObject: channelManip, channelWork, channelRes
endfor

# Analysis/control objects are no longer needed.
removeObject: analysisPitch, analysisMono, pitchTier

# Attenuation-only peak safety.
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Exponential Pitch Glide v0.4.1##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + presetName$ + " | " + dirName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.6, 7.6, 0.7, 1.6
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.8, 2.9
    Select inner viewport: 0.6, 7.6, 1.9, 2.8
    selectObject: result
    if direction = 1
        Colour: "{0.5, 0.7, 0.6}"
    else
        Colour: "{0.7, 0.5, 0.6}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Glide " + dirName$
    Text bottom: "yes", "Time (s)"
    
    # Glide curve
    Select outer viewport: 0, 8, 3.1, 4.7
    Select inner viewport: 0.6, 7.6, 3.3, 4.6
    
    # Determine range
    if direction = 1
        minShift = -1
        maxShift = semitones_change + 1
    else
        minShift = -semitones_change - 1
        maxShift = 1
    endif
    
    Axes: xmin, xmax, minShift, maxShift
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minShift, maxShift
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Draw glide curve
    if direction = 1
        Colour: "{0.4, 0.7, 0.5}"
    else
        Colour: "{0.7, 0.4, 0.5}"
    endif
    Line width: 2
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    # End point marker
    Paint circle (mm): "Black", xmax, signMultiplier * semitones_change, 1.5
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Semitones"
    Text bottom: "yes", "Time (s)"
    
    # Curve shape comparison (different steepness)
    Select outer viewport: 0, 8, 4.9, 5.3
    Select inner viewport: 0.6, 7.6, 5.0, 5.25
    
    Axes: 0, 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1.1
    
    # Draw curves for different steepness values
    steepVals# = {1, 3, 6}
    steepColors$# = {"{0.7, 0.7, 0.7}", "{0.5, 0.5, 0.5}", "{0.3, 0.3, 0.3}"}
    
    for sv to 3
        steep = steepVals#[sv]
        Colour: steepColors$#[sv]
        
        prevX = 0
        prevY = 0
        for pt from 1 to 50
            px = (pt - 1) / 49
            if steep > 0.001
                py = (1 - exp(-steep * px)) / (1 - exp(-steep))
            else
                py = px
            endif
            
            if pt > 1
                Draw line: prevX, prevY, px, py
            endif
            prevX = px
            prevY = py
        endfor
    endfor
    
    # Mark current steepness
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 2
    prevX = 0
    prevY = 0
    for pt from 1 to 50
        px = (pt - 1) / 49
        if curve_steepness > 0.001
            py = (1 - exp(-curve_steepness * px)) / (1 - exp(-curve_steepness))
        else
            py = px
        endif
        
        if pt > 1
            Draw line: prevX, prevY, px, py
        endif
        prevX = px
        prevY = py
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Shape"
    Text bottom: "yes", "Steepness: 1 (gray) → 6 (black), current=" + fixed$(curve_steepness, 1) + " (red)"
    
    Font size: 10
    Colour: "Black"

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.50, 6.06
    Select inner viewport: 0.60, 7.70, 5.50 + 0.04, 6.06 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Exponential glide law • pitch trajectory • rendered output"
    Text: 0.02, "left", 0.20, "half", "Exponential Glide • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.16
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Nominal final shift: ", signMultiplier * semitones_change, " semitones"
appendInfoLine: "Output channels: ", nChannels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
