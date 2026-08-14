# ============================================================
# Praat AudioTools - Granular_Displacement.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Granular Displacement - divides sound into equal grains
#   and applies different random delays to each grain. Creates
#   displaced, fragmented echo textures. Different from
#   Fractal_Feedback which uses hierarchical multi-layer
#   structure; this is a simpler single-layer grain effect.
#
# Changelog v0.2:
#   - Fixed delay formula (was looking forward)
#   - Added bounds checking
#   - Fixed selection and formula syntax
#   - Added wet/dry mix control
#   - Added visualization
#
# Changelog v0.4:
#   - Public form/defaults, output naming, and final selection are unchanged.
#   - Added a private zero-based work copy so non-zero source xmin does not
#     break concatenation or Formula(part) grain timing.
#   - Fixed 3+ channel input: silent tail now matches source channel count,
#     and the shared-grain branch processes every channel instead of row 1 only.
#   - Grain count is limited internally by available samples and a practical
#     ceiling; grainSizeSamp can no longer become zero.
#   - Final grain includes integer-division remainder samples.
#   - Custom delay bounds are ordered, kept to at least one sample, and
#     equal ranges avoid randomUniform(min=max).
#   - Custom amplitude bounds are ordered and capped at unity internally,
#     preventing recursive delayed reads from growing without bound.
#   - Safe Scale peak skips digital silence while preserving the original
#     non-silent normalization behavior.
#   - Caller-visible final selected object remains the result.
#
# Changelog v0.3:
#   - Fixed visualization: title and parameter line spilled off the left edge
#     (centred against a stale/seconds world window); now pinned to a 0..1 axis.
#     The result panel now shows its full length, including the echo tail.
#   - Wet/dry references the dry signal per-channel (object[id, row, col]).
#   - Guarded the delay range so max can never fall below min (tiny grains).
# ============================================================

form Granular Displacement
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Granular
        option Medium Granular
        option Heavy Granular
        option Extreme Granular
    
    comment === Grain Parameters ===
    positive Tail_duration_s 2.0
    natural Number_of_grains 8
    
    comment === Delay Range ===
    positive Delay_min_ms 5
    positive Delay_max_factor 0.25
    comment (max = grain_duration × factor)
    
    comment === Amplitude Range ===
    positive Amplitude_min 0.2
    positive Amplitude_max 0.8
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Scale_peak 0.95
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
nSamples = Get number of samples

# Private zero-based processing copy; caller's original Sound is untouched.
selectObject: original
workSource = Copy: "granular_displacement_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 2
    # Subtle Granular
    tail_duration_s = 1.5
    number_of_grains = 5
    delay_min_ms = 3
    delay_max_factor = 0.2
    amplitude_min = 0.15
    amplitude_max = 0.6
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Granular
    tail_duration_s = 2.0
    number_of_grains = 8
    delay_min_ms = 5
    delay_max_factor = 0.25
    amplitude_min = 0.2
    amplitude_max = 0.8
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Granular
    tail_duration_s = 2.5
    number_of_grains = 12
    delay_min_ms = 8
    delay_max_factor = 0.33
    amplitude_min = 0.25
    amplitude_max = 0.95
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Granular
    tail_duration_s = 3.5
    number_of_grains = 18
    delay_min_ms = 10
    delay_max_factor = 0.4
    amplitude_min = 0.3
    amplitude_max = 1.0
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Internal Custom guards; built-in presets are already within these limits.
ampLo = min(amplitude_min, amplitude_max)
ampHi = max(amplitude_min, amplitude_max)
effectiveAmpMin = min(ampLo, 1)
effectiveAmpMax = min(ampHi, 1)
if effectiveAmpMin > effectiveAmpMax
    effectiveAmpMin = effectiveAmpMax
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Calculate grain parameters.
# The created silent tail uses the same sampling frequency, so its sample
# count is the rounded duration in samples.
tailSamples = max(1, round(tail_duration_s * sr))
totalSamples = nSamples + tailSamples
totalDur = totalSamples / sr

effectiveGrains = min(number_of_grains, totalSamples)
if effectiveGrains > 4096
    effectiveGrains = 4096
endif
if effectiveGrains < 1
    effectiveGrains = 1
endif

grainSizeSamp = floor(totalSamples / effectiveGrains)
grainDur = grainSizeSamp / sr

delay_min_samp = max(1, round(delay_min_ms / 1000 * sr))
delay_max_samp = max(1, round(grainSizeSamp * delay_max_factor))
if delay_min_samp > delay_max_samp
    tmpDelay = delay_min_samp
    delay_min_samp = delay_max_samp
    delay_max_samp = tmpDelay
endif

# Keep recursive delayed reads inside the available Sound.
maxUsableDelay = max(1, totalSamples - 1)
delay_min_samp = min(delay_min_samp, maxUsableDelay)
delay_max_samp = min(delay_max_samp, maxUsableDelay)

# Pre-generate random delays and amplitudes for visualization.
for g from 1 to effectiveGrains
    if delay_min_samp = delay_max_samp
        grainDelay[g] = delay_min_samp
    else
        grainDelay[g] = round(randomUniform(delay_min_samp, delay_max_samp))
    endif

    if effectiveAmpMin = effectiveAmpMax
        grainAmp[g] = effectiveAmpMin
    else
        grainAmp[g] = randomUniform(effectiveAmpMin, effectiveAmpMax)
    endif
endfor

# === Info ===
writeInfoLine: "=== Granular Displacement ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Grains: ", effectiveGrains
if effectiveGrains <> number_of_grains
    appendInfoLine: "  (requested ", number_of_grains, "; internally limited)"
endif
appendInfoLine: "Grain duration: ", fixed$(grainDur * 1000, 1), " ms"
appendInfoLine: "Delay range: ", fixed$(delay_min_samp / sr * 1000, 3), "-", fixed$(delay_max_samp / sr * 1000, 1), " ms"
appendInfoLine: "Amplitude range: ", effectiveAmpMin, "-", effectiveAmpMax
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Grain details:"
for g from 1 to min(effectiveGrains, 10)
    appendInfoLine: "  Grain ", g, ": delay=", fixed$(grainDelay[g] / sr * 1000, 1), "ms, amp=", fixed$(grainAmp[g], 2)
endfor
if effectiveGrains > 10
    appendInfoLine: "  ... (", effectiveGrains - 10, " more)"
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create silent tail with the source channel count.
Create Sound from formula: "silent_tail", numChannels, 0, tail_duration_s, sr, "0"
silentTail = selected("Sound")

# workSource was created before silentTail, so Object-list order is source then tail.
selectObject: workSource, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left
    selectObject: leftChannel
    Copy: "wet_left"
    wetLeft = selected("Sound")
    
    for g from 1 to effectiveGrains
        delay = grainDelay[g]
        amp = grainAmp[g]
        
        startSamp = (g - 1) * grainSizeSamp + 1
        if g = effectiveGrains
            endSamp = totalSamples
        else
            endSamp = g * grainSizeSamp
        endif
        
        tStart = (startSamp - 1) / sr
        tEnd = endSamp / sr
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp)
        
        selectObject: wetLeft
        Formula (part): tStart, tEnd, 1, 1, "if col > " + delay_str$ + " then self + " + amp_str$ + " * self[col - " + delay_str$ + "] else self fi"
    endfor
    
    # Process right (different random values for decorrelation)
    selectObject: rightChannel
    Copy: "wet_right"
    wetRight = selected("Sound")
    
    for g from 1 to effectiveGrains
        # Generate decorrelated right-channel values with valid ranges.
        rLo = delay_min_samp * 1.1
        rHi = delay_max_samp * 0.9
        if rHi < rLo
            rHi = rLo
        endif
        if rLo = rHi
            delay = round(rLo)
        else
            delay = round(randomUniform(rLo, rHi))
        endif

        rAmpLo = effectiveAmpMin * 0.9
        rAmpHi = effectiveAmpMax * 0.95
        if rAmpHi < rAmpLo
            rAmpHi = rAmpLo
        endif
        if rAmpLo = rAmpHi
            amp = rAmpLo
        else
            amp = randomUniform(rAmpLo, rAmpHi)
        endif
        
        startSamp = (g - 1) * grainSizeSamp + 1
        if g = effectiveGrains
            endSamp = totalSamples
        else
            endSamp = g * grainSizeSamp
        endif
        
        tStart = (startSamp - 1) / sr
        tEnd = endSamp / sr
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp)
        
        selectObject: wetRight
        Formula (part): tStart, tEnd, 1, 1, "if col > " + delay_str$ + " then self + " + amp_str$ + " * self[col - " + delay_str$ + "] else self fi"
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: wetLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + ", row, col] * " + dry_str$
        
        selectObject: wetRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + ", row, col] * " + dry_str$
    endif
    
    # Normalize (same as v0.3 for non-silent channels).
    selectObject: wetLeft
    leftPeak = Get absolute extremum: 0, 0, "None"
    if leftPeak > 0
        Scale peak: scale_peak
    endif

    selectObject: wetRight
    rightPeak = Get absolute extremum: 0, 0, "None"
    if rightPeak > 0
        Scale peak: scale_peak
    endif
    
    # Combine
    selectObject: wetLeft, wetRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_granular_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, wetLeft, wetRight, extendedSound

else
    # === MONO / MULTICHANNEL SHARED-GRAIN PROCESSING ===
    if numChannels = 1
        appendInfoLine: "  Processing mono..."
    else
        appendInfoLine: "  Processing ", numChannels, "-channel shared-grain mode..."
    endif
    
    selectObject: extendedSound
    Copy: "wet_mono"
    wetMono = selected("Sound")
    
    for g from 1 to effectiveGrains
        delay = grainDelay[g]
        amp = grainAmp[g]
        
        startSamp = (g - 1) * grainSizeSamp + 1
        if g = effectiveGrains
            endSamp = totalSamples
        else
            endSamp = g * grainSizeSamp
        endif
        
        tStart = (startSamp - 1) / sr
        tEnd = endSamp / sr
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp)
        
        selectObject: wetMono
        Formula (part): tStart, tEnd, 1, numChannels, "if col > " + delay_str$ + " then self + " + amp_str$ + " * self[col - " + delay_str$ + "] else self fi"
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: wetMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + ", row, col] * " + dry_str$
    endif
    
    selectObject: wetMono
    sharedPeak = Get absolute extremum: 0, 0, "None"
    if sharedPeak > 0
        Scale peak: scale_peak
    endif
    Rename: originalName$ + "_granular_" + presetName$
    result = wetMono
    
    removeObject: extendedSound
endif

removeObject: workSource

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Granular Displacement: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Granular " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Grain structure
    Select outer viewport: 0, 8, 2.5, 3.8
    Select inner viewport: 0.6, 7.6, 2.6, 3.7
    
    Axes: 0, totalDur, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDur, 0, 1.2
    
    # Draw grains with delay/amplitude info
    for g from 1 to effectiveGrains
        gStart = (g - 1) * grainDur
        if g = effectiveGrains
            gEnd = totalDur
        else
            gEnd = g * grainDur
        endif
        
        # Color by amplitude
        r = 0.5 + grainAmp[g] * 0.3
        gr = 0.6 - grainAmp[g] * 0.1
        b = 0.5
        
        # Draw grain box
        Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(gr, 2) + ", " + fixed$(b, 2) + "}", gStart + 0.002, gEnd - 0.002, 0.1, 0.9
        
        # Draw boundary
        Colour: "White"
        Draw line: gEnd, 0.1, gEnd, 0.9
        
        # Draw delay indicator (arrow length = delay)
        delayMs = grainDelay[g] / sr * 1000
        maxDelayMs = delay_max_samp / sr * 1000
        arrowLen = (delayMs / maxDelayMs) * grainDur * 0.8
        
        Colour: "{0.3, 0.3, 0.5}"
        gMid = (gStart + gEnd) / 2
        Draw arrow: gMid, 0.5, gMid + arrowLen, 0.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Grains"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.4, 0.4, 0.4}"
    Text: totalDur * 0.5, "centre", 1.1, "half", "Arrow length = delay time | Color intensity = amplitude"
    
    # Parameters
    Select outer viewport: 0, 8, 3.9, 4.3
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Grains: " + string$(effectiveGrains) + " | Duration: " + fixed$(grainDur * 1000, 0) + "ms | Delay: " + fixed$(delay_min_samp / sr * 1000, 1) + "-" + fixed$(delay_max_samp / sr * 1000, 0) + "ms"
    
    Font size: 10
    Colour: "Black"
endif

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