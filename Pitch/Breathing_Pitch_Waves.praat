# ============================================================
# Praat AudioTools - Breathing_Pitch_Waves.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4b (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Breathing Pitch Waves - creates organic, breathing-like
#   pitch modulation using complex waveforms combining breath
#   fundamentals, harmonics, flutter, tremor, and gasp effects.
#   Emotional intensity builds over time.
#
# Changelog v0.4b:
#   - Praat syntax fix: Get number of channels cannot be embedded directly
#     inside appendInfoLine. The value is queried first, then printed.
# Changelog v0.4a:
#   - Praat fix: vector arrays cannot be initialized with undefined#().
#     Visualization arrays now use zero#() plus a separate vizFilled# mask,
#     so time 0 and negative start times remain valid.
# Changelog v0.4:
#   - Preserves the original channel count. Pitch is analysed once from a
#     mono reference, then the same breathing target contour is resynthesized
#     independently on every source channel and rebuilt as N-channel output.
#   - Modulates the SOURCE pitch contour instead of replacing the whole file
#     with a contour around one median F0. Original melody/intonation is kept.
#   - Pitch_depth_semitones is now a true bounded maximum shift. The compound
#     breathing control is centred and passed through tanh(), so emotional
#     build-up increases motion without exceeding +/-Pitch_depth_semitones.
#   - Uses a fixed 100-Hz modulation control rate independent of file length;
#     visualization remains decimated separately to at most 500 points.
#   - Micro_flutter and Emotional_intensity can now be zero.
#   - Validates pitch range and modulation parameters.
#   - No-pitch material now stops with a clear message instead of inventing
#     a 200-Hz target that cannot create missing glottal pulses.
#   - Final peak handling is attenuation-only: quiet results are never boosted.
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
form Breathing Pitch Waves v0.4b
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
    real Pitch_depth_semitones 18
    
    comment === Flutter & Chaos ===
    real Micro_flutter 4
    real Emotional_intensity 2.5
    
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

# === Validate Parameters ===
if pitch_depth_semitones < 0
    pitch_depth_semitones = 0
endif
if pitch_depth_semitones > 48
    pitch_depth_semitones = 48
endif
if micro_flutter < 0
    micro_flutter = 0
endif
if micro_flutter > 20
    micro_flutter = 20
endif
if emotional_intensity < 0
    emotional_intensity = 0
endif
if emotional_intensity > 10
    emotional_intensity = 10
endif
if minimum_pitch >= maximum_pitch
    exitScript: "Minimum_pitch must be lower than Maximum_pitch."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
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

# === Modulation Control Grid ===
# Fixed 100-Hz control rate keeps flutter/chaos bandwidth consistent across
# short and long files. Visualization is decimated separately below.
control_step = 0.01
npoints = ceiling(dur / control_step) + 1
if npoints < 2
    npoints = 2
endif

# === Create Mono Pitch-Analysis Reference ===
selectObject: original
nch = Get number of channels
if nch > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: originalName$ + "_analysis_mono"
endif

selectObject: analysisMono
analysisPitch = To Pitch: time_step, minimum_pitch, maximum_pitch

# Verify that the source actually contains detected pitch.
selectObject: analysisPitch
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"
if median_f0 = undefined
    removeObject: analysisPitch, analysisMono
    exitScript: "No usable pitch was detected in the selected Sound." + newline$
        ... + "Breathing Pitch Waves requires voiced / periodic material."
endif
appendInfoLine: "Median detected pitch: ", fixed$(median_f0, 1), " Hz"
appendInfoLine: "Channels preserved: ", nch

# === Create Breathing Pitch Tier ===
appendInfoLine: ""
appendInfoLine: "Building breathing curve with ", npoints, " points..."

Create PitchTier: "breath_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store curve for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# === Build Breathing Pitch Curve ===
voiced_points = 0
for i from 0 to npoints - 1
    if i = npoints - 1
        t = xmax
    else
        t = min(xmax, xmin + i * control_step)
    endif

    # Breathing phase, local to source start time.
    phase = (t - xmin) * 2 * pi * breath_rate

    # Centred compound breathing waveform.
    breath_fundamental = sin(phase)^3
    breath_harmonic = 0.6 * sin(phase * 2)^5
    breath_subharmonic = 0.3 * (sin(phase * 0.5)^2 - 0.5)
    breath_curve = breath_fundamental + breath_harmonic + breath_subharmonic

    # Micro-flutter.
    flutter_phase = phase * 12
    chaos_phase = phase * 23.7
    flutter_component1 = sin(flutter_phase) * randomUniform(0.6, 1.4)
    flutter_component2 = 0.5 * sin(chaos_phase) * randomUniform(0.8, 1.2)
    flutter = micro_flutter * 0.15 * (flutter_component1 + flutter_component2)

    # Emotional tremor and centred gasp impulses.
    tremor = 0.8 * sin(phase * 7.3) * cos(phase * 2.1)
    gasp_trigger = sin(phase * 3)^8
    gasp = 3 * (gasp_trigger - 35/128) * randomUniform(0.5, 1.5)

    # Build-up increases drive, but tanh keeps the result within +/-1.
    time_factor = (t - xmin) / dur
    emotional_drive = 1 + emotional_intensity * time_factor^1.5
    raw_motion = breath_curve + flutter + tremor + gasp
    bounded_motion = tanh(raw_motion * emotional_drive)

    # True bounded musical depth.
    total_shift = pitch_depth_semitones * bounded_motion

    # Deterministic decimation for visualization.
    vizIdx = floor(i * maxVizPoints / npoints) + 1
    if vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif
    if vizFilled#[vizIdx] = 0
        vizTimes#[vizIdx] = t
        vizShifts#[vizIdx] = total_shift
        vizFilled#[vizIdx] = 1
    endif

    # Modulate the ORIGINAL pitch contour.
    selectObject: analysisPitch
    source_f0 = Get value at time: t, "Hertz", "Linear"
    if source_f0 <> undefined and source_f0 > 0
        ratio = 2 ^ (total_shift / 12)
        new_f0 = source_f0 * ratio

        if new_f0 < minimum_pitch
            new_f0 = minimum_pitch
        elsif new_f0 > maximum_pitch
            new_f0 = maximum_pitch
        endif

        selectObject: pitchTier
        Add point: t, new_f0
        voiced_points = voiced_points + 1
    endif
endfor

if voiced_points = 0
    removeObject: pitchTier, analysisPitch, analysisMono
    exitScript: "Pitch analysis produced no usable voiced control points."
endif

# === Resynthesize Every Source Channel with the Same Target PitchTier ===
appendInfoLine: "Resynthesizing ", nch, " channel(s)..."

result = Create Sound from formula: originalName$ + "_breathing", nch, xmin, xmax, orig_sr, "0"

for ch from 1 to nch
    selectObject: original
    if nch = 1
        chanWork = Copy: originalName$ + "_breath_ch1"
    else
        chanWork = Extract one channel: ch
        Rename: originalName$ + "_breath_ch" + string$(ch)
    endif

    selectObject: chanWork
    chanManip = To Manipulation: time_step, minimum_pitch, maximum_pitch

    selectObject: pitchTier
    plusObject: chanManip
    Replace pitch tier

    selectObject: chanManip
    chanRes = Get resynthesis (overlap-add)

    selectObject: result
    Formula (part): xmin, xmax, ch, ch, "object['chanRes:0', 1, col]"

    removeObject: chanManip, chanWork, chanRes
endfor

removeObject: analysisPitch, analysisMono

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
    
    # Find range over populated visualization points.
    minShift = pitch_depth_semitones
    maxShift = -pitch_depth_semitones
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1
            if vizShifts#[vp] < minShift
                minShift = vizShifts#[vp]
            endif
            if vizShifts#[vp] > maxShift
                maxShift = vizShifts#[vp]
            endif
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
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
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
    Text: 0.5, "centre", 0.5, "half", "Components: centred breath + flutter + tremor + gasps -> emotional drive -> bounded tanh controller"
    
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
removeObject: pitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
outputChannels = Get number of channels
appendInfoLine: "Channels: ", outputChannels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result