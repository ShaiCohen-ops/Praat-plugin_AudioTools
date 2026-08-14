# ============================================================
# Praat AudioTools - Spectral_Decay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.1 (2026 review)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Decay Reverb - convolution reverb with a
#   chirp-amplitude-modulated Poisson impulse response and
#   Hann-band spectral shaping. The IR has exponential decay;
#   the modulation frequency increases linearly through time.
#
# Changelog v0.3.1:
#   - Fixed Formula conditional syntax: nested if/else/fi is used
#     because elsif is valid in scripts but not in Formula expressions
#
# Changelog v0.3:
#   - Corrected chirp phase: modulation now performs a true
#     linear-frequency sweep instead of a constant-frequency sine
#   - Wet fade is applied before wet/dry mixing (dry path untouched)
#   - Wet peak control is down-only; quiet inputs are never boosted
#   - Stereo wet peak control uses one shared gain, preserving image
#   - Final peak protection is down-only and bypassed at 0% wet
#   - Bandpass is applied to the IR before convolution for efficiency
#   - Convolution uses the source without the appended silent tail
#   - Output duration is always source duration + requested tail
#   - Time-based object access makes wet/dry alignment robust
#   - Added mono/stereo, decay-base, cutoff and Nyquist guards
#   - Custom fade duration is clamped to the tail duration
#   - Visualization now displays the full output tail
# ============================================================

form Spectral Decay Reverb
    comment Select a mono or stereo Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Decay
        option Medium Decay
        option Heavy Decay
        option Extreme Decay

    comment === IR Parameters ===
    positive Tail_duration_s 2.0
    positive Impulse_duration_s 3.0
    positive Poisson_density 2000
    positive Decay_base 110

    comment === Spectral Filtering ===
    positive Low_cutoff_Hz 100
    positive High_cutoff_Hz 4000
    positive Smoothing_Hz 100

    comment === Mix ===
    real Wet_dry_percent 50
    comment (0 = dry only, 100 = wet only)

    comment === Output ===
    positive Fadeout_duration_s 1.2
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
originalStart = Get start time
originalEnd = Get end time
sr = Get sampling frequency
numChannels = Get number of channels

if numChannels <> 1 and numChannels <> 2
    exitScript: "Spectral Decay supports mono or stereo Sounds only."
endif

# Work on a zero-based copy so convolution and mixing time domains align.
selectObject: original
Extract part: originalStart, originalEnd, "rectangular", 1, "no"
workingSound = selected("Sound")
Rename: originalName$ + "_spectral_work"

# === Apply Presets ===
if preset = 2
    # Subtle Decay
    tail_duration_s = 1.5
    impulse_duration_s = 2.0
    poisson_density = 1200
    decay_base = 150
    low_cutoff_Hz = 120
    high_cutoff_Hz = 3500
    smoothing_Hz = 80
    fadeout_duration_s = 0.8
    wet_dry_percent = 35
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Decay
    tail_duration_s = 2.0
    impulse_duration_s = 3.0
    poisson_density = 2000
    decay_base = 110
    low_cutoff_Hz = 100
    high_cutoff_Hz = 4000
    smoothing_Hz = 100
    fadeout_duration_s = 1.2
    wet_dry_percent = 50
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Decay
    tail_duration_s = 3.0
    impulse_duration_s = 4.5
    poisson_density = 3000
    decay_base = 80
    low_cutoff_Hz = 80
    high_cutoff_Hz = 4500
    smoothing_Hz = 120
    fadeout_duration_s = 1.8
    wet_dry_percent = 65
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Decay
    tail_duration_s = 4.5
    impulse_duration_s = 6.5
    poisson_density = 4500
    decay_base = 50
    low_cutoff_Hz = 60
    high_cutoff_Hz = 5000
    smoothing_Hz = 150
    fadeout_duration_s = 2.5
    wet_dry_percent = 80
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Parameter guards ===
if decay_base <= 1
    removeObject: workingSound
    exitScript: "Decay base must be greater than 1."
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Keep the requested upper cutoff safely below Nyquist.
nyquist = sr / 2
maxHigh = nyquist * 0.95
cutoffAdjusted = 0
if high_cutoff_Hz > maxHigh
    high_cutoff_Hz = maxHigh
    cutoffAdjusted = 1
endif

if low_cutoff_Hz >= high_cutoff_Hz
    removeObject: workingSound
    exitScript: "Low cutoff must be lower than the effective high cutoff (and below Nyquist)."
endif

# Fade only the tail; never fade the dry source for custom settings.
effectiveFade = fadeout_duration_s
if effectiveFade > tail_duration_s
    effectiveFade = tail_duration_s
endif

# Fixed chirp parameters.  The value after each start frequency is
# a true sweep rate in Hz/s (instantaneous f = f0 + rate * t).
chirpStartL = 150
chirpRateL = 20
chirpDepthL = 0.70
chirpStartR = 140
chirpRateR = 22
chirpDepthR = 0.65

# === Info ===
writeInfoLine: "=== Spectral Decay Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "IR duration: ", impulse_duration_s, " s"
appendInfoLine: "Poisson density: ", poisson_density, " events/s"
appendInfoLine: "Decay base: ", decay_base
appendInfoLine: "Bandpass: ", fixed$(low_cutoff_Hz, 1), " - ", fixed$(high_cutoff_Hz, 1), " Hz"
if cutoffAdjusted
    appendInfoLine: "  (High cutoff reduced to stay below Nyquist.)"
endif
appendInfoLine: "Chirp L: ", chirpStartL, " Hz + ", chirpRateL, " Hz/s"
if numChannels = 2
    appendInfoLine: "Chirp R: ", chirpStartR, " Hz + ", chirpRateR, " Hz/s"
endif
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tail_duration_s
fade_start = totalDur - effectiveFade
total_str$ = string$(totalDur)
fade_str$ = string$(effectiveFade)
start_str$ = string$(fade_start)
wet_str$ = string$(wet_level)
dry_str$ = string$(dry_level)

# Create dry path with the requested silent tail.
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

selectObject: workingSound, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

# Strings used in IR formulas
decay_str$ = string$(decay_base)
chirpStartL_str$ = string$(chirpStartL)
chirpRateL_str$ = string$(chirpRateL)
chirpDepthL_str$ = string$(chirpDepthL)
chirpStartR_str$ = string$(chirpStartR)
chirpRateR_str$ = string$(chirpRateR)
chirpDepthR_str$ = string$(chirpDepthR)

# Fast path: at 0% wet, return the dry signal plus silent tail without
# generating an IR or performing convolution.
if wet_level = 0
    selectObject: extendedSound
    Copy: originalName$ + "_spectral_" + presetName$
    result = selected("Sound")
    removeObject: extendedSound, workingSound

else
    if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."

    # Source channels for convolution: do NOT convolve the silent tail.
    selectObject: workingSound
    Extract one channel: 1
    sourceLeft = selected("Sound")

    selectObject: workingSound
    Extract one channel: 2
    sourceRight = selected("Sound")

    # Dry channels define the exact requested output duration.
    selectObject: extendedSound
    Extract one channel: 1
    dryLeft = selected("Sound")

    selectObject: extendedSound
    Extract one channel: 2
    dryRight = selected("Sound")

    # === LEFT IR ===
    Create Poisson process: "poisson_left", 0, impulse_duration_s, poisson_density
    poissonLeft = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.035, 2800
    irLeft = selected("Sound")

    # True linear chirp: phase = 2*pi*(f0*t + 0.5*k*t^2),
    # so instantaneous modulation frequency is f0 + k*t.
    Formula: "self * " + decay_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + chirpDepthL_str$ + "*sin(2*pi*(" + chirpStartL_str$ + "*(x-xmin) + 0.5*" + chirpRateL_str$ + "*(x-xmin)^2)))"

    # Spectrally shape the IR before convolution (same LTI intent,
    # less work than filtering the longer convolved output).
    Filter (pass Hann band): low_cutoff_Hz, high_cutoff_Hz, smoothing_Hz
    irLeftFiltered = selected("Sound")
    removeObject: irLeft

    selectObject: sourceLeft, irLeftFiltered
    Convolve: "sum", "zero"
    wetLeft = selected("Sound")

    # === RIGHT IR ===
    Create Poisson process: "poisson_right", 0, impulse_duration_s * 0.93, poisson_density * 0.95
    poissonRight = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.032, 2600
    irRight = selected("Sound")

    decay_R = decay_base * 0.95
    decay_R_str$ = string$(decay_R)
    Formula: "self * " + decay_R_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + chirpDepthR_str$ + "*sin(2*pi*(" + chirpStartR_str$ + "*(x-xmin) + 0.5*" + chirpRateR_str$ + "*(x-xmin)^2)))"

    Filter (pass Hann band): low_cutoff_Hz * 1.2, high_cutoff_Hz * 0.95, smoothing_Hz * 0.9
    irRightFiltered = selected("Sound")
    removeObject: irRight

    selectObject: sourceRight, irRightFiltered
    Convolve: "sum", "zero"
    wetRight = selected("Sound")

    # Fade WET only. Anything beyond requested output duration is muted.
    selectObject: wetLeft
    Formula: "if x >= " + total_str$ + " then 0 else if x > " + start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + start_str$ + ")/" + fade_str$ + ")) else self fi fi"

    selectObject: wetRight
    Formula: "if x >= " + total_str$ + " then 0 else if x > " + start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + start_str$ + ")/" + fade_str$ + ")) else self fi fi"

    # Down-only wet protection with ONE gain for both channels.
    selectObject: wetLeft
    wetPeak = Get absolute extremum: 0, totalDur, "none"
    selectObject: wetRight
    wetPeakR = Get absolute extremum: 0, totalDur, "none"
    if wetPeakR > wetPeak
        wetPeak = wetPeakR
    endif

    wetGain = 1
    if wetPeak > 0.95
        wetGain = 0.95 / wetPeak
    endif
    wetGain_str$ = string$(wetGain)

    if wetGain < 1
        selectObject: wetLeft
        Formula: "self * " + wetGain_str$
        selectObject: wetRight
        Formula: "self * " + wetGain_str$
    endif

    # Mix on copies of the dry path. Time interpolation keeps alignment
    # correct even if the IR's first sample is not exactly at t=0.
    wetLeft_str$ = string$(wetLeft)
    selectObject: dryLeft
    Copy: "spectral_mix_left"
    mixLeft = selected("Sound")
    Formula: "self * " + dry_str$ + " + object(" + wetLeft_str$ + ", x, 1) * " + wet_str$

    wetRight_str$ = string$(wetRight)
    selectObject: dryRight
    Copy: "spectral_mix_right"
    mixRight = selected("Sound")
    Formula: "self * " + dry_str$ + " + object(" + wetRight_str$ + ", x, 1) * " + wet_str$

    # Combine first, then peak-protect once so stereo balance is preserved.
    selectObject: mixLeft, mixRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_spectral_" + presetName$

    if wet_level > 0
        resultPeak = Get absolute extremum: 0, 0, "none"
        if resultPeak > 0.98
            Scale peak: 0.98
        endif
    endif

    # Cleanup
    removeObject: sourceLeft, sourceRight, dryLeft, dryRight
    removeObject: poissonLeft, poissonRight, irLeftFiltered, irRightFiltered
    removeObject: wetLeft, wetRight, mixLeft, mixRight
    removeObject: extendedSound, workingSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."

    Create Poisson process: "poisson_mono", 0, impulse_duration_s, poisson_density
    poissonMono = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.035, 2800
    irMono = selected("Sound")

    Formula: "self * " + decay_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + chirpDepthL_str$ + "*sin(2*pi*(" + chirpStartL_str$ + "*(x-xmin) + 0.5*" + chirpRateL_str$ + "*(x-xmin)^2)))"

    Filter (pass Hann band): low_cutoff_Hz, high_cutoff_Hz, smoothing_Hz
    irMonoFiltered = selected("Sound")
    removeObject: irMono

    # Convolve source only; the dry tail is not needlessly processed.
    selectObject: workingSound, irMonoFiltered
    Convolve: "sum", "zero"
    wetMono = selected("Sound")

    # Fade WET only and mute anything after requested output duration.
    Formula: "if x >= " + total_str$ + " then 0 else if x > " + start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + start_str$ + ")/" + fade_str$ + ")) else self fi fi"

    # Down-only wet protection: never boost a quiet convolution.
    wetPeak = Get absolute extremum: 0, totalDur, "none"
    if wetPeak > 0.95
        wetGain = 0.95 / wetPeak
        wetGain_str$ = string$(wetGain)
        Formula: "self * " + wetGain_str$
    endif

    # Mix on the fixed-duration dry path.
    wetMono_str$ = string$(wetMono)
    selectObject: extendedSound
    Copy: originalName$ + "_spectral_" + presetName$
    result = selected("Sound")
    Formula: "self * " + dry_str$ + " + object(" + wetMono_str$ + ", x, 1) * " + wet_str$

    # Down-only final peak protection; 0% wet remains a true dry copy.
    if wet_level > 0
        resultPeak = Get absolute extremum: 0, 0, "none"
        if resultPeak > 0.98
            Scale peak: 0.98
        endif
    endif

    # Cleanup
    removeObject: poissonMono, irMonoFiltered, wetMono
    removeObject: extendedSound, workingSound
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Decay Reverb: " + originalName$ + " (" + presetName$ + ")"

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

    # Result waveform including tail
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, totalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectral " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"

    # Bandpass filter shape
    Select outer viewport: 0, 4, 2.5, 4.0
    Select inner viewport: 0.6, 3.7, 2.7, 3.85

    Axes: 0, sr / 2 / 1000, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, sr / 2 / 1000, 0, 1.2

    Colour: "{0.5, 0.7, 0.9}"
    Line width: 2

    lowK = low_cutoff_Hz / 1000
    highK = high_cutoff_Hz / 1000
    smoothK = smoothing_Hz / 1000

    Draw line: 0, 0, lowK - smoothK, 0
    Draw line: lowK - smoothK, 0, lowK, 1
    Draw line: lowK, 1, highK, 1
    Draw line: highK, 1, highK + smoothK, 0
    Draw line: highK + smoothK, 0, sr / 2 / 1000, 0

    Line width: 1
    Paint rectangle: "{0.8, 0.9, 1.0}", lowK, highK, 0, 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (kHz)"

    Font size: 8
    Select outer viewport: 0, 4, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "BANDPASS FILTER"

    # Decay envelope with the corrected linear chirp modulation
    Select outer viewport: 4, 8, 2.5, 4.0
    Select inner viewport: 4.5, 7.7, 2.7, 3.85

    Axes: 0, impulse_duration_s, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, impulse_duration_s, -1.2, 1.2

    Colour: "{0.6, 0.5, 0.7}"
    Line width: 1.5

    numPoints = 200
    for i from 1 to numPoints
        t = (i - 1) / (numPoints - 1) * impulse_duration_s
        tNorm = t / impulse_duration_s
        chirpPhase = 2 * pi * (chirpStartL * t + 0.5 * chirpRateL * t^2)
        envelope = decay_base ^ (-tNorm) * (1 + chirpDepthL * sin(chirpPhase))

        if envelope > 1.2
            envelope = 1.2
        elsif envelope < -1.2
            envelope = -1.2
        endif

        if i > 1
            Draw line: prevT, prevEnv, t, envelope
        endif
        prevT = t
        prevEnv = envelope
    endfor

    # Exponential decay envelope only (dotted)
    Colour: "{0.8, 0.6, 0.4}"
    Dotted line
    for i from 1 to numPoints
        t = (i - 1) / (numPoints - 1) * impulse_duration_s
        tNorm = t / impulse_duration_s
        envelope = decay_base ^ (-tNorm)

        if i > 1
            Draw line: prevT2, prevEnv2, t, envelope
        endif
        prevT2 = t
        prevEnv2 = envelope
    endfor
    Solid line

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    Font size: 8
    Select outer viewport: 4, 8, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "IR ENVELOPE (linear chirp modulated)"

    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "IR: " + fixed$(impulse_duration_s, 1) + "s | Density: " + string$(poisson_density) + " | Decay: " + string$(decay_base) + " | Band: " + fixed$(low_cutoff_Hz, 0) + "-" + fixed$(high_cutoff_Hz, 0) + "Hz"

    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
outputDur = Get total duration
appendInfoLine: "Output duration: ", fixed$(outputDur, 3), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
