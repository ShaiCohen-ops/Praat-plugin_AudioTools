# ============================================================
# Praat AudioTools - Harmonic_Decay_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.1 (2026)
# v0.6.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Decay Reverb - creates echoes at harmonically-
#   related delay times using power law spacing. Delay times
#   follow: delay[k] = base × k^(1/spread), creating dense
#   early reflections that spread out over time - similar to
#   natural room mode decay. Amplitude decays exponentially
#   with random variation for organic texture.
#
# Changelog v0.2:
#   - Fixed selection and formula syntax
#   - Added proper stereo processing
#   - Added wet/dry mix control
#   - Added visualization
#   - Fixed variable name mismatches
#
# Changelog v0.3:
#   - Echoes past the tail (silent, since self(x-delay) reads before t=0) are
#     no longer wasted: when power-law spacing overshoots, the whole pattern is
#     scaled to fit the tail so every echo is used (Extreme wasted ~3/4 before).
#   - Fixed visualization: title and parameter line spilled off the left edge
#     (centred against a stale/seconds world window); now pinned to a 0..1 axis.
#     The result panel now shows its full length, including the reverb tail.
#   - Wet/dry references the dry signal per-channel (object[id, row, col]).
#
# Changelog v0.4:
#   - Stereo output from any source: a mono input is duplicated to two channels
#     before processing, so the decorrelated L/R reverb produces a wide stereo
#     tail with a mono-compatible (centred) dry signal.
# Changelog v0.5:
#   - Public form/defaults, output naming, and final selection are unchanged.
#   - Corrected Wet/Dry semantics: 0% = dry only, 100% = harmonic-decay
#     reflections only. The internal processed buffer still contains dry +
#     reflections; the mixer explicitly removes the embedded dry component.
#   - Added a private zero-based work copy for non-zero source xmin.
#   - Fixed 3+ channel input: silent tail now matches the source channel count;
#     the shared-processing branch applies every echo to every channel.
#   - Fadeout is limited to the reverb tail, so Custom values can no longer
#     fade the original source before it ends.
#   - Echo delay generation is evaluated safely in the log domain when the
#     power-law pattern must be scaled to the tail, preventing overflow for
#     pathological Custom spread values while preserving the same curve.
#   - Echo delays are kept at least two samples long, avoiding near-zero-delay
#     self-gain artifacts after extreme pattern compression.
#   - Individual recursive echo gains are capped below unity for stability;
#     built-in presets are unaffected in normal operation.
#   - Echo processing uses Formula (part) only from each delay onward, preserving
#     the same recurrence while avoiding work on samples that cannot change.
#   - Final Scale peak is a safety ceiling only, so quiet dry/effect output is
#     not boosted and Wet/Dry endpoints remain level-faithful.
#
# ============================================================

form Harmonic Decay Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Harmonic
        option Medium Harmonic
        option Heavy Harmonic
        option Extreme Harmonic
    
    comment === Reverb Parameters ===
    positive Tail_duration_s 1.5
    natural Number_of_echoes 48
    positive Base_delay_s 0.05
    
    comment === Harmonic Spacing ===
    positive Harmonic_spread 1.2
    comment (higher = more compressed spacing)
    
    comment === Amplitude ===
    positive Decay_factor 0.92
    positive Amplitude_mean 0.25
    positive Amplitude_stddev 0.08
    
    comment === Fadeout ===
    positive Fadeout_duration_s 1.0
    
    comment === Mix ===
    real Wet_dry_percent 60
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
workSource = Copy: "harmonic_decay_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 2
    # Subtle Harmonic
    tail_duration_s = 1.0
    number_of_echoes = 30
    base_delay_s = 0.04
    decay_factor = 0.94
    harmonic_spread = 1.4
    amplitude_mean = 0.18
    amplitude_stddev = 0.05
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Harmonic
    tail_duration_s = 1.5
    number_of_echoes = 48
    base_delay_s = 0.05
    decay_factor = 0.92
    harmonic_spread = 1.2
    amplitude_mean = 0.25
    amplitude_stddev = 0.08
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Harmonic
    tail_duration_s = 2.0
    number_of_echoes = 70
    base_delay_s = 0.06
    decay_factor = 0.9
    harmonic_spread = 1.0
    amplitude_mean = 0.32
    amplitude_stddev = 0.1
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Harmonic
    tail_duration_s = 3.0
    number_of_echoes = 100
    base_delay_s = 0.08
    decay_factor = 0.88
    harmonic_spread = 0.8
    amplitude_mean = 0.38
    amplitude_stddev = 0.12
    fadeout_duration_s = 1.8
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Keep fadeout entirely inside the appended reverb tail.
effectiveFadeoutDuration = min(fadeout_duration_s, tail_duration_s)

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Pre-calculate delays and amplitudes for visualization.
# Evaluate the decision to scale in the log domain, so tiny Custom spread
# values cannot overflow k^power before the tail-fit step has a chance to run.
harmonic_power = 1 / harmonic_spread
usableSpan = tail_duration_s * 0.95
minEchoDelay = 2 / sr
logRawMaxDelay = ln(base_delay_s) + harmonic_power * ln(number_of_echoes)
logUsableSpan = ln(usableSpan)
delayScale = 1
patternNeedsScaling = 0
if logRawMaxDelay > logUsableSpan
    patternNeedsScaling = 1
    logScale = logUsableSpan - logRawMaxDelay
    if logScale > -700
        delayScale = exp(logScale)
    else
        delayScale = 0
    endif
endif

for k from 1 to number_of_echoes
    if patternNeedsScaling
        # Algebraically identical to base*k^power*delayScale, but overflow-safe.
        echoDelay[k] = usableSpan * exp(harmonic_power * (ln(k) - ln(number_of_echoes)))
    else
        echoDelay[k] = base_delay_s * exp(harmonic_power * ln(k))
    endif
    if echoDelay[k] < minEchoDelay
        echoDelay[k] = minEchoDelay
    endif

    echoAmp[k] = (decay_factor ^ k) * randomGauss(amplitude_mean, amplitude_stddev)
    if echoAmp[k] < 0
        echoAmp[k] = 0.01
    elsif echoAmp[k] > 0.99
        echoAmp[k] = 0.99
    endif
endfor

# Find max delay for info
maxDelay = echoDelay[number_of_echoes]

# === Info ===
writeInfoLine: "=== Harmonic Decay Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Echoes: ", number_of_echoes
appendInfoLine: "Base delay: ", base_delay_s * 1000, " ms"
appendInfoLine: "Harmonic spread: ", harmonic_spread, " (power=", fixed$(harmonic_power, 3), ")"
appendInfoLine: "Decay factor: ", decay_factor
appendInfoLine: "Max delay: ", fixed$(maxDelay * 1000, 1), " ms"
if delayScale < 1
    appendInfoLine: "  (delays scaled x", fixed$(delayScale, 3), " so all ", number_of_echoes, " echoes fit the tail)"
endif
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "First 10 echo delays:"
for k from 1 to min(10, number_of_echoes)
    appendInfoLine: "  ", k, ": ", fixed$(echoDelay[k] * 1000, 1), " ms (amp=", fixed$(echoAmp[k], 3), ")"
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tail_duration_s

# Create silent tail with exactly the source channel count.
Create Sound from formula: "silent_tail", numChannels, 0, tail_duration_s, sr, "0"
silentTail = selected("Sound")

# workSource was created before silentTail, so Object-list order is source then tail.
selectObject: workSource, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

# Stereo output even from a mono source: duplicate to two channels so the
# decorrelated L/R reverb below produces a wide stereo field (the dry stays
# centred, so the result is mono-compatible).
if numChannels = 1
    selectObject: extendedSound
    Convert to stereo
    extendedMono = extendedSound
    extendedSound = selected("Sound")
    removeObject: extendedMono
    numChannels = 2
endif

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
    Copy: "reverb_left"
    reverbLeft = selected("Sound")
    
    for k from 1 to number_of_echoes
        delay = echoDelay[k]
        amp = echoAmp[k]
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp)
        
        selectObject: reverbLeft
        Formula (part): delay, totalDur, 1, 1, "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
    endfor
    
    # Process right (slightly different random amplitudes for decorrelation)
    selectObject: rightChannel
    Copy: "reverb_right"
    reverbRight = selected("Sound")
    
    for k from 1 to number_of_echoes
        delay = echoDelay[k] * randomUniform(0.98, 1.02)
        amp = (decay_factor ^ k) * randomGauss(amplitude_mean * 0.95, amplitude_stddev)
        if amp < 0
            amp = 0.01
        elsif amp > 0.99
            amp = 0.99
        endif
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp)
        
        selectObject: reverbRight
        Formula (part): delay, totalDur, 1, 1, "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
    endfor
    
    # True dry/effect crossfade. reverbLeft/Right currently contain dry + reflections.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_str$ = string$(leftChannel)
    right_str$ = string$(rightChannel)

    selectObject: reverbLeft
    Formula: "object[" + left_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + left_str$ + ", row, col]) * " + wet_str$

    selectObject: reverbRight
    Formula: "object[" + right_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + right_str$ + ", row, col]) * " + wet_str$
    
    # Apply fadeout
    fade_start = totalDur - effectiveFadeoutDuration
    fade_str$ = string$(effectiveFadeoutDuration)
    start_str$ = string$(fade_start)
    
    selectObject: reverbLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    leftPeak = Get absolute extremum: 0, 0, "None"
    if leftPeak > 0.95
        Scale peak: 0.95
    endif

    selectObject: reverbRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    rightPeak = Get absolute extremum: 0, 0, "None"
    if rightPeak > 0.95
        Scale peak: 0.95
    endif
    
    # Combine
    selectObject: reverbLeft, reverbRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_harmonic_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, reverbLeft, reverbRight, extendedSound

else
    # === MULTICHANNEL SHARED PROCESSING ===
    appendInfoLine: "  Processing ", numChannels, "-channel shared-decay mode..."
    
    selectObject: extendedSound
    Copy: "reverb_mono"
    reverbMono = selected("Sound")
    
    for k from 1 to number_of_echoes
        delay = echoDelay[k]
        amp = echoAmp[k]
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp)
        
        selectObject: reverbMono
        Formula (part): delay, totalDur, 1, numChannels, "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
    endfor
    
    # True dry/effect crossfade. reverbMono contains dry + reflections.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    ext_str$ = string$(extendedSound)

    selectObject: reverbMono
    Formula: "object[" + ext_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + ext_str$ + ", row, col]) * " + wet_str$
    
    # Apply fadeout
    fade_start = totalDur - effectiveFadeoutDuration
    fade_str$ = string$(effectiveFadeoutDuration)
    start_str$ = string$(fade_start)
    
    selectObject: reverbMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    sharedPeak = Get absolute extremum: 0, 0, "None"
    if sharedPeak > 0.95
        Scale peak: 0.95
    endif
    Rename: originalName$ + "_harmonic_" + presetName$
    result = reverbMono
    
    removeObject: extendedSound
endif

removeObject: workSource

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
    Text: 0.5, "centre", 0.5, "half", "Harmonic Decay Reverb: " + originalName$ + " (" + presetName$ + ")" + " | v0.6.1"
    
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
    Colour: "{0.6, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Harmonic " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    
    # Harmonic delay pattern
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.60, 7.70, 2.6, 3.9
    
    # Find max amplitude for scaling
    maxAmp = 0
    for k from 1 to number_of_echoes
        if echoAmp[k] > maxAmp
            maxAmp = echoAmp[k]
        endif
    endfor
    
    Axes: 0, maxDelay * 1000, 0, maxAmp * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxDelay * 1000, 0, maxAmp * 1.2
    
    # Draw echo impulses
    for k from 1 to number_of_echoes
        delayMs = echoDelay[k] * 1000
        amp = echoAmp[k]
        
        # Color gradient based on delay
        r = 0.5 + (k / number_of_echoes) * 0.3
        g = 0.4
        b = 0.6 - (k / number_of_echoes) * 0.2
        
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        Draw line: delayMs, 0, delayMs, amp
        Paint circle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", delayMs, amp, maxDelay * 8
    endfor
    
    # Draw exponential decay envelope
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    for k from 2 to number_of_echoes
        d1 = echoDelay[k-1] * 1000
        d2 = echoDelay[k] * 1000
        a1 = (decay_factor ^ (k-1)) * amplitude_mean
        a2 = (decay_factor ^ k) * amplitude_mean
        Draw line: d1, a1, d2, a2
    endfor
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.6, 3.9
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amplitude"
    Select inner viewport: 0.60, 7.70, 2.6, 3.9
    Axes: 0, maxDelay * 1000, 0, maxAmp * 1.2
    Text bottom: "yes", "Delay (ms)"
    
    # Legend
    Font size: 6
    Colour: "{0.6, 0.4, 0.5}"
    Text: maxDelay * 900, "centre", maxAmp * 1.1, "half", "Harmonic echoes"
    Colour: "{0.7, 0.7, 0.7}"
    Text: maxDelay * 900, "centre", maxAmp * 1.0, "half", "Decay envelope"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Echoes: " + string$(number_of_echoes) + " | Base: " + fixed$(base_delay_s * 1000, 0) + "ms | Spread: " + fixed$(harmonic_spread, 2) + " | Decay: " + fixed$(decay_factor, 2)
    
    Font size: 10
    Colour: "Black"

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, 4.60, 5.60
    Select inner viewport: 0.60, 7.70, 4.67, 5.53
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Harmonic decay map shows frequency-dependent tail construction"
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Colour is semantic: neutral reference versus resonant decay structure"

    # Restore full-page viewport before leaving visualization.
    Select inner viewport: 0.60, 7.70, 4.67, 5.53
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 5.70
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

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
