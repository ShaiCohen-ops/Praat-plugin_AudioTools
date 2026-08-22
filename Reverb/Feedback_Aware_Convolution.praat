# ============================================================
# Praat AudioTools - Feedback_Aware_Convolution.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Feedback-Aware Convolution - self-referential convolution
#   that analyzes the input signal (intensity or pitch) and
#   generates an impulse train at detected threshold crossings.
#   The sound is then convolved with its own event-driven IR,
#   creating feedback-like textures without actual feedback.
#   Intensity mode triggers at loud moments; pitch mode at
#   melodic/harmonic moments.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection syntax
#   - Fixed formula syntax
#   - Added presets
#   - Added wet/dry mix control
#   - Added visualization
#   - Removed goto statement
#
# Changelog v0.4:
#   - Public form/defaults, output naming, and final selection are unchanged.
#   - Added a private zero-based work copy so non-zero source xmin cannot
#     break pitch scanning or convolution/trim timing.
#   - Fixed 3+ channel input: every detected impulse is now written to every
#     channel of the event-driven IR. Mono/stereo behaviour is unchanged.
#   - Custom pitch-floor/ceiling values are ordered internally and equal
#     bounds are separated safely before To Pitch.
#   - Extremely short Custom impulses are clamped to a few samples so an
#     event cannot disappear because its Formula(part) window hits no samples.
#   - Safe final Scale peak skips digital silence while preserving the
#     original non-silent normalization behaviour.
#   - Private work objects are cleaned on both success and no-event exit.
#
# Changelog v0.3:
#   - Fixed visualization: title and parameter line were centred against a
#     stale (seconds) world window and spilled off the left edge; now pinned
#     to a 0..1 axis.
#   - Result now matches the input length exactly (Extract part overshot by one
#     sample). Wet/dry is built on the original's grid and references the wet
#     signal per-channel via object[id, row, col].
# ============================================================

form Feedback-Aware Convolution
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Sparse Intensity
        option Dense Intensity
        option Melodic Pitch
        option Rhythmic Events
    
    comment === Parameter Type ===
    optionmenu Parameter_type 1
        option Intensity
        option Pitch
    
    comment === Detection ===
    positive Detection_threshold 70
    comment (Intensity: dB, Pitch: Hz)
    positive Minimum_spacing_s 0.05
    comment (Refractory period between impulses)
    
    comment === Pitch Settings (ignored in Intensity mode) ===
    positive Pitch_floor_Hz 80
    positive Pitch_ceiling_Hz 600
    
    comment === Impulse Characteristics ===
    positive Impulse_duration_s 0.0003
    positive Amplitude_mapping 1.0
    comment (0.5=subtle, 1.0=normal, 2.0=intense)
    
    comment === Mix ===
    real Wet_dry_percent 50
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# Private zero-based processing copy; caller's original Sound is untouched.
selectObject: original
workSource = Copy: "feedback_aware_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 2
    # Sparse Intensity
    parameter_type = 1
    detection_threshold = 75
    minimum_spacing_s = 0.08
    impulse_duration_s = 0.0005
    amplitude_mapping = 0.8
    presetName$ = "SparseInt"
elsif preset = 3
    # Dense Intensity
    parameter_type = 1
    detection_threshold = 60
    minimum_spacing_s = 0.03
    impulse_duration_s = 0.0003
    amplitude_mapping = 1.2
    presetName$ = "DenseInt"
elsif preset = 4
    # Melodic Pitch
    parameter_type = 2
    detection_threshold = 150
    minimum_spacing_s = 0.05
    pitch_floor_Hz = 80
    pitch_ceiling_Hz = 600
    impulse_duration_s = 0.0004
    amplitude_mapping = 1.0
    presetName$ = "Melodic"
elsif preset = 5
    # Rhythmic Events
    parameter_type = 1
    detection_threshold = 72
    minimum_spacing_s = 0.04
    impulse_duration_s = 0.0002
    amplitude_mapping = 1.5
    presetName$ = "Rhythmic"
else
    presetName$ = "Custom"
endif

# Internal guards; built-in presets are already within these limits.
if pitch_floor_Hz > pitch_ceiling_Hz
    tmpPitch = pitch_floor_Hz
    pitch_floor_Hz = pitch_ceiling_Hz
    pitch_ceiling_Hz = tmpPitch
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    pitch_ceiling_Hz = pitch_floor_Hz + 1
endif

effectiveImpulseDuration = max(impulse_duration_s, 3 / sr)

# Get parameter type string
if parameter_type = 1
    paramType$ = "intensity"
else
    paramType$ = "pitch"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# === Info ===
writeInfoLine: "=== Feedback-Aware Convolution ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Parameter: ", paramType$
appendInfoLine: "Threshold: ", detection_threshold, if paramType$ = "intensity" then " dB" else " Hz" fi
appendInfoLine: "Min spacing: ", minimum_spacing_s, " s"
appendInfoLine: "Impulse duration: ", effectiveImpulseDuration * 1000, " ms"
appendInfoLine: "Amplitude mapping: ", amplitude_mapping
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# STEP 1: EXTRACT PARAMETER
# ============================================================

appendInfoLine: "Step 1/4: Extracting ", paramType$, "..."

if paramType$ = "intensity"
    selectObject: workSource
    To Intensity: 75, 0.001, "yes"
    intensityObj = selected("Intensity")
    
    Down to IntensityTier
    paramTier = selected("IntensityTier")
    
    removeObject: intensityObj
    
else
    # Pitch mode
    appendInfoLine: "  Pitch range: ", pitch_floor_Hz, "-", pitch_ceiling_Hz, " Hz"
    
    selectObject: workSource
    To Pitch: 0.001, pitch_floor_Hz, pitch_ceiling_Hz
    pitchObj = selected("Pitch")
endif

# ============================================================
# STEP 2: DETECT THRESHOLD CROSSINGS
# ============================================================

appendInfoLine: "Step 2/4: Detecting threshold crossings..."

max_impulses = 10000
impulse_count = 0
reachedMax = 0

if paramType$ = "intensity"
    selectObject: paramTier
    num_points = Get number of points
    
    last_impulse_time = -1
    
    for i from 1 to num_points
        if reachedMax = 0
            selectObject: paramTier
            time = Get time from index: i
            value = Get value at index: i
            
            if value > detection_threshold and (time - last_impulse_time) >= minimum_spacing_s
                impulse_count = impulse_count + 1
                impulseTime[impulse_count] = time
                impulseValue[impulse_count] = value
                last_impulse_time = time
                
                if impulse_count >= max_impulses
                    appendInfoLine: "  Warning: Max impulses reached (", max_impulses, ")"
                    reachedMax = 1
                endif
            endif
        endif
    endfor
    
else
    # Pitch mode - sample at regular intervals
    selectObject: pitchObj
    time_step = 0.001
    current_time = 0
    last_impulse_time = -1
    
    min_pitch = 10000
    max_pitch = 0
    defined_count = 0
    
    while current_time <= originalDur and reachedMax = 0
        selectObject: pitchObj
        value = Get value at time: current_time, "Hertz", "Linear"
        
        if value <> undefined
            defined_count = defined_count + 1
            
            if value < min_pitch
                min_pitch = value
            endif
            if value > max_pitch
                max_pitch = value
            endif
            
            if value > detection_threshold and (current_time - last_impulse_time) >= minimum_spacing_s
                impulse_count = impulse_count + 1
                impulseTime[impulse_count] = current_time
                impulseValue[impulse_count] = value
                last_impulse_time = current_time
                
                if impulse_count >= max_impulses
                    appendInfoLine: "  Warning: Max impulses reached"
                    reachedMax = 1
                endif
            endif
        endif
        
        current_time = current_time + time_step
    endwhile
    
    if defined_count > 0
        appendInfoLine: "  Pitch range found: ", fixed$(min_pitch, 1), "-", fixed$(max_pitch, 1), " Hz"
    endif
endif

appendInfoLine: "  Detected ", impulse_count, " impulse events"

if impulse_count = 0
    # Cleanup and exit
    if paramType$ = "intensity"
        removeObject: paramTier
    else
        removeObject: pitchObj
    endif
    removeObject: workSource
    exitScript: "No impulses detected. Try lowering the threshold."
endif

# ============================================================
# STEP 3: GENERATE IMPULSE TRAIN
# ============================================================

appendInfoLine: "Step 3/4: Generating impulse train..."

Create Sound from formula: "impulse_train", numChannels, 0, originalDur, sr, "0"
impulseTrain = selected("Sound")

# Add Gaussian impulses at detected times
for i from 1 to impulse_count
    time = impulseTime[i]
    value = impulseValue[i]
    
    # Normalize value to amplitude
    if paramType$ = "intensity"
        normalized = (value - 40) / 40
    else
        normalized = (value - detection_threshold) / detection_threshold
    endif
    
    # Clamp and apply mapping
    if normalized < 0
        normalized = 0
    elsif normalized > 1
        normalized = 1
    endif
    
    amp = normalized * amplitude_mapping
    
    # Calculate impulse window
    halfDur = effectiveImpulseDuration / 2
    impStart = time - halfDur
    impEnd = time + halfDur
    
    if impStart < 0
        impStart = 0
    endif
    if impEnd > originalDur
        impEnd = originalDur
    endif
    
    # Build formula strings
    time_str$ = string$(time)
    amp_str$ = string$(amp)
    sigma_str$ = string$(effectiveImpulseDuration / 6)
    
    # Add the same event-driven IR to every channel. This preserves the
    # v0.3 mono/stereo sound and fixes 3+ channel wet routing.
    selectObject: impulseTrain
    Formula (part): impStart, impEnd, 1, numChannels, "self + " + amp_str$ + " * exp(-((x - " + time_str$ + ") / " + sigma_str$ + ")^2)"
endfor

appendInfoLine: "  Impulse train generated"

# ============================================================
# STEP 4: CONVOLVE
# ============================================================

appendInfoLine: "Step 4/4: Convolving..."

selectObject: workSource, impulseTrain
Convolve: "sum", "zero"
wetSound = selected("Sound")

# Trim to original duration
selectObject: wetSound
Extract part: 0, originalDur, "rectangular", 1, "no"
wetTrimmed = selected("Sound")
removeObject: wetSound

# Apply wet/dry mix on the original's time grid so the result length matches
# the input exactly (Extract part can overshoot by one sample), and reference
# the wet signal per-channel.
wet_str$ = string$(wet_level)
dry_str$ = string$(dry_level)
wet_id$ = string$(wetTrimmed)

selectObject: original
Copy: "fac_mix"
result = selected("Sound")
Formula: "object[" + wet_id$ + ", row, col] * " + wet_str$ + " + self * " + dry_str$
removeObject: wetTrimmed

selectObject: result
resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > 0
    Scale peak: 0.95
endif
Rename: originalName$ + "_feedback_" + presetName$

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Feedback-Aware Convolution: " + originalName$ + " (" + presetName$ + ")" + " | v0.5.1"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.7, 1.3
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    Axes: 0, 1, 0, 1
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Result " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    
    # Impulse positions
    Select outer viewport: 0, 8, 2.5, 3.5
    Select inner viewport: 0.60, 7.70, 2.6, 3.4
    
    Axes: 0, originalDur, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, originalDur, 0, 1.2
    
    # Draw impulse markers
    Colour: "{0.6, 0.5, 0.5}"
    Line width: 1
    
    for i from 1 to impulse_count
        time = impulseTime[i]
        value = impulseValue[i]
        
        # Normalize for display
        if paramType$ = "intensity"
            normVal = (value - 40) / 50
        else
            normVal = value / (pitch_ceiling_Hz * 1.2)
        endif
        
        if normVal > 1
            normVal = 1
        endif
        if normVal < 0.1
            normVal = 0.1
        endif
        
        Draw line: time, 0, time, normVal
        Paint circle: "{0.6, 0.5, 0.5}", time, normVal, 0.008 * originalDur
    endfor
    
    # Threshold line
    Colour: "{0.8, 0.6, 0.6}"
    Dotted line
    if paramType$ = "intensity"
        threshNorm = (detection_threshold - 40) / 50
    else
        threshNorm = detection_threshold / (pitch_ceiling_Hz * 1.2)
    endif
    Draw line: 0, threshNorm, originalDur, threshNorm
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.6, 3.4
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Impulses (" + string$(impulse_count) + ")"
    Select inner viewport: 0.60, 7.70, 2.6, 3.4
    Axes: 0, originalDur, 0, 1.2
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 0, 8, 3.6, 4.0
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Mode: " + paramType$ + " | Threshold: " + string$(detection_threshold) + " | Spacing: " + fixed$(minimum_spacing_s * 1000, 0) + "ms | Impulses: " + string$(impulse_count)
    
    Font size: 10
    Colour: "Black"

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, 4.10, 5.10
    Select inner viewport: 0.60, 7.70, 4.17, 5.03
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Feedback-aware IR structure is shown before the rendered output"
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Reference path remains neutral; effect accents indicate the active feedback field"

    # Restore full-page viewport before leaving visualization.
    Select inner viewport: 0.60, 7.70, 4.17, 5.03
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 5.20
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: impulseTrain
removeObject: workSource

if paramType$ = "intensity"
    removeObject: paramTier
else
    removeObject: pitchObj
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Impulses: ", impulse_count

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
