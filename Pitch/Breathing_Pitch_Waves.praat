# ============================================================
# Praat AudioTools - Breathing_Pitch_Waves.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Breathing Pitch Waves - creates organic, breathing-like
#   pitch modulation using complex waveforms combining breath
#   fundamentals, harmonics, flutter, tremor, and gasp effects.
#   Emotional intensity builds over time.
#
# Changelog v0.3:
#   - Fixed stereo crash: To Manipulation is mono-only, so a stereo
#     input is now folded to mono before analysis/resynthesis.
#     Mono input is unchanged.
#   - Viz: title and the two end captions now set explicit Axes
#     (0,1,0,1); they were inheriting the pitch-curve panel's axes
#     and rendering off-position.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Added visualization
#   - Fixed resampled output selection
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
orig_sr = Get sampling frequency
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

# === Form ===
form Breathing Pitch Waves
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Breath
        option Emotional Swell
        option Dramatic Breath
        option Panic Breathing
        option Subtle Tremor
        option Deep Meditation
        option Intense Gasping
    
    comment === Breathing Parameters ===
    positive Breath_rate 0.3
    comment (cycles per second)
    positive Pitch_depth_semitones 18
    
    comment === Flutter & Chaos ===
    positive Micro_flutter 4
    positive Emotional_intensity 2.5
    
    comment === Pitch Analysis ===
    positive Time_step 0.005
    positive Minimum_pitch 50
    positive Maximum_pitch 900
    
    comment === Output ===
    positive Output_sample_rate 44100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Breath
    breath_rate = 0.2
    pitch_depth_semitones = 8
    micro_flutter = 1
    emotional_intensity = 1.2
elsif preset = 3
    # Emotional Swell
    breath_rate = 0.25
    pitch_depth_semitones = 15
    micro_flutter = 2
    emotional_intensity = 2.0
elsif preset = 4
    # Dramatic Breath
    breath_rate = 0.35
    pitch_depth_semitones = 24
    micro_flutter = 5
    emotional_intensity = 3.0
elsif preset = 5
    # Panic Breathing
    breath_rate = 0.8
    pitch_depth_semitones = 36
    micro_flutter = 8
    emotional_intensity = 4.0
elsif preset = 6
    # Subtle Tremor
    breath_rate = 0.15
    pitch_depth_semitones = 6
    micro_flutter = 3
    emotional_intensity = 0.8
elsif preset = 7
    # Deep Meditation
    breath_rate = 0.1
    pitch_depth_semitones = 4
    micro_flutter = 0.5
    emotional_intensity = 0.5
elsif preset = 8
    # Intense Gasping
    breath_rate = 0.5
    pitch_depth_semitones = 30
    micro_flutter = 6
    emotional_intensity = 3.5
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "Gentle Breath"
elsif preset = 3
    presetName$ = "Emotional Swell"
elsif preset = 4
    presetName$ = "Dramatic Breath"
elsif preset = 5
    presetName$ = "Panic Breathing"
elsif preset = 6
    presetName$ = "Subtle Tremor"
elsif preset = 7
    presetName$ = "Deep Meditation"
else
    presetName$ = "Intense Gasping"
endif

# === Info ===
writeInfoLine: "=== Breathing Pitch Waves ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Breath rate: ", breath_rate, " Hz"
appendInfoLine: "Pitch depth: ±", pitch_depth_semitones, " semitones"
appendInfoLine: "Flutter: ", micro_flutter
appendInfoLine: "Emotional intensity: ", emotional_intensity
appendInfoLine: ""

# === Calculate Number of Points ===
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

# === Create Working Copy and Manipulation ===
selectObject: original
Copy: originalName$ + "_breath_tmp"
tmpSound = selected("Sound")

# To Manipulation (below) is mono-only; fold a stereo copy down first.
selectObject: tmpSound
nch = Get number of channels
if nch > 1
    monoTmp = Convert to mono
    removeObject: tmpSound
    tmpSound = monoTmp
endif

selectObject: tmpSound
manipulation = To Manipulation: time_step, minimum_pitch, maximum_pitch

# === Get Median Pitch ===
selectObject: tmpSound
To Pitch: time_step, minimum_pitch, maximum_pitch
tmpPitch = selected("Pitch")
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if median_f0 = undefined
    median_f0 = 200
    appendInfoLine: "No pitch detected, using default: ", median_f0, " Hz"
else
    appendInfoLine: "Median pitch: ", fixed$(median_f0, 1), " Hz"
endif

removeObject: tmpPitch

# === Create Breathing Pitch Tier ===
appendInfoLine: ""
appendInfoLine: "Building breathing curve with ", npoints, " points..."

Create PitchTier: "breath_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store curve for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# === Build Breathing Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    
    # Breathing phase
    phase = (t - xmin) * 2 * pi * breath_rate
    
    # Complex breathing waveform
    breath_fundamental = sin(phase)^3
    breath_harmonic = 0.6 * sin(phase * 2)^5
    breath_subharmonic = 0.3 * sin(phase * 0.5)^2
    breath_curve = breath_fundamental + breath_harmonic + breath_subharmonic
    
    # Micro-flutter components
    flutter_phase = phase * 12
    chaos_phase = phase * 23.7
    flutter_component1 = sin(flutter_phase) * randomUniform(0.6, 1.4)
    flutter_component2 = 0.5 * sin(chaos_phase) * randomUniform(0.8, 1.2)
    flutter = micro_flutter * 0.15 * (flutter_component1 + flutter_component2)
    
    # Emotional tremor and gasps
    tremor = 0.8 * sin(phase * 7.3) * cos(phase * 2.1)
    gasp_trigger = sin(phase * 3)^8
    gasp = 3 * gasp_trigger * randomUniform(0.5, 1.5)
    
    # Emotional intensity envelope (builds over time)
    time_factor = (t - xmin) / dur
    intensity_envelope = 1 + emotional_intensity * time_factor^1.5
    
    # Total pitch shift in semitones
    total_shift = pitch_depth_semitones * (breath_curve + flutter + tremor + gasp) * intensity_envelope
    
    # Store for visualization
    vizIdx = floor(i / vizStep) + 1
    if vizIdx <= maxVizPoints and vizIdx >= 1
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizShifts#[vizIdx] = total_shift
        endif
    endif
    
    # Convert semitones to frequency
    ratio = 2 ^ (total_shift / 12)
    new_f0 = median_f0 * ratio
    
    # Clamp to range
    if new_f0 < minimum_pitch
        new_f0 = minimum_pitch
    elsif new_f0 > maximum_pitch
        new_f0 = maximum_pitch
    endif
    
    selectObject: pitchTier
    Add point: t, new_f0
endfor

# === Replace Pitch Tier ===
selectObject: manipulation, pitchTier
Replace pitch tier

# === Resynthesize ===
appendInfoLine: "Resynthesizing..."
selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_breathing"

# === Resample if Needed ===
selectObject: result
currentSR = Get sampling frequency
if output_sample_rate <> currentSR
    Resample: output_sample_rate, 50
    resampledResult = selected("Sound")
    removeObject: result
    result = resampledResult
    Rename: originalName$ + "_breathing"
endif

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Breathing Pitch Waves: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.6, 7.6, 0.7, 1.6
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.8, 2.9
    Select inner viewport: 0.6, 7.6, 1.9, 2.8
    selectObject: result
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Breathing"
    Text bottom: "yes", "Time (s)"
    
    # Breathing curve (pitch shift over time)
    Select outer viewport: 0, 8, 3.1, 4.7
    Select inner viewport: 0.6, 7.6, 3.3, 4.6
    
    # Find range
    minShift = vizShifts#[1]
    maxShift = vizShifts#[1]
    for vp from 2 to maxVizPoints
        if vizShifts#[vp] < minShift
            minShift = vizShifts#[vp]
        endif
        if vizShifts#[vp] > maxShift
            maxShift = vizShifts#[vp]
        endif
    endfor
    
    margin = (maxShift - minShift) * 0.1
    if margin < 1
        margin = 1
    endif
    
    Axes: xmin, xmax, minShift - margin, maxShift + margin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minShift - margin, maxShift + margin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Draw breathing curve
    Colour: "{0.4, 0.6, 0.8}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shift (st)"
    Text bottom: "yes", "Time (s)"
    
    # Breathing components illustration
    Select outer viewport: 0, 8, 4.9, 5.3
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Components: sin³(breath) + sin⁵(2×) + sin²(0.5×) + flutter + tremor + gasps × intensity_envelope"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Rate: " + fixed$(breath_rate, 2) + " Hz | Depth: ±" + string$(pitch_depth_semitones) + " st | Flutter: " + fixed$(micro_flutter, 1) + " | Intensity: " + fixed$(emotional_intensity, 1)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: tmpSound, manipulation, pitchTier

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